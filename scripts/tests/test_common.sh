#!/bin/sh
# Tests for scripts/common.sh.
set -eu

TESTS_DIR="$(
  unset CDPATH
  cd -- "$(dirname -- "$0")" && pwd
)"
readonly TESTS_DIR
# shellcheck source=lib.sh
. "$TESTS_DIR/lib.sh"
# shellcheck source=../common.sh
. "$TESTS_DIR/../common.sh"

test_log_and_die() {
  assert_eq "log prefix" "[t] hello" "$(LOG_PREFIX=t log hello 2>&1)"
  assert_eq "die message" "[t] ERROR: boom" "$(sh -c ". '$TESTS_DIR/../common.sh'; LOG_PREFIX=t die boom" 2>&1 || true)"
  assert_status "die exits 1" 1 sh -c ". '$TESTS_DIR/../common.sh'; die boom"
}

test_require() {
  assert_status "require present tool" 0 sh -c ". '$TESTS_DIR/../common.sh'; require sh"
  assert_status "require missing tool" 1 sh -c ". '$TESTS_DIR/../common.sh'; require no-such-tool-xyz"
}

test_confirm() {
  assert_status "confirm with FORCE" 0 sh -c ". '$TESTS_DIR/../common.sh'; FORCE=1 confirm go"
  assert_status "confirm yes" 0 sh -c ". '$TESTS_DIR/../common.sh'; echo yes | confirm go"
  assert_status "confirm no" 1 sh -c ". '$TESTS_DIR/../common.sh'; echo no | confirm go"
}

test_resolve_region() {
  _test_tfvars="$(mktemp)"
  printf 'primary_region = "eu-west-1"\n' >"$_test_tfvars"
  assert_eq "region from tfvars" "eu-west-1" "$(AWS_REGION='' resolve_region "$_test_tfvars")"
  assert_eq "region from env" "ap-south-1" "$(AWS_REGION=ap-south-1 resolve_region "$_test_tfvars")"
  assert_eq "region default" "us-east-1" "$(AWS_REGION='' resolve_region /nonexistent)"
  rm -f "$_test_tfvars"
}

test_aws_as() {
  _test_bin="$(mktemp -d)"
  cat >"$_test_bin/aws" <<'STUB'
#!/bin/sh
echo "${AWS_PROFILE:-none} $*"
STUB
  chmod +x "$_test_bin/aws"
  assert_eq "aws_as profile" "p1 s3 ls" "$(PATH="$_test_bin:$PATH" aws_as p1 s3 ls)"
  assert_eq "aws_as no profile" "none s3 ls" "$(PATH="$_test_bin:$PATH" AWS_PROFILE='' aws_as '' s3 ls | sed 's/^ /none /')"
  rm -rf "$_test_bin"
}

test_log_and_die
test_require
test_confirm
test_resolve_region
test_aws_as
finish
