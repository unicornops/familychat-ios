#!/usr/bin/env bash
#
# Copyright 2026 Unicorn Operations Ltd.
#
# SPDX-License-Identifier: AGPL-3.0-only
#
# Merges the newest stable upstream release tag into the default branch, on a branch of its own, and
# opens a pull request for a person to review. When the merge conflicts, it pushes nothing and opens
# (or updates) an issue labelled `upstream-sync` instead. It never merges anything into the default
# branch itself. See "Merging upstream releases" in the README.
#
# The merge runs in a temporary worktree, so the checkout it is started from is never touched.
#
# Run by .github/workflows/upstream-sync.yml, and runnable locally from any checkout of this repository:
#
#   GITHUB_REPOSITORY=unicornops/familychat-ios DRY_RUN=true TAG=release/26.09.2 \
#     .github/workflows/scripts/upstream-sync.sh
#
# Environment:
#   GITHUB_REPOSITORY  owner/name of this repository (required)
#   GH_TOKEN           token for gh and for pushing: contents + pull requests + issues write on this
#                      repository only. Pushes made with GITHUB_TOKEN do not trigger CI, so it is a
#                      fine-grained token or a GitHub App token. With DRY_RUN=true, gh's own login works too
#   TAG                upstream tag to merge, release/YY.MM.N (default: upstream's latest stable release)
#   DRY_RUN            "true" to do everything locally and print the PR or issue instead of creating it
#   UPSTREAM_REPO      default element-hq/element-x-ios
#   BASE_BRANCH        default familychat
#   REMOTE             the remote pointing at this repository, default origin

# The single-quoted backticks are Markdown, not command substitutions.
# shellcheck disable=SC2016

set -euo pipefail

upstream_repo="${UPSTREAM_REPO:-element-hq/element-x-ios}"
base_branch="${BASE_BRANCH:-familychat}"
remote="${REMOTE:-origin}"
repo="${GITHUB_REPOSITORY:?GITHUB_REPOSITORY must be set to owner/name}"
dry_run="${DRY_RUN:-false}"
label="upstream-sync"

# Paths the fork deleted on purpose. Upstream edits to them are modify/delete conflicts, which are resolved by
# keeping the deletion. Anything else that conflicts goes to a person.
deleted_on_purpose_regex='^(\.github/workflows/[^/]+\.ya?ml|Enterprise)$'

# Upstream releases are tagged release/YY.MM.N; pre-releases use the same format and are told apart by the GitHub
# release.
tag_regex='^release/[0-9]{2}\.[0-9]{2}\.[0-9]+$'

# Screenshots are Git LFS pointers. The merge only needs the pointers (the fork shares upstream's LFS objects), so
# never download them, even where git-lfs is installed.
export GIT_LFS_SKIP_SMUDGE=1

work_dir="$(mktemp -d)"
tree="$work_dir/tree"
cleanup() {
  if [[ -d "$tree" ]]; then
    git worktree remove --force "$tree" > /dev/null 2>&1 || true
  fi
  rm -rf "$work_dir"
}
trap cleanup EXIT

log() { echo "upstream-sync: $*" >&2; }

summary() {
  if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
    cat >> "$GITHUB_STEP_SUMMARY"
  else
    cat >&2
  fi
}

# --- Which tag ----------------------------------------------------------------------------------------------------

if [[ -n "${TAG:-}" ]]; then
  tag="$TAG"
else
  # The latest release excludes drafts and pre-releases.
  tag="$(gh api "repos/$upstream_repo/releases/latest" --jq .tag_name)"
fi

if [[ ! "$tag" =~ $tag_regex ]]; then
  log "'$tag' is not a release/YY.MM.N release tag"
  exit 1
fi
version="${tag#release/}"

release_json="$work_dir/release.json"
gh api "repos/$upstream_repo/releases/tags/$tag" > "$release_json"
if [[ "$(jq -r '.prerelease or .draft' "$release_json")" != "false" ]]; then
  log "$tag is a pre-release or a draft on $upstream_repo, only stable releases are merged"
  exit 1
fi

git fetch --quiet "$remote" "+refs/heads/$base_branch:refs/remotes/$remote/$base_branch"
git fetch --quiet --no-tags "https://github.com/$upstream_repo.git" "+refs/tags/$tag:refs/tags/$tag"
base_ref="$remote/$base_branch"

if git merge-base --is-ancestor "$tag" "$base_ref"; then
  log "$base_branch already contains $tag, nothing to do"
  echo "\`$base_branch\` already contains \`$tag\`, nothing to do." | summary
  exit 0
fi

branch="upstream/$version"
if [[ "$dry_run" != "true" ]] && git ls-remote --exit-code --heads "$remote" "$branch" > /dev/null; then
  log "$branch already exists on $remote, its pull request is waiting for review"
  echo "\`$branch\` already exists, its pull request is waiting for review." | summary
  exit 0
fi

# --- Security fast path -------------------------------------------------------------------------------------------

