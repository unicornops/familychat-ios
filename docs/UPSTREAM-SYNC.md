# Upstream sync

[`.github/workflows/upstream-sync.yml`](../.github/workflows/upstream-sync.yml) runs daily (and on manual
dispatch) and merges the newest **stable** `element-hq/element-x-ios` release into `familychat`, using
[`upstream-sync.sh`](../.github/workflows/scripts/upstream-sync.sh). It does what "Merging upstream releases"
in the [README](../README.md#merging-upstream-releases) describes, and never merges anything itself: a person
reviews every upstream merge, because upstream code runs in a child-directed app.

## What it does

1. Takes upstream's latest release (`gh api repos/element-hq/element-x-ios/releases/latest`, which skips
   pre-releases and drafts), or the `tag` input. Tags look like `release/YY.MM.N`; a tag that is a GitHub
   pre-release is refused. If `familychat` already contains the tag, or `upstream/<version>` already exists
   (its pull request is waiting for review), it stops.
2. Merges the tag into `familychat` with `git merge --no-ff` in a temporary worktree (never a rebase), without
   downloading Git LFS objects: the merge only needs the pointers, and the fork shares upstream's LFS objects.
3. Upstream edits to paths the fork deleted on purpose (any `.github/workflows/*.yml`, the `Enterprise`
   submodule) are modify/delete conflicts, resolved by keeping the deletion. Workflows that are new in the
   release are dropped in a second commit, since they would run with our permissions (and schedule,
   `pull_request_target` and `workflow_run` triggers run from the default branch). Both are listed in the pull
   request; restore one deliberately if we want it.
4. **Clean merge:** pushes `upstream/<version>` (for example `upstream/26.10.0`) and opens a pull request titled
   `chore(upstream): merge element-hq/element-x-ios release/<version>`, labelled `upstream-sync`. It lists the
   files both sides changed since the last merge (git merged them, but they deserve a close read), carries the
   per-merge checklist and upstream's release notes. Normal CI runs on it.
5. **Any other conflict:** pushes nothing and opens (or updates) an issue labelled `upstream-sync`, titled
   `Upstream release/<version> does not merge cleanly`, with the conflicting paths and the commands to
   reproduce the merge. Resolve it by hand on a branch, following the README, and close the issue from that pull
   request. Conflicts in the workflows we keep but trimmed (`compound-ios.yml`, `ui-tests.yml` without
   Codecov) also land here.
6. **Security fast path:** when the release notes mention a security fix, a CVE or a GHSA, or a published
   upstream advisory is patched in that version, the pull request or issue is also labelled `security` and
   pings the CODEOWNERS.

## Setup (once)

The job runs in the `upstream-sync` environment, which should allow deployments from `familychat` only and
hold one secret:

- `UPSTREAM_SYNC_TOKEN`: a fine-grained personal access token (or GitHub App token) for
  `unicornops/familychat-ios` only, with read and write access to **contents**, **pull requests** and
  **issues**. `GITHUB_TOKEN` can't be used: pushes and pull requests it creates don't trigger CI.

Until both exist, the scheduled run fails with "UPSTREAM_SYNC_TOKEN is not set".

## Running it by hand

A manual dispatch (Actions, "Upstream sync", "Run workflow") defaults to a dry run, which writes the pull
request or issue it would open to the job summary. Untick `dry_run` to really push and open it. `tag` merges a
specific release instead of the latest.

The script also runs locally from any checkout of this repository (it only needs `git`, `gh` and `jq`, and
works in a temporary worktree, so the checkout is left as it was). With `DRY_RUN=true`, `gh`'s own login is
enough:

```bash
GITHUB_REPOSITORY=unicornops/familychat-ios DRY_RUN=true TAG=release/26.09.2 \
  .github/workflows/scripts/upstream-sync.sh
```

Without `TAG` it uses upstream's latest stable release. `BASE_BRANCH`, `REMOTE` and `UPSTREAM_REPO` override
`familychat`, `origin` and `element-hq/element-x-ios`.

### Dry runs recorded for #5 (2026-10-08)

- `TAG=release/26.09.1` (the fork's base): "`familychat` already contains `release/26.09.1`, nothing to do."
- `TAG=release/26.08.3` (a pre-release): refused, exit 1.
- Latest (`release/26.09.2`) against `familychat` before the manual catch-up: would open the conflict issue
  listing 15 paths (the account-provider rework and two workflows), with `integration-tests.yml`,
  `unit-tests.yml` and `Enterprise` resolved by keeping the deletion.
- Clean path, against a scratch base (`release/26.08.4` with `unit-tests.yml` and `stale.yml` deleted): would
  push `upstream/26.09.2`, keeping `unit-tests.yml` deleted and dropping the new `pr-checks.yml`.
