#!/usr/bin/env bash

set -euo pipefail

repo_root="$(git rev-parse --show-toplevel 2>/dev/null || true)"

if [[ -z "${repo_root}" ]]; then
  echo "Run this script from inside the repository." >&2
  exit 1
fi

cd "${repo_root}"

manifest_path="${repo_root}/asset-manifest.sha256"
temporary_manifest="$(mktemp "${TMPDIR:-/tmp}/static-cs-assets.XXXXXX")"
trap 'rm -f "${temporary_manifest}"' EXIT

asset_paths() {
  find . -maxdepth 1 -type f \
    \( -name 'ps*.gif' -o -name 'ps*.mp4' -o -name 'pyg_*.mp4' -o -name 'assets.zip' \) \
    -print | LC_ALL=C sort
}

ps_count="$(asset_paths | sed 's#^\./##' | grep -Ec '^ps.*\.(gif|mp4)$' || true)"
pygames_count="$(asset_paths | sed 's#^\./##' | grep -Ec '^pyg_.*\.mp4$' || true)"
total_count="$(asset_paths | wc -l | tr -d '[:space:]')"

if [[ "${ps_count}" != "77" || "${pygames_count}" != "27" || "${total_count}" != "105" ]]; then
  echo "Refusing to build a manifest for an unexpected asset set." >&2
  echo "Expected 77 Python files, 27 PyGames videos, and assets.zip (105 total)." >&2
  echo "Found ${ps_count} Python files, ${pygames_count} PyGames videos, and ${total_count} total." >&2
  exit 1
fi

while IFS= read -r path; do
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum "${path}" >> "${temporary_manifest}"
  else
    shasum -a 256 "${path}" >> "${temporary_manifest}"
  fi
done < <(asset_paths)

mv "${temporary_manifest}" "${manifest_path}"
trap - EXIT

echo "Wrote checksums for ${total_count} assets to asset-manifest.sha256."
