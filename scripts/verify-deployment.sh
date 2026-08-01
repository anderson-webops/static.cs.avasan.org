#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'USAGE'
Usage: ./scripts/verify-deployment.sh \
  --expected-version MAJOR.MINOR.PATCH \
  --expected-revision FULL_COMMIT_ID \
  [--base-url HTTPS_ORIGIN] [--concurrency N]

Validate the public static host against asset-manifest.sha256 without reading
or downloading local Git LFS assets.

Environment overrides:
  ASSET_BASE_URL          Default: https://static.cs.avasan.org
  VERIFY_CONCURRENCY      Default: 8
  EXPECTED_VERSION        Required if --expected-version is omitted
  EXPECTED_REVISION       Required if --expected-revision is omitted
  EXPECTED_CORS_ORIGIN    Default: https://cs.avasan.org
  CURL_CONNECT_TIMEOUT    Default: 10 seconds
  CURL_MAX_TIME           Default: 30 seconds
USAGE
}

base_url="${ASSET_BASE_URL:-https://static.cs.avasan.org}"
concurrency="${VERIFY_CONCURRENCY:-8}"
expected_cors_origin="${EXPECTED_CORS_ORIGIN:-https://cs.avasan.org}"
connect_timeout="${CURL_CONNECT_TIMEOUT:-10}"
max_time="${CURL_MAX_TIME:-30}"
expected_version="${EXPECTED_VERSION:-}"
expected_revision="${EXPECTED_REVISION:-}"

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --base-url)
      [[ "$#" -ge 2 ]] || {
        echo "--base-url requires a value." >&2
        exit 2
      }
      base_url="$2"
      shift 2
      ;;
    --concurrency)
      [[ "$#" -ge 2 ]] || {
        echo "--concurrency requires a value." >&2
        exit 2
      }
      concurrency="$2"
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

base_url="${base_url%/}"

if [[ ! "${base_url}" =~ ^https://[A-Za-z0-9.-]+(:[0-9]+)?$ ]] ||
  [[ "${base_url}" == *".."* ]]; then
  echo "The base URL must be an HTTPS origin without credentials, a path, a query, or a fragment: ${base_url}" >&2
  exit 2
fi

if [[ ! "${concurrency}" =~ ^[1-9][0-9]*$ ]] || (( concurrency > 32 )); then
  echo "Concurrency must be an integer from 1 through 32." >&2
  exit 2
fi

if [[ ! "${connect_timeout}" =~ ^[1-9][0-9]*$ ]] ||
  [[ ! "${max_time}" =~ ^[1-9][0-9]*$ ]]; then
  echo "Curl timeouts must be positive whole seconds." >&2
  exit 2
fi

if [[ ! "${expected_version}" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]; then
  echo "Expected version must be an exact MAJOR.MINOR.PATCH value." >&2
  exit 2
fi

if [[ ! "${expected_revision}" =~ ^[0-9a-f]{40}$ ]]; then
  echo "Expected revision must be a full lowercase 40-character Git commit ID." >&2
  exit 2
fi

for required_command in awk cat cmp curl dd git grep head mktemp sed sort tr uniq wc; do
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

manifest="${repo_root}/asset-manifest.sha256"

if [[ ! -f "${manifest}" ]]; then
  echo "Missing asset-manifest.sha256." >&2
  exit 1
fi

temporary_dir="$(mktemp -d "${TMPDIR:-/tmp}/static-cs-live.XXXXXX")"
trap 'rm -rf "${temporary_dir}"' EXIT

manifest_path_list="${temporary_dir}/manifest-paths"
: > "${manifest_path_list}"

asset_paths=()
line_number=0

while IFS= read -r manifest_line || [[ -n "${manifest_line}" ]]; do
  line_number=$((line_number + 1))

  if [[ ! "${manifest_line}" =~ ^[0-9a-f]{64}[[:space:]]+\./([A-Za-z0-9][A-Za-z0-9._-]*\.(zip|gif|mp4))$ ]]; then
    echo "Invalid manifest entry on line ${line_number}." >&2
    exit 1
  fi

  asset_path="${BASH_REMATCH[1]}"
  asset_paths+=("${asset_path}")
  printf '%s\n' "${asset_path}" >> "${manifest_path_list}"
done < "${manifest}"

if [[ "${#asset_paths[@]}" -ne 105 ]]; then
  echo "Expected 105 manifest paths; found ${#asset_paths[@]}." >&2
  exit 1
fi

duplicate_paths="$(sort "${manifest_path_list}" | uniq -d)"

if [[ -n "${duplicate_paths}" ]]; then
  echo "The manifest contains duplicate public paths:" >&2
  printf '%s\n' "${duplicate_paths}" >&2
  exit 1
fi

header_value() {
  local header_file="$1"
  local requested_name="$2"

  awk -v requested_name="${requested_name}" '
    {
      line = $0
      sub(/\r$/, "", line)
      separator = index(line, ":")
      if (separator > 0) {
        name = tolower(substr(line, 1, separator - 1))
        if (name == tolower(requested_name)) {
          value = substr(line, separator + 1)
          sub(/^[[:space:]]+/, "", value)
          found = value
        }
      }
    }
    END {
      if (found != "") {
        print found
      }
    }
  ' "${header_file}"
}

normalized_content_type() {
  local header_file="$1"
  local content_type

  content_type="$(header_value "${header_file}" "Content-Type")"
  content_type="${content_type%%;*}"
  printf '%s' "${content_type}" |
    sed 's/^[[:space:]]*//;s/[[:space:]]*$//' |
    tr '[:upper:]' '[:lower:]'
}

expected_content_type() {
  case "$1" in
    *.zip)
      printf 'application/zip'
      ;;
    *.gif)
      printf 'image/gif'
      ;;
    *.mp4)
      printf 'video/mp4'
      ;;
    *)
      return 1
      ;;
  esac
}

