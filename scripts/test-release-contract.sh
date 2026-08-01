#!/usr/bin/env bash

set -euo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"

if [[ -z "${repo_root}" ]]; then
  echo "Run this script from inside the repository." >&2
  exit 1
fi

temporary_root="$(mktemp -d "${TMPDIR:-/tmp}/static-cs-release-tests.XXXXXX")"
trap 'rm -rf "${temporary_root}"' EXIT
bare_repository="${temporary_root}/origin.git"
fixture_repository="${temporary_root}/checkout"

git init --bare --quiet "${bare_repository}"
git init --quiet -b main "${fixture_repository}"
git -C "${fixture_repository}" config user.name "Release Contract Test"
git -C "${fixture_repository}" config user.email "release-contract@example.invalid"
git -C "${fixture_repository}" config core.autocrlf false
git -C "${fixture_repository}" remote add origin "${bare_repository}"
printf '9.8.7\n' > "${fixture_repository}/VERSION"
printf 'fixture\n' > "${fixture_repository}/fixture.txt"
git -C "${fixture_repository}" add VERSION fixture.txt
git -C "${fixture_repository}" commit --quiet -m "Create fixture"
git -C "${fixture_repository}" push --quiet -u origin main
fixture_revision="$(git -C "${fixture_repository}" rev-parse HEAD)"

expect_failure() {
  if (cd "${fixture_repository}" && "$@" >/dev/null 2>&1); then
    echo "Expected command to fail: $*" >&2
    exit 1
  fi
}

expect_failure "${repo_root}/scripts/verify-release-source.sh" \
  9.8.7 "${fixture_revision}"

git -C "${fixture_repository}" tag v9.8.7
expect_failure "${repo_root}/scripts/verify-release-source.sh" \
  9.8.7 "${fixture_revision}"
git -C "${fixture_repository}" tag -d v9.8.7 >/dev/null

git -C "${fixture_repository}" tag -a v9.8.7 -m "Release v9.8.7"
(
  cd "${fixture_repository}"
  "${repo_root}/scripts/verify-release-source.sh" 9.8.7 "${fixture_revision}"
)

expect_failure "${repo_root}/scripts/verify-release-source.sh" \
  9.8.6 "${fixture_revision}"
expect_failure "${repo_root}/scripts/verify-release-source.sh" \
  9.8.7 0000000000000000000000000000000000000000

printf 'dirty\n' >> "${fixture_repository}/fixture.txt"
expect_failure "${repo_root}/scripts/verify-release-source.sh" \
  9.8.7 "${fixture_revision}"
git -C "${fixture_repository}" restore fixture.txt

release_directory="${temporary_root}/.${fixture_revision}.staging.test"
mkdir "${release_directory}"
printf '{"version":"9.8.7","revision":"%s"}\n' \
  "${fixture_revision}" > "${release_directory}/release.json"
"${repo_root}/scripts/verify-release-json.sh" \
  "${release_directory}/release.json" 9.8.7 "${fixture_revision}"

printf '{"version":"9.8.7","revision":"%s","extra":true}\n' \
  "${fixture_revision}" > "${release_directory}/release.json"
expect_failure "${repo_root}/scripts/verify-release-json.sh" \
  "${release_directory}/release.json" 9.8.7 "${fixture_revision}"

echo "Release provenance regression tests passed."
