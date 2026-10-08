#!/usr/bin/env bash

# Copyright 2026 Unicorn Operations Ltd.
#
# SPDX-License-Identifier: AGPL-3.0-only OR LicenseRef-Element-Commercial.
# Please see LICENSE files in the repository root for full details.

# Gate of the release workflow (#6, docs/RELEASING.md). Fails unless:
# - TAG is v<yy.mm.r>-fc.<n> with n in 1..99;
# - the upstream version in the tag is the one the tagged commit is built from (project.yml MARKETING_VERSION);
# - the tagged commit is on familychat;
# - CI passed on that commit: the latest push run of Build (build.yml) succeeded. Scheduled workflows are ignored.
# Writes tag, version, fc and sha to GITHUB_OUTPUT. Needs TAG, REPO and GH_TOKEN; runs from a full clone.

set -euo pipefail

if [[ ! "${TAG}" =~ ^v([0-9]{2}\.[0-9]{2}\.[0-9]+)-fc\.([1-9][0-9]?)$ ]]; then
    echo "::error::${TAG} is not a release tag: expected v<yy.mm.r>-fc.<n>, n in 1..99"
    exit 1
fi
tag_version="${BASH_REMATCH[1]}"
fc="${BASH_REMATCH[2]}"

sha="$(git rev-list -n 1 "refs/tags/${TAG}")"

built_version="$(git show "${sha}:project.yml" | sed -n 's/^  MARKETING_VERSION: *//p' | tr -d '"' | head -n 1)"
if [[ "${tag_version}" != "${built_version}" ]]; then
    echo "::error::${TAG} says upstream ${tag_version}, but the tagged commit is built from upstream ${built_version}"
    exit 1
fi

if ! git merge-base --is-ancestor "${sha}" origin/familychat; then
    echo "::error::${TAG} (${sha}) is not on familychat"
    exit 1
fi

latest="$(gh api "repos/${REPO}/actions/workflows/build.yml/runs?head_sha=${sha}&event=push&per_page=20" \
    --jq '[.workflow_runs[]] | max_by(.run_number) // empty | .status + " " + (.conclusion // "")')"
if [[ -z "${latest}" ]]; then
    echo "::error::Build (build.yml) has not run on ${sha} (a push to familychat runs it)"
    exit 1
fi
if [[ "${latest}" != "completed success" ]]; then
    echo "::error::Build is not green on ${sha}: ${latest}"
    exit 1
fi

echo "Release ${TAG}: upstream ${built_version}, Family Chat release ${fc}, commit ${sha}"
{
    echo "tag=${TAG}"
    echo "version=${built_version}"
    echo "fc=${fc}"
    echo "sha=${sha}"
} >> "${GITHUB_OUTPUT}"