curl_common=(
  --silent
  --show-error
  --connect-timeout "${connect_timeout}"
  --max-time "${max_time}"
  --retry 2
  --retry-all-errors
  --proto '=https'
  --tlsv1.2
)

verify_release_identity() {
  local headers="${temporary_dir}/release.headers"
  local body="${temporary_dir}/release.body"
  local expected_body="${temporary_dir}/release.expected"
  local stderr_file="${temporary_dir}/release.stderr"
  local status

  if ! status="$(
    curl "${curl_common[@]}" --dump-header "${headers}" --output "${body}" \
      --write-out '%{http_code}' "${base_url}/release.json" 2>"${stderr_file}"
  )"; then
    echo "Release identity request failed: $(tr '\n' ' ' < "${stderr_file}")" >&2
    return 1
  fi

  if [[ "${status}" != "200" ]]; then
    echo "Expected HTTP 200 for /release.json; received ${status}." >&2
    return 1
  fi

  if [[ "$(normalized_content_type "${headers}")" != "application/json" ]]; then
    echo "The deployed release.json does not use application/json." >&2
    return 1
  fi

  local cache_control
  cache_control="$(
    header_value "${headers}" "Cache-Control" | tr '[:upper:]' '[:lower:]'
  )"

  if [[ "${cache_control}" != *"no-store"* ]]; then
    echo "The deployed release.json must use Cache-Control: no-store." >&2
    return 1
  fi

  if [[ -n "$(header_value "${headers}" "Set-Cookie")" ]]; then
    echo "The deployed release.json must not set a cookie." >&2
    return 1
  fi

  printf '{"version":"%s","revision":"%s"}\n' \
    "${expected_version}" "${expected_revision}" > "${expected_body}"

  if ! cmp -s "${body}" "${expected_body}"; then
    echo "The deployed release.json does not exactly match the expected release identity." >&2
    return 1
  fi

  local hsts
  hsts="$(
    header_value "${headers}" "Strict-Transport-Security" |
      tr '[:upper:]' '[:lower:]'
  )"

  if [[ "${hsts}" != *"max-age=31536000"* ]]; then
    echo "Missing one-year Strict-Transport-Security for /release.json." >&2
    return 1
  fi

  echo "PASS release ${expected_version} ${expected_revision}"
}

verify_release_identity

