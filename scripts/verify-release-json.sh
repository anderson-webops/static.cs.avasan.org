#!/usr/bin/env bash

set -euo pipefail

if [[ "$#" -ne 3 ]]; then
  echo "Usage: ./scripts/verify-release-json.sh FILE EXPECTED_VERSION EXPECTED_REVISION" >&2
  exit 2
fi

release_json="$1"
expected_version="$2"
expected_revision="$3"
version_pattern='^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$'
revision_pattern='^[0-9a-f]{40}$'

if [[ ! "${expected_version}" =~ ${version_pattern} ]] ||
  [[ ! "${expected_revision}" =~ ${revision_pattern} ]]; then
  echo "Invalid expected release identity." >&2
  exit 2
fi

if [[ ! -f "${release_json}" || -L "${release_json}" ]]; then
  echo "Release metadata must be a regular file: ${release_json}" >&2
  exit 1
fi

canonical_json="$(mktemp "${TMPDIR:-/tmp}/static-cs-release-json.XXXXXX")"
trap 'rm -f "${canonical_json}"' EXIT
printf '{"version":"%s","revision":"%s"}\n' \
  "${expected_version}" "${expected_revision}" > "${canonical_json}"

if ! cmp -s "${release_json}" "${canonical_json}"; then
  echo "Release metadata does not exactly match the expected two-field JSON contract." >&2
  exit 1
fi

echo "Verified release.json for ${expected_version} at ${expected_revision}."
