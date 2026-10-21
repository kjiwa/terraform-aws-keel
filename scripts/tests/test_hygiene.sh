#!/bin/sh
# Tests for scripts/hygiene.sh. Offending strings are assembled at run time so
# this file itself stays clean.
set -eu

TESTS_DIR="$(
  unset CDPATH
  cd -- "$(dirname -- "$0")" && pwd
)"
readonly TESTS_DIR
readonly HYGIENE="$TESTS_DIR/../hygiene.sh"
# shellcheck source=lib.sh
. "$TESTS_DIR/lib.sh"

# check_line NAME EXPECTED_STATUS CONTENT
check_line() {
  _check_file="$WORK/case.txt"
  printf '%s\n' "$3" >"$_check_file"
  assert_status "$1" "$2" sh "$HYGIENE" "$_check_file"
}

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

check_line "clean text" 0 "terraform apply with var.account_id"
check_line "account id" 1 "account $(printf '%s%s' 1234 56789012) here"
check_line "13 digits is not an id" 0 "serial $(printf '%s%s' 1234 567890123)"
check_line "hex run is not an id" 0 "sha ab$(printf '%s%s' 1234 56789012)cd"
check_line "profile env" 1 "export AWS_PROFILE=$(printf 'my%s' admin)"
check_line "profile flag" 1 "aws s3 ls --profile $(printf 'my%s' admin)"
check_line "profile hcl" 1 "profile = \"$(printf 'my%s' admin)\""
# shellcheck disable=SC2016 # the line under test must stay literal
check_line "profile variable" 0 'AWS_PROFILE="$profile" aws "$@"'
check_line "personal email" 1 "mail $(printf 'someone@%s.com' gmail)"
check_line "other email" 0 "mail someone@example.com"
check_line "home path" 1 "cd /$(printf 'Users')/someone/src"
check_line "linux home path" 1 "cd /$(printf 'home')/someone/src"

printf '%s\n' "x" >"$WORK/a.txt"
printf '%s\n' "/$(printf 'Users')/someone/x" >"$WORK/b.txt"
assert_status "any dirty file fails" 1 sh "$HYGIENE" "$WORK/a.txt" "$WORK/b.txt"
assert_status "missing file is skipped" 0 sh "$HYGIENE" "$WORK/none.txt"

finish