verify_asset_head() {
  local index="$1"
  local asset_path="$2"
  local headers="${temporary_dir}/head-${index}.headers"
  local stderr_file="${temporary_dir}/head-${index}.stderr"
  local url="${base_url}/${asset_path}"
  local status

  if ! status="$(
    curl "${curl_common[@]}" --head --dump-header "${headers}" \
      --output /dev/null --write-out '%{http_code}' "${url}" \
      2>"${stderr_file}"
  )"; then
    printf 'FAIL %-40s request error: %s\n' "${asset_path}" \
      "$(tr '\n' ' ' < "${stderr_file}")"
    return 1
  fi

  if [[ "${status}" != "200" ]]; then
    printf 'FAIL %-40s expected HTTP 200, received %s\n' \
      "${asset_path}" "${status}"
    return 1
  fi

  local expected_type
  local actual_type
  expected_type="$(expected_content_type "${asset_path}")"
  actual_type="$(normalized_content_type "${headers}")"

  if [[ "${actual_type}" != "${expected_type}" ]]; then
    printf 'FAIL %-40s expected %s, received %s\n' \
      "${asset_path}" "${expected_type}" "${actual_type:-<missing>}"
    return 1
  fi

  local content_length
  content_length="$(header_value "${headers}" "Content-Length")"

  if [[ ! "${content_length}" =~ ^[1-9][0-9]*$ ]]; then
    printf 'FAIL %-40s missing or invalid Content-Length: %s\n' \
      "${asset_path}" "${content_length:-<missing>}"
    return 1
  fi

  local accept_ranges
  accept_ranges="$(
    header_value "${headers}" "Accept-Ranges" | tr '[:upper:]' '[:lower:]'
  )"

  if [[ "${accept_ranges}" != "bytes" ]]; then
    printf 'FAIL %-40s expected Accept-Ranges: bytes\n' "${asset_path}"
    return 1
  fi

  local cors_origin
  cors_origin="$(header_value "${headers}" "Access-Control-Allow-Origin")"

  if [[ "${cors_origin}" != "${expected_cors_origin}" ]]; then
    printf 'FAIL %-40s expected CORS origin %s, received %s\n' \
      "${asset_path}" "${expected_cors_origin}" "${cors_origin:-<missing>}"
    return 1
  fi

  local cache_control
  cache_control="$(
    header_value "${headers}" "Cache-Control" | tr '[:upper:]' '[:lower:]'
  )"

  if [[ "${cache_control}" != *"public"* ||
    "${cache_control}" != *"max-age=3600"* ]]; then
    printf 'FAIL %-40s unexpected Cache-Control: %s\n' \
      "${asset_path}" "${cache_control:-<missing>}"
    return 1
  fi

  local nosniff
  nosniff="$(
    header_value "${headers}" "X-Content-Type-Options" |
      tr '[:upper:]' '[:lower:]'
  )"

  if [[ "${nosniff}" != "nosniff" ]]; then
    printf 'FAIL %-40s missing X-Content-Type-Options: nosniff\n' \
      "${asset_path}"
    return 1
  fi

  local resource_policy
  resource_policy="$(
    header_value "${headers}" "Cross-Origin-Resource-Policy" |
      tr '[:upper:]' '[:lower:]'
  )"

  if [[ "${resource_policy}" != "cross-origin" ]]; then
    printf 'FAIL %-40s missing Cross-Origin-Resource-Policy: cross-origin\n' \
      "${asset_path}"
    return 1
  fi

  local hsts
  hsts="$(
    header_value "${headers}" "Strict-Transport-Security" |
      tr '[:upper:]' '[:lower:]'
  )"

  if [[ "${hsts}" != *"max-age=31536000"* ]]; then
    printf 'FAIL %-40s missing one-year Strict-Transport-Security\n' \
      "${asset_path}"
    return 1
  fi

  printf 'PASS %-40s %s %s bytes\n' \
    "${asset_path}" "${expected_type}" "${content_length}"
}

echo "Checking ${#asset_paths[@]} manifest URLs at ${base_url} ..."

active_pids=()

