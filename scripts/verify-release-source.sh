#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: ./scripts/verify-release-source.sh EXPECTED_VERSION EXPECTED_REVISION

Verify that this clean checkout is the exact commit named by one annotated
vMAJOR.MINOR.PATCH tag and by VERSION. EXPECTED_REVISION must be the full
lowercase 40-character Git commit ID selected by the deployer.
USAGE
}

if [[ "$#" -ne 2 ]]; then
  usage >&2
  exit 2
fi

expected_version="$1"
expected_revision="$2"
version_pattern='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
revision_pattern='^[0-9a-f]{40}$'

if [[ ! "${expected_version}" =~ ${version_pattern} ]]; then
  echo "Expected version must be an exact MAJOR.MINOR.PATCH value." >&2
  exit 2
fi

if [[ ! "${expected_revision}" =~ ${revision_pattern} ]]; then
  echo "Expected revision must be a full lowercase 40-character Git commit ID." >&2
  exit 2
fi

for required_command in cat cmp git grep mktemp sort tr wc; do
  if ! command -v "${required_command}" >/dev/null 2>&1; then
    echo "Missing required command: ${required_command}" >&2
    exit 1
  fi
done

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"

if [[ -z "${repo_root}" ]]; then
  echo "Run this script from inside the repository." >&2
  exit 1
fi

cd "${repo_root}"

if [[ ! -f VERSION ]]; then
  echo "Missing VERSION." >&2
  exit 1
fi

version="$(cat VERSION)"
canonical_version_file="$(mktemp "${TMPDIR:-/tmp}/static-cs-version.XXXXXX")"
trap 'rm -f "${canonical_version_file}"' EXIT
printf '%s\n' "${version}" > "${canonical_version_file}"

if [[ ! "${version}" =~ ${version_pattern} ]] ||
  ! cmp -s VERSION "${canonical_version_file}"; then
  echo "VERSION must contain one canonical MAJOR.MINOR.PATCH value and a newline." >&2
  exit 1
fi

if [[ "${version}" != "${expected_version}" ]]; then
  echo "VERSION ${version} does not match expected version ${expected_version}." >&2
  exit 1
fi

revision="$(git rev-parse --verify 'HEAD^{commit}' 2>/dev/null || true)"

if [[ ! "${revision}" =~ ${revision_pattern} ]]; then
  echo "HEAD did not resolve to a full lowercase 40-character commit ID." >&2
  exit 1
fi

if [[ "${revision}" != "${expected_revision}" ]]; then
  echo "HEAD ${revision} does not match expected revision ${expected_revision}." >&2
  exit 1
fi

if [[ -e release.json || -L release.json ]]; then
  echo "release.json must not exist in the source checkout." >&2
  exit 1
fi

if ! git diff --quiet --ignore-submodules -- ||
  ! git diff --cached --quiet --ignore-submodules -- ||
  [[ -n "$(git ls-files --others --exclude-standard)" ]]; then
  echo "The release checkout must be clean, including untracked files." >&2
  exit 1
fi

expected_tag="v${version}"
semver_tags="$(
  git tag --points-at "${revision}" |
    LC_ALL=C grep -E '^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$' |
    LC_ALL=C sort || true
)"
semver_tag_count="$(printf '%s\n' "${semver_tags}" | grep -c . || true)"

if [[ "${semver_tag_count}" != "1" || "${semver_tags}" != "${expected_tag}" ]]; then
  echo "HEAD must have exactly one semantic-version tag: ${expected_tag}." >&2
  exit 1
fi

if [[ "$(git cat-file -t "refs/tags/${expected_tag}" 2>/dev/null || true)" != "tag" ]]; then
  echo "${expected_tag} must be an annotated tag, not a lightweight tag." >&2
  exit 1
fi

tag_revision="$(
  git rev-parse --verify "refs/tags/${expected_tag}^{commit}" 2>/dev/null || true
)"

if [[ "${tag_revision}" != "${revision}" ]]; then
  echo "${expected_tag} does not resolve to HEAD ${revision}." >&2
  exit 1
fi

echo "Verified ${expected_tag} at ${revision}."
