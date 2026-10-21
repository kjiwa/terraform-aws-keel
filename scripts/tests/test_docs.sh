#!/bin/sh
# Tests for scripts/docs.sh argument handling.
set -eu

TESTS_DIR="$(
  unset CDPATH
  cd -- "$(dirname -- "$0")" && pwd
)"
readonly TESTS_DIR
readonly DOCS="$TESTS_DIR/../docs.sh"
# shellcheck source=lib.sh
. "$TESTS_DIR/lib.sh"

assert_status "unknown flag prints usage" 2 sh "$DOCS" --chekc
assert_status "extra argument prints usage" 2 sh "$DOCS" --check extra
assert_status "stray word prints usage" 2 sh "$DOCS" check

finish
