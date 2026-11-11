#!/bin/sh
# Every KMS key and backup vault under modules/ must carry prevent_destroy.
set -eu

TESTS_DIR="$(
  unset CDPATH
  cd -- "$(dirname -- "$0")" && pwd
)"
readonly TESTS_DIR
readonly MODULES="$TESTS_DIR/../../modules"
# shellcheck source=lib.sh
. "$TESTS_DIR/lib.sh"

# unprotected FILE: prints "type.name" for each key or vault block without
# prevent_destroy = true. Blocks end at the first closing brace in column 0.
unprotected() {
  awk '
    /^resource "aws_(kms_key|backup_vault)" / {
      name = $2 "." $3
      gsub(/"/, "", name)
      open = 1
      guarded = 0
      next
    }
    open && /^[[:space:]]*prevent_destroy[[:space:]]*=[[:space:]]*true/ { guarded = 1 }
    open && /^}/ {
      if (!guarded) print name
      open = 0
    }
  ' "$1"
}

# scanned FILE: prints "type.name" for each key or vault block.
scanned() {
  grep -E '^resource "aws_(kms_key|backup_vault)" ' "$1" | awk '{ print $2 "." $3 }' | tr -d '"'
}

main() {
  _main_count=0
  for _main_file in "$MODULES"/*/*.tf; do
    for _main_res in $(unprotected "$_main_file"); do
      _main_rel="${_main_file#"$MODULES"/}"
      assert_eq "$_main_rel $_main_res has prevent_destroy" "protected" "unprotected"
    done
  done
  for _main_file in "$MODULES"/*/*.tf; do
    _main_count=$((_main_count + $(scanned "$_main_file" | wc -l)))
  done
  assert_eq "scanned at least one key or vault" "yes" "$([ "$_main_count" -gt 0 ] && echo yes || echo no)"
  finish
}

main "$@"
