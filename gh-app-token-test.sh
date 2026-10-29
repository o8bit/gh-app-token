#!/bin/sh
# Tests for gh-app-token.
#
# Offline: exercises the pure helpers only - no network, no real credentials.
# Plain assertions rather than a framework because the script runs in a minimal
# image and must not acquire dependencies just to be testable.
#
# Run: sh gh-app-token/gh-app-token-test.sh
set -u

GHAT_SKIP_MAIN=1
export GHAT_SKIP_MAIN
# shellcheck source=/dev/null
. "$(dirname "$0")/gh-app-token"
# The script under test sets -e; sourcing imports it, which would abort this
# suite on the first deliberately-failing assertion.
set +e

passed=0
failed=0

check() {
  if [ "$2" = "$3" ]; then
    passed=$((passed + 1)); printf '  ok   %s\n' "$1"
  else
    failed=$((failed + 1)); printf '  FAIL %s\n    expected: %s\n    actual:   %s\n' "$1" "$3" "$2"
  fi
}

contains() {
  case "$2" in
    *"$3"*) passed=$((passed + 1)); printf '  ok   %s\n' "$1" ;;
    *) failed=$((failed + 1)); printf '  FAIL %s\n    %s not found in: %s\n' "$1" "$3" "$2" ;;
  esac
}

fails_with() {
  _out=$( (GITHUB_APP_PRIVATE_KEY="$2" ghat_write_key "$TMP/attempt.pem") 2>&1 )
  if [ -n "$_out" ]; then
    contains "$1" "$_out" "$3"
  else
    failed=$((failed + 1)); printf '  FAIL %s\n    expected failure, got success\n' "$1"
  fi
}

# ghat_fail exits, so validation runs in a subshell and is judged by its output.
accepts() {
  _label=$1; shift
  _out=$( (ghat_validate_repositories "$@") 2>&1 )
  check "accepts $_label" "$?:$_out" '0:'
}

rejects() {
  _label=$1; _expect=$2; shift 2
  _out=$( (ghat_validate_repositories "$@") 2>&1 )
  _rc=$?
  check "rejects $_label (exit)" "$_rc" '1'
  contains "rejects $_label (message)" "$_out" "$_expect"
}

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT INT TERM

