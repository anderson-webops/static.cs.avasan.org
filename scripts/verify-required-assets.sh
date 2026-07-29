#!/usr/bin/env bash

set -euo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"

if [[ -z "${repo_root}" ]]; then
  echo "Run this script from inside the repository." >&2
  exit 1
fi

cd "${repo_root}"

manifest="asset-manifest.sha256"

if [[ ! -f "${manifest}" ]]; then
  echo "Missing ${manifest}. Run ./scripts/build-asset-manifest.sh." >&2
  exit 1
fi

asset_paths() {
  find . -maxdepth 1 -type f \
    \( -name 'ps*.gif' -o -name 'ps*.mp4' -o -name 'pyg_*.mp4' -o -name 'assets.zip' \) \
    -print | LC_ALL=C sort
}

ps_count="$(asset_paths | sed 's#^\./##' | grep -Ec '^ps.*\.(gif|mp4)$' || true)"
pygames_count="$(asset_paths | sed 's#^\./##' | grep -Ec '^pyg_.*\.mp4$' || true)"
total_count="$(asset_paths | wc -l | tr -d '[:space:]')"
manifest_count="$(wc -l < "${manifest}" | tr -d '[:space:]')"

if [[ "${ps_count}" != "77" ]]; then
  echo "Expected 77 Python Level 2 files; found ${ps_count}." >&2
  exit 1
fi

if [[ "${pygames_count}" != "27" ]]; then
  echo "Expected 27 PyGames videos; found ${pygames_count}." >&2
  exit 1
fi

if [[ "${total_count}" != "105" || "${manifest_count}" != "105" ]]; then
  echo "Expected 105 binary assets and 105 manifest entries." >&2
  echo "Found ${total_count} assets and ${manifest_count} manifest entries." >&2
  exit 1
fi

if [[ ! -s "assets.zip" ]]; then
  echo "assets.zip is missing or empty." >&2
  exit 1
fi

if [[ "$(head -c 2 assets.zip)" != "PK" ]]; then
  echo "assets.zip does not have a ZIP signature." >&2
  exit 1
fi

unzip -tq assets.zip >/dev/null

if command -v sha256sum >/dev/null 2>&1; then
  sha256sum --check "${manifest}"
else
  shasum -a 256 --check "${manifest}"
fi

manifest_paths="$(mktemp "${TMPDIR:-/tmp}/static-cs-manifest-paths.XXXXXX")"
checkout_paths="$(mktemp "${TMPDIR:-/tmp}/static-cs-checkout-paths.XXXXXX")"
lfs_paths="$(mktemp "${TMPDIR:-/tmp}/static-cs-lfs-paths.XXXXXX")"
trap 'rm -f "${manifest_paths}" "${checkout_paths}" "${lfs_paths}"' EXIT

awk '{ print $2 }' "${manifest}" | LC_ALL=C sort > "${manifest_paths}"
asset_paths | LC_ALL=C sort > "${checkout_paths}"
git lfs ls-files -n | sed 's#^#./#' | LC_ALL=C sort > "${lfs_paths}"

if ! cmp -s "${manifest_paths}" "${checkout_paths}"; then
  echo "The manifest and checkout asset paths differ." >&2
  diff -u "${manifest_paths}" "${checkout_paths}" || true
  exit 1
fi

if ! cmp -s "${checkout_paths}" "${lfs_paths}"; then
  echo "Every binary asset must be tracked by Git LFS, with no extra LFS files." >&2
  diff -u "${checkout_paths}" "${lfs_paths}" || true
  exit 1
fi

if [[ "$(cat robots.txt 2>/dev/null || true)" != $'User-agent: *\nDisallow: /' ]]; then
  echo "robots.txt must block indexing of the asset host." >&2
  exit 1
fi

echo "Verified 105 curated assets: 77 Python files, 27 PyGames videos, and assets.zip."