version_regex="(^|[^0-9.])v?${version//./[.]}([^0-9]|$)"
security_reasons=()
if jq -r '.body // ""' "$release_json" | grep -Eiq 'security|CVE-[0-9]{4}-|GHSA-'; then
  security_reasons+=("the release notes mention a security fix")
fi
advisories="$(gh api --paginate "repos/$upstream_repo/security-advisories?state=published" \
  --jq ".[] | select([.vulnerabilities[]?.patched_versions // \"\"] | any(test(\"$version_regex\"))) | .ghsa_id")"
if [[ -n "$advisories" ]]; then
  security_reasons+=("published advisories patched in $tag: $(echo "$advisories" | paste -sd ' ')")
fi
is_security=false
if (( ${#security_reasons[@]} > 0 )); then
  is_security=true
fi

owners=""
if owners_file="$(git show "$base_ref:.github/CODEOWNERS" 2> /dev/null)"; then
  owners="$(echo "$owners_file" | awk '$1 == "*" { $1 = ""; print }' | xargs)"
fi

# --- Merge --------------------------------------------------------------------------------------------------------

merge_base="$(git merge-base "$base_ref" "$tag")"
git worktree add --quiet --detach "$tree" "$base_ref"
# Git commands that touch the merge run in the temporary worktree.
in_tree() { git -C "$tree" "$@"; }

if [[ -z "$(git config user.email || true)" ]]; then
  export GIT_AUTHOR_NAME="Family Chat upstream sync" GIT_COMMITTER_NAME="Family Chat upstream sync"
  export GIT_AUTHOR_EMAIL="41898282+github-actions[bot]@users.noreply.github.com"
  export GIT_COMMITTER_EMAIL="$GIT_AUTHOR_EMAIL"
fi

merge_message="chore(upstream): merge $upstream_repo $tag"
auto_resolved=()
if ! in_tree merge --no-ff --no-edit -m "$merge_message" "$tag" > "$work_dir/merge.log" 2>&1; then
  cat "$work_dir/merge.log" >&2
  # "DU": deleted by us, modified by them.
  while IFS= read -r path; do
    if [[ "$path" =~ $deleted_on_purpose_regex ]]; then
      in_tree rm --quiet -r --cached -- "$path"
      rm -rf -- "${tree:?}/$path"
      auto_resolved+=("$path")
    fi
  done < <(in_tree status --porcelain=v1 | awk '$1 == "DU" { print $2 }')
fi

conflicts="$(in_tree diff --name-only --diff-filter=U)"

if [[ -n "$conflicts" ]]; then
  in_tree merge --abort
  log "$tag conflicts with $base_branch:"
  echo "$conflicts" >&2

  title="Upstream $tag does not merge cleanly"
  body="$work_dir/issue.md"
  {
    echo "Merging [\`$upstream_repo\` $tag](https://github.com/$upstream_repo/releases/tag/$tag) into \`$base_branch\` conflicts, so the sync workflow pushed nothing."
    echo
    if [[ "$is_security" == "true" ]]; then
      echo "> [!WARNING]"
      echo "> **Security release:** $(IFS=';'; echo "${security_reasons[*]}"). ${owners}"
      echo
    fi
    echo "### Conflicting paths"
    echo
    echo "$conflicts" | sed 's/^/- `/; s/$/`/'
    echo
    if (( ${#auto_resolved[@]} > 0 )); then
      echo "Upstream also changed these paths the fork deleted; keep the deletion:"
      echo
      printf -- '- `%s`\n' "${auto_resolved[@]}"
      echo
    fi
    echo "### Reproduce and resolve"
    echo
    echo '```bash'
    echo "git fetch origin $base_branch"
    echo "git fetch --no-tags https://github.com/$upstream_repo.git 'refs/tags/$tag:refs/tags/$tag'"
    echo "git switch -c $branch origin/$base_branch"
    echo "git merge --no-ff $tag"
    echo '```'
    echo
    echo "Resolve following \"Merging upstream releases\" in the README, then open a pull request titled \`$merge_message\` with the per-merge checklist. Close this issue from that pull request."
  } > "$body"

  if [[ "$dry_run" == "true" ]]; then
    { echo "## Dry run: would open or update the issue \"$title\""; echo; cat "$body"; } | summary
    exit 0
  fi

  labels="$label"
  if [[ "$is_security" == "true" ]]; then
    labels="$labels,security"
  fi
  existing="$(gh issue list --repo "$repo" --state open --label "$label" --search "\"$title\" in:title" \
    --json number,title --jq ".[] | select(.title == \"$title\") | .number" | head -n 1)"
  if [[ -n "$existing" ]]; then
    gh issue edit "$existing" --repo "$repo" --body-file "$body" --add-label "$labels"
    log "updated issue #$existing"
  else
    gh issue create --repo "$repo" --title "$title" --body-file "$body" --label "$labels"
  fi
  exit 0
fi

if (( ${#auto_resolved[@]} > 0 )); then
  in_tree commit --quiet --no-edit
fi

# Upstream workflows new in this release would run on our pull requests (and, once merged, from our default branch),
# so drop them too. The reviewer restores any we want.
dropped_workflows=()
while IFS= read -r path; do
  [[ -n "$path" ]] && dropped_workflows+=("$path")
done < <(in_tree diff --name-only --diff-filter=A "$base_ref" HEAD -- '.github/workflows/*.yml' '.github/workflows/*.yaml')
if (( ${#dropped_workflows[@]} > 0 )); then
  in_tree rm --quiet -- "${dropped_workflows[@]}"
  in_tree commit --quiet -m "chore(upstream): drop the workflows $tag adds" \
    -m "Upstream's automation stays off in the fork (README, \"Deleted upstream workflows\")."
fi

# --- Pull request -------------------------------------------------------------------------------------------------

# Files both sides changed since the merge base: the ones to read closely even though git merged them.
git diff --name-only "$merge_base" "$base_ref" | sort > "$work_dir/ours"
git diff --name-only "$merge_base" "$tag" | sort > "$work_dir/theirs"
# Only files still in the merged tree (the deleted-on-purpose ones are listed above), without snapshots or
# translations.
overlap="$(comm -12 "$work_dir/ours" "$work_dir/theirs" | grep -v -e '/__Snapshots__/' -e '\.lproj/' \
  | while IFS= read -r path; do if [[ -e "$tree/$path" ]]; then echo "$path"; fi; done || true)"

body="$work_dir/pr.md"
{
  echo "Merges [\`$upstream_repo\` $tag](https://github.com/$upstream_repo/releases/tag/$tag) into \`$base_branch\`. Opened by the upstream-sync workflow; a person reviews and merges it, because upstream code runs in a child-directed app."
  echo
  if [[ "$is_security" == "true" ]]; then
    echo "> [!WARNING]"
    echo "> **Security release:** $(IFS=';'; echo "${security_reasons[*]}"). Please review promptly. ${owners}"
    echo
  fi
  echo "### Resolved automatically"
  echo
  if (( ${#auto_resolved[@]} == 0 && ${#dropped_workflows[@]} == 0 )); then
    echo "Nothing: the merge was clean."
  fi
  for path in "${auto_resolved[@]}"; do
    echo "- \`$path\`: changed upstream, deleted in the fork; kept deleted"
  done
  for path in "${dropped_workflows[@]}"; do
    echo "- \`$path\`: new upstream workflow; dropped (restore it if we want it)"
  done
  echo
  echo "### Changed on both sides since the last merge"
  echo
  if [[ -n "$overlap" ]]; then
    echo "Git merged these without conflicts, but both upstream and the fork changed them. Read them closely:"
    echo
    echo "$overlap" | head -n 200 | sed 's/^/- `/; s/$/`/'
    if (( $(echo "$overlap" | wc -l) > 200 )); then
      echo "- …and $(( $(echo "$overlap" | wc -l) - 200 )) more"
    fi
  else
    echo "None."
  fi
  echo
  echo "### Per-merge checklist"
  echo
  cat <<'CHECKLIST'
- [ ] `xcodegen` run on a Mac and the project file committed (CI regenerates it, but local builds need it)
- [ ] Snapshot/UI tests: note any that need re-recording (`record-snapshots` label)
- [ ] No upstream workflow re-added (or re-deleted + still disabled at repo level: `gh workflow list --all`)
- [ ] Brand check: no "Element"/Element URLs reintroduced in user-facing strings or config
- [ ] Parental gate still covers every new way to leave the app (README "Parental gate"): new `open`/URL/link code, new web views, new library-provided buttons
- [ ] Sign-in allowlist and sign-in-code rules unchanged (family-chat `docs/client-login-links.md`)
- [ ] No third-party analytics/telemetry re-enabled (Kids/Families declarations, family-chat#232 decisions 4 and 8)
- [ ] CI green
- [ ] README conflict hotspots updated if this merge found a new one
CHECKLIST
  echo
  echo "### Upstream changelog"
  echo
  echo "<details><summary>$tag release notes</summary>"
  echo
  jq -r '.body // "No release notes."' "$release_json" | head -c 30000
  echo
  echo
  echo "</details>"
} > "$body"

if [[ "$dry_run" == "true" ]]; then
  { echo "## Dry run: would push \`$branch\` and open \"$merge_message\""; echo; cat "$body"; } | summary
  in_tree log --oneline --no-decorate --first-parent "$base_ref..HEAD" >&2
  exit 0
fi

# The token is passed as a header for this one push, never stored in the git config. --no-verify: git-lfs's pre-push
# hook, where installed, would try to upload LFS objects this checkout never downloaded.
auth="$(printf 'x-access-token:%s' "$GH_TOKEN" | base64 -w0)"
echo "::add-mask::$auth"
in_tree -c "http.https://github.com/.extraheader=AUTHORIZATION: basic $auth" \
  push --quiet --no-verify "https://github.com/$repo.git" "HEAD:refs/heads/$branch"

labels="$label"
if [[ "$is_security" == "true" ]]; then
  labels="$labels,security"
fi
gh pr create --repo "$repo" --base "$base_branch" --head "$branch" --title "$merge_message" \
  --body-file "$body" --label "$labels"