for asset_index in "${!asset_paths[@]}"; do
  (
    result_file="${temporary_dir}/result-${asset_index}"
    if ! verify_asset_head "${asset_index}" "${asset_paths[${asset_index}]}" \
      > "${result_file}" 2>&1; then
      if ! grep -q '^FAIL ' "${result_file}"; then
        printf 'FAIL %-40s verifier exited unexpectedly\n' \
          "${asset_paths[${asset_index}]}" >> "${result_file}"
      fi
    fi
  ) &
  active_pids+=("$!")

  if (( ${#active_pids[@]} >= concurrency )); then
    wait "${active_pids[0]}"
    active_pids=("${active_pids[@]:1}")
  fi
done

for active_pid in "${active_pids[@]}"; do
  wait "${active_pid}"
done

failed_asset_count=0

for asset_index in "${!asset_paths[@]}"; do
  result_file="${temporary_dir}/result-${asset_index}"
  cat "${result_file}"

  if grep -q '^FAIL ' "${result_file}"; then
    failed_asset_count=$((failed_asset_count + 1))
  fi
done

if (( failed_asset_count > 0 )); then
  echo "${failed_asset_count} manifest URL checks failed." >&2
  exit 1
fi

verify_range() {
  local asset_path="$1"
  local signature_kind="$2"
  local headers="${temporary_dir}/range-${signature_kind}.headers"
  local body="${temporary_dir}/range-${signature_kind}.body"
  local stderr_file="${temporary_dir}/range-${signature_kind}.stderr"
  local expected_type
  local actual_type
  local status

  expected_type="$(expected_content_type "${asset_path}")"

  if ! status="$(
    curl "${curl_common[@]}" --range 0-1023 --dump-header "${headers}" \
      --output "${body}" --write-out '%{http_code}' \
      "${base_url}/${asset_path}" 2>"${stderr_file}"
  )"; then
    echo "Range request failed for ${asset_path}: $(tr '\n' ' ' < "${stderr_file}")" >&2
    return 1
  fi

  if [[ "${status}" != "206" ]]; then
    echo "Expected HTTP 206 for ${asset_path}; received ${status}." >&2
    return 1
  fi

  actual_type="$(normalized_content_type "${headers}")"
  if [[ "${actual_type}" != "${expected_type}" ]]; then
    echo "Unexpected range MIME for ${asset_path}: ${actual_type:-<missing>}." >&2
    return 1
  fi

  local body_size
  body_size="$(wc -c < "${body}" | tr -d '[:space:]')"
  if [[ "${body_size}" != "1024" ]]; then
    echo "Expected 1,024 range bytes for ${asset_path}; received ${body_size}." >&2
    return 1
  fi

  local content_range
  content_range="$(header_value "${headers}" "Content-Range")"
  if [[ ! "${content_range}" =~ ^bytes[[:space:]]0-1023/([1-9][0-9]*)$ ]] ||
    (( BASH_REMATCH[1] <= 1024 )); then
    echo "Invalid Content-Range for ${asset_path}: ${content_range:-<missing>}." >&2
    return 1
  fi

  case "${signature_kind}" in
    zip)
      if [[ "$(LC_ALL=C head -c 2 "${body}")" != "PK" ]]; then
        echo "The assets.zip range does not start with a ZIP signature." >&2
        return 1
      fi
      ;;
    gif)
      local gif_signature
      gif_signature="$(LC_ALL=C head -c 6 "${body}")"
      if [[ "${gif_signature}" != "GIF87a" && "${gif_signature}" != "GIF89a" ]]; then
        echo "The GIF range has an invalid signature: ${gif_signature}." >&2
        return 1
      fi
      ;;
    mp4)
      local mp4_signature
      mp4_signature="$(
        LC_ALL=C dd if="${body}" bs=1 skip=4 count=4 2>/dev/null
      )"
      if [[ "${mp4_signature}" != "ftyp" ]]; then
        echo "The MP4 range has an invalid file-type box." >&2
        return 1
      fi
      ;;
  esac

  echo "PASS range ${asset_path} (bytes 0-1023)"
}

for representative_path in \
  assets.zip \
  ps1_mad_libs.gif \
  pyg_1_rainbow_fill.mp4; do
  if ! grep -Fxq "${representative_path}" "${manifest_path_list}"; then
    echo "Representative range path is absent from the manifest: ${representative_path}" >&2
    exit 1
  fi
done

verify_range assets.zip zip
verify_range ps1_mad_libs.gif gif
verify_range pyg_1_rainbow_fill.mp4 mp4

verify_small_response() {
  local path="$1"
  local expected_status="$2"
  local output="${temporary_dir}/small-output"
  local headers="${temporary_dir}/small-headers"
  local stderr_file="${temporary_dir}/small-stderr"
  local status

  if ! status="$(
    curl "${curl_common[@]}" --dump-header "${headers}" --output "${output}" \
      --write-out '%{http_code}' "${base_url}${path}" 2>"${stderr_file}"
  )"; then
    echo "Request failed for ${path}: $(tr '\n' ' ' < "${stderr_file}")" >&2
    return 1
  fi

  if [[ "${status}" != "${expected_status}" ]]; then
    echo "Expected HTTP ${expected_status} for ${path}; received ${status}." >&2
    return 1
  fi

  local hsts
  hsts="$(
    header_value "${headers}" "Strict-Transport-Security" |
      tr '[:upper:]' '[:lower:]'
  )"

  if [[ "${hsts}" != *"max-age=31536000"* ]]; then
    echo "Missing one-year Strict-Transport-Security for ${path}." >&2
    return 1
  fi
}

verify_small_response /robots.txt 200
if [[ "$(normalized_content_type "${temporary_dir}/small-headers")" != "text/plain" ]]; then
  echo "The deployed robots.txt does not use text/plain." >&2
  exit 1
fi
if [[ "$(cat "${temporary_dir}/small-output")" != $'User-agent: *\nDisallow: /' ]]; then
  echo "The deployed robots.txt does not match the repository contract." >&2
  exit 1
fi

verify_small_response / 404
verify_small_response /asset-manifest.sha256 404
verify_small_response /.git/config 404

echo "Verified exact release identity, all 105 manifest URLs, three representative ranges, robots.txt, and private paths."
