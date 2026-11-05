#!/usr/bin/env bash
# Uploads one SBOM or Cargo.lock to Light Squares SSCI. Reads its inputs from
# SSCI_* variables (see action.yml) and needs only bash and curl; jq, when
# present, adds the step outputs and the job summary.
set -euo pipefail

fail() {
  echo "::error::$1" >&2
  exit 1
}

# Percent-encodes everything except unreserved characters, so that a ref such as
# `refs/heads/fix+docs` arrives as it is. Works byte by byte; the mask keeps bytes
# above 127 positive in every bash version.
urlencode() {
  local LC_ALL=C value=$1 encoded="" c byte i
  for ((i = 0; i < ${#value}; i++)); do
    c=${value:i:1}
    case $c in
      [a-zA-Z0-9.~_-]) encoded+=$c ;;
      *)
        printf -v byte '%d' "'$c"
        printf -v c '%%%02X' $((byte & 255))
        encoded+=$c
        ;;
    esac
  done
  printf '%s' "$encoded"
}

# Text from the server, on one line, so that it cannot start a workflow command.
one_line() {
  tr -s '\r\n' '  ' | head -c 500
}

[[ -n ${SSCI_TOKEN:-} ]] || fail "The token input is empty. Pass the upload token from a secret."
echo "::add-mask::$SSCI_TOKEN"
# Anything else, such as GITHUB_TOKEN passed by mistake, never leaves the runner.
[[ $SSCI_TOKEN == ssci_* ]] || fail "The token input is not an SSCI upload token."
[[ -n ${SSCI_FILE:-} ]] || fail "The file input is empty."
[[ -f $SSCI_FILE ]] || fail "No such file: $SSCI_FILE"
[[ ${SSCI_URL:-} == https://* ]] || fail "The url input must start with https://."
release=${SSCI_RELEASE:-false}
[[ $release == true || $release == false ]] ||
  fail "The release input must be true or false, not '$release'."

query="ref=$(urlencode "${SSCI_REF:-}")&commit=$(urlencode "${SSCI_COMMIT:-}")"
query+="&version=$(urlencode "${SSCI_VERSION:-}")&release=$release"

response=$(mktemp)
trap 'rm -f "$response"' EXIT
# The header goes through stdin, so the token is not in curl's command line.
status=$(printf 'Authorization: Bearer %s\n' "$SSCI_TOKEN" |
  curl -sS --proto =https --connect-timeout 30 --max-time 300 \
    -X POST -o "$response" -w '%{http_code}' \
    -H @- \
    --data-binary "@$SSCI_FILE" \
    "$SSCI_URL?$query") || fail "Could not reach $SSCI_URL."

if [[ $status != 201 ]]; then
  message=$(sed -n 's/.*"error" *: *"\([^"]*\)".*/\1/p' "$response" | one_line)
  fail "Upload refused (HTTP $status): ${message:-$(one_line <"$response")}"
fi

if ! command -v jq >/dev/null; then
  echo "Reported $SSCI_FILE."
  exit 0
fi
read_json() {
  jq -r "$1 // empty" "$response" 2>/dev/null || true
}
id=$(read_json .id)
packages=$(read_json .component_count)
added=$(read_json .changes.added)
removed=$(read_json .changes.removed)
changed=$(read_json .changes.changed)
# Only values of the expected shape reach the job's outputs and log.
uuid='^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
if ! [[ $id =~ $uuid && $packages =~ ^[0-9]+$ ]]; then
  echo "::warning::Reported $SSCI_FILE, but the answer was not understood, so no outputs are set."
  exit 0
fi
summary="Reported $packages packages from \`$SSCI_FILE\` to Light Squares SSCI"
if [[ $added =~ ^[0-9]+$ && $removed =~ ^[0-9]+$ && $changed =~ ^[0-9]+$ ]]; then
  summary+=" (+$added −$removed ~$changed since the previous upload it is compared with)"
fi
echo "$summary."
if [[ -n ${GITHUB_OUTPUT:-} ]]; then
  {
    echo "inventory-id=$id"
    echo "packages=$packages"
  } >>"$GITHUB_OUTPUT"
fi
if [[ -n ${GITHUB_STEP_SUMMARY:-} ]]; then
  echo "$summary." >>"$GITHUB_STEP_SUMMARY"
fi
