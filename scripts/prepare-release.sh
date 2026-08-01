#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: ./scripts/prepare-release.sh \
  --release-root ABSOLUTE_PATH \
  --expected-version MAJOR.MINOR.PATCH \
  --expected-revision FULL_COMMIT_ID

Build a commit-specific static payload and atomically promote its current
symlink only after the source, assets, and generated release.json agree.
USAGE
}

release_root=""
expected_version=""
expected_revision=""

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --release-root)
      [[ "$#" -ge 2 ]] || {
        echo "--release-root requires a value." >&2
        exit 2
      }
      release_root="$2"
      shift 2
      ;;
    --expected-version)
      [[ "$#" -ge 2 ]] || {
        echo "--expected-version requires a value." >&2
        exit 2
      }
      expected_version="$2"
      shift 2
      ;;
    --expected-revision)
      [[ "$#" -ge 2 ]] || {
        echo "--expected-revision requires a value." >&2
        exit 2
      }
      expected_revision="$2"
      shift 2
      ;;
    --help|-h)
      usage
      exit 0
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

if [[ -z "${release_root}" || -z "${expected_version}" ||
  -z "${expected_revision}" ]]; then
  usage >&2
  exit 2
fi

if [[ "${release_root}" != /* || "${release_root}" == "/" ]]; then
  echo "Release root must be a specific absolute path other than /." >&2
  exit 2
fi

for required_command in awk basename cmp find git install ln mktemp mv sort; do
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

./scripts/verify-release-source.sh \
  "${expected_version}" "${expected_revision}"
./scripts/verify-lfs-checkout.sh
./scripts/verify-required-assets.sh

releases_root="${release_root%/}/releases"
release_directory="${releases_root}/${expected_revision}"
current_link="${release_root%/}/current"
next_link="${release_root%/}/.current.next.${expected_revision}.$$"

install -d -m 0755 "${releases_root}"

if [[ -e "${release_directory}" || -L "${release_directory}" ]]; then
  echo "Release directory already exists: ${release_directory}" >&2
  exit 1
fi

if [[ -e "${current_link}" && ! -L "${current_link}" ]]; then
  echo "Refusing to replace a non-symlink current path: ${current_link}" >&2
  exit 1
fi

staging_directory="$(
  mktemp -d "${releases_root}/.${expected_revision}.staging.XXXXXX"
)"
expected_inventory="$(mktemp "${TMPDIR:-/tmp}/static-cs-inventory.XXXXXX")"
actual_inventory="$(mktemp "${TMPDIR:-/tmp}/static-cs-inventory.XXXXXX")"

cleanup() {
  rm -f -- "${expected_inventory}" "${actual_inventory}" "${next_link}"
  if [[ -n "${staging_directory:-}" && -d "${staging_directory}" ]]; then
    rm -rf -- "${staging_directory}"
  fi
}
trap cleanup EXIT

chmod 0755 "${staging_directory}"

while read -r _ static_manifest_path; do
  static_asset_name="${static_manifest_path#./}"
  install -m 0644 -- "${static_asset_name}" \
    "${staging_directory}/${static_asset_name}"
done < asset-manifest.sha256

install -m 0644 -- robots.txt "${staging_directory}/robots.txt"
printf '{"version":"%s","revision":"%s"}\n' \
  "${expected_version}" "${expected_revision}" > \
  "${staging_directory}/release.json"
chmod 0644 "${staging_directory}/release.json"

{
  awk '{ path = $2; sub(/^\.\//, "", path); print path }' asset-manifest.sha256
  printf '%s\n' release.json robots.txt
} | LC_ALL=C sort > "${expected_inventory}"

find "${staging_directory}" -mindepth 1 -maxdepth 1 -type f \
  -exec basename {} \; | LC_ALL=C sort > "${actual_inventory}"

if [[ -n "$(
  find "${staging_directory}" -mindepth 1 -maxdepth 1 ! -type f -print -quit
)" ]] || ! cmp -s "${expected_inventory}" "${actual_inventory}"; then
  echo "Staged release inventory differs from 105 assets, robots.txt, and release.json." >&2
  exit 1
fi

(
  cd "${staging_directory}"
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum --check "${repo_root}/asset-manifest.sha256"
  else
    shasum -a 256 --check "${repo_root}/asset-manifest.sha256"
  fi
)

./scripts/verify-release-json.sh \
  "${staging_directory}/release.json" \
  "${expected_version}" "${expected_revision}"

# Close the source-change window before the atomic directory rename.
./scripts/verify-release-source.sh \
  "${expected_version}" "${expected_revision}"

mv -- "${staging_directory}" "${release_directory}"
staging_directory=""

# The current symlink is not touched until the finalized directory still
# matches the selected source identity and exact generated JSON.
./scripts/verify-release-json.sh \
  "${release_directory}/release.json" \
  "${expected_version}" "${expected_revision}"
./scripts/verify-release-source.sh \
  "${expected_version}" "${expected_revision}"

ln -s "releases/${expected_revision}" "${next_link}"
mv -f -- "${next_link}" "${current_link}"

echo "Promoted static release ${expected_version} at ${expected_revision}."
