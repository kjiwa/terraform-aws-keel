#!/bin/sh
# Fails when a file contains an AWS account ID (12 digits), an AWS profile
# name, a personal email address, or a home directory path.
#
#   ./hygiene.sh FILE...
set -eu

readonly PATTERN_ACCOUNT_ID='(^|[^0-9A-Za-z])[0-9]{12}([^0-9A-Za-z]|$)'
readonly PATTERN_PROFILE='(AWS_PROFILE=|--profile[= ])["'"'"']?[A-Za-z0-9]|profile[[:space:]]*=[[:space:]]*"[A-Za-z0-9]'
readonly PATTERN_EMAIL='[A-Za-z0-9._%+-]+@(gmail|googlemail|outlook|hotmail|yahoo|icloud|proton|protonmail)\.(com|me)'
readonly PATTERN_HOME='/(Users|home)/[A-Za-z0-9._-]+/'

_check() {
  _check_hits="$(grep -InE -e "$2" "$3" || true)"
  [ -z "$_check_hits" ] && return 0
  printf '%s\n' "$_check_hits" | sed "s|^|$3:$1: |" >&2
  return 1
}

main() {
  _main_status=0
  for _main_file in "$@"; do
    [ -f "$_main_file" ] || continue
    _check "account-id" "$PATTERN_ACCOUNT_ID" "$_main_file" || _main_status=1
    _check "profile" "$PATTERN_PROFILE" "$_main_file" || _main_status=1
    _check "email" "$PATTERN_EMAIL" "$_main_file" || _main_status=1
    _check "home-path" "$PATTERN_HOME" "$_main_file" || _main_status=1
  done
  [ "$_main_status" -eq 0 ] || echo "hygiene: remove the identifiers above" >&2
  return "$_main_status"
}

main "$@"