b64u_decode() {
  _s=$1
  case $(( ${#_s} % 4 )) in
    2) _s="${_s}==" ;;
    3) _s="${_s}=" ;;
  esac
  printf '%s' "$_s" | tr '_-' '/+' | base64 -d
}

openssl genrsa -out "$TMP/test.pem" 2048 2>/dev/null
openssl rsa -in "$TMP/test.pem" -pubout -out "$TMP/test.pub" 2>/dev/null

echo 'ghat_b64u'
check 'strips padding' "$(printf 'a' | ghat_b64u)" 'YQ'
check 'encodes without newlines' "$(printf 'abc' | ghat_b64u)" 'YWJj'
check 'uses the url alphabet' "$(printf '\373\377' | ghat_b64u)" '-_8'

echo 'ghat_repositories'
check 'single entry' "$(ghat_repositories 'org-a/x')" 'org-a/x'
check 'several entries, one per line' "$(ghat_repositories 'org-a/x,org-b/y' | tr '\n' ' ')" 'org-a/x org-b/y '
check 'tolerates spaces after commas' "$(ghat_repositories 'org-a/x, org-b/y' | tr '\n' ' ')" 'org-a/x org-b/y '
check 'drops a trailing comma' "$(ghat_repositories 'org-a/x,' | tr '\n' ' ')" 'org-a/x '
check 'empty list yields nothing' "$(ghat_repositories '')" ''

echo 'ghat_validate_repositories'
accepts 'owner/repo' 'org-a/x'
accepts 'owner/* and several owners' 'org-a/*' 'org-b/my.repo_1' 'org-b/other-repo'
rejects 'a bare owner' 'is not owner/repo' 'org-a'
rejects 'an empty owner' 'is not owner/repo' '/x'
rejects 'an empty repository' 'is not owner/repo' 'org-a/'
rejects 'a nested path' 'is not owner/repo' 'org-a/x/y'
rejects 'json in the owner' 'invalid owner name' 'org"a/x'
rejects 'json in the repository' 'invalid repository name' 'org-a/x"}'
rejects 'a partial wildcard' 'invalid repository name' 'org-a/app-*'
rejects 'a later bad entry' 'is not owner/repo' 'org-a/x' 'org-b'
rejects 'owner/* alongside a named repository' 'cannot be combined' 'org-a/x' 'org-a/*'

echo 'ghat_owners'
check 'one owner per line, in first-seen order, without repeats' \
  "$(ghat_owners org-b/x org-a/y org-b/z | tr '\n' ' ')" 'org-b org-a '

echo 'ghat_owner_repos'
check 'only the named owner' "$(ghat_owner_repos org-a org-a/x org-b/y org-a/z | tr '\n' ' ')" 'x z '
check 'a wildcard is a lone *' "$(ghat_owner_repos org-a org-a/'*' org-b/y)" '*'

echo 'ghat_mint_body'
check 'limits the token to the named repositories' \
  "$(ghat_mint_body '{"contents":"read"}' 'x
y')" '{"permissions":{"contents":"read"},"repositories":["x","y"]}'
check 'a wildcard sends no repository list' \
  "$(ghat_mint_body '{"contents":"read"}' '*')" '{"permissions":{"contents":"read"}}'

echo 'ghat_main'
contains 'refuses the v1 GITHUB_APP_ORGS' \
  "$( (GITHUB_APP_ORGS=org-a GITHUB_APP_REPOSITORIES=org-a/x ghat_main) 2>&1 )" \
  'GITHUB_APP_ORGS was replaced by GITHUB_APP_REPOSITORIES'
contains 'refuses permissions that are not a JSON object' \
  "$( (GITHUB_APP_ORGS='' GITHUB_APP_PRIVATE_KEY=k GITHUB_APP_ID=1 GITHUB_APP_REPOSITORIES=org-a/x \
      GITHUB_APP_TOKEN_DIR="$TMP/tokens" GITHUB_APP_PERMISSIONS='contents:read' ghat_main) 2>&1 )" \
  'GITHUB_APP_PERMISSIONS is not a JSON object'
# A directory named like the owner, so owner/* would match a file if globbed.
mkdir -p "$TMP/glob/org-a" && : >"$TMP/glob/org-a/file"
contains 'does not glob owner/* against the working directory' \
  "$(cd "$TMP/glob" && (GITHUB_APP_ORGS='' GITHUB_APP_PRIVATE_KEY=k GITHUB_APP_ID=1 \
      GITHUB_APP_REPOSITORIES='org-a/*,org-a/x' GITHUB_APP_TOKEN_DIR="$TMP/tokens" ghat_main) 2>&1 )" \
  "'org-a/*' cannot be combined"

echo 'ghat_token_path'
check 'joins dir and name' "$(ghat_token_path /tokens org-a)" '/tokens/org-a.token'
check 'tolerates a trailing slash' "$(ghat_token_path /tokens/ org-a)" '/tokens/org-a.token'

echo 'ghat_jwt'
JWT=$(ghat_jwt "$TMP/test.pem" '123456' 1786013400)
check 'has three dot-separated segments' "$(printf '%s' "$JWT" | awk -F. '{print NF}')" '3'
H=$(printf '%s' "$JWT" | cut -d. -f1)
C=$(printf '%s' "$JWT" | cut -d. -f2)
Sg=$(printf '%s' "$JWT" | cut -d. -f3)
check 'header declares RS256' "$(b64u_decode "$H")" '{"alg":"RS256","typ":"JWT"}'
check 'claims are exact' "$(b64u_decode "$C")" '{"iat":1786013340,"exp":1786013940,"iss":"123456"}'
# Derived from the produced JWT, not from literals: a broken ghat_jwt must fail these.
IAT=$(b64u_decode "$C" | sed -n 's/.*"iat":\([0-9]*\).*/\1/p')
EXP=$(b64u_decode "$C" | sed -n 's/.*"exp":\([0-9]*\).*/\1/p')
check 'iat is backdated 60s for clock skew' "$((1786013400 - IAT))" '60'
check 'exp is within githubs 10 minute ceiling' \
  "$( [ "$((EXP - 1786013400))" -le 600 ] && echo yes || echo no )" 'yes'
b64u_decode "$Sg" >"$TMP/sig.bin"
printf '%s' "$H.$C" >"$TMP/signed.txt"
check 'signature verifies against the public key' \
  "$(openssl dgst -sha256 -verify "$TMP/test.pub" -signature "$TMP/sig.bin" "$TMP/signed.txt" 2>&1)" \
  'Verified OK'

echo 'ghat_write_key'
GITHUB_APP_PRIVATE_KEY=$(cat "$TMP/test.pem") ghat_write_key "$TMP/from-raw.pem"
check 'accepts a raw pem' "$(openssl rsa -in "$TMP/from-raw.pem" -noout -check 2>&1)" 'RSA key ok'
check 'raw pem written 0600' "$(ls -l "$TMP/from-raw.pem" | cut -c2-10)" 'rw-------'
GITHUB_APP_PRIVATE_KEY=$(base64 <"$TMP/test.pem" | tr -d '\n') ghat_write_key "$TMP/from-b64.pem"
check 'accepts a base64 pem' "$(openssl rsa -in "$TMP/from-b64.pem" -noout -check 2>&1)" 'RSA key ok'
GITHUB_APP_PRIVATE_KEY=$(base64 <"$TMP/test.pem") ghat_write_key "$TMP/from-b64nl.pem"
check 'accepts a base64 pem containing newlines' "$(openssl rsa -in "$TMP/from-b64nl.pem" -noout -check 2>&1)" 'RSA key ok'
fails_with 'rejects a non-key non-base64 value' 'not a key!!' 'not a valid RSA private key'
fails_with 'rejects base64 that is not a key' "$(printf 'hello world' | base64)" 'not a valid RSA private key'
fails_with 'rejects an empty value' '' 'not a valid RSA private key'
fails_with 'rejects a truncated pem' '-----BEGIN RSA PRIVATE KEY-----
bm90IGEga2V5
-----END RSA PRIVATE KEY-----' 'not a valid RSA private key'

echo 'ghat_write_token'
ghat_write_token "$TMP/tok" 'ghs_123456_ey.Jz-a_b'
check 'writes the token verbatim' "$(cat "$TMP/tok")" 'ghs_123456_ey.Jz-a_b'
check 'token file is 0600' "$(ls -l "$TMP/tok" | cut -c2-10)" 'rw-------'

printf '\n%s passed, %s failed\n' "$passed" "$failed"
[ "$failed" -eq 0 ] || exit 1
