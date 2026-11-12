#!/bin/sh
# Tests for scripts/rightsize-check.sh with stub aws and curl on PATH.
set -eu

TESTS_DIR="$(
  unset CDPATH
  cd -- "$(dirname -- "$0")" && pwd
)"
readonly TESTS_DIR
readonly CHECK="$TESTS_DIR/../rightsize-check.sh"
# shellcheck source=lib.sh
. "$TESTS_DIR/lib.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin"
readonly CALLS="$WORK/aws-calls"

cat >"$WORK/bin/curl" <<'STUB'
#!/bin/sh
for _arg in "$@"; do
  case "$_arg" in
  PUT) echo "token"; exit 0 ;;
  */availability-zone-id) echo "${AZ_ID:-use1-az1}"; exit 0 ;;
  */availability-zone) echo "${AZ:-us-east-1a}"; exit 0 ;;
  */instance-life-cycle) echo "${LIFECYCLE:-spot}"; exit 0 ;;
  */instance-type) echo "${OWN_TYPE:-t4g.large}"; exit 0 ;;
  esac
done
exit 22
STUB

cat >"$WORK/bin/aws" <<'STUB'
#!/bin/sh
echo "$*" >>"$CALLS"
[ "${AWS_FAIL:-}" != "$2" ] || exit 255
case "$2" in
describe-auto-scaling-groups)
  case "$*" in
  *length*) echo "${OVERRIDES:-1}" ;;
  *) echo '{}' ;;
  esac
  ;;
get-instance-types-from-instance-requirements) echo "t4g.small t4g.large" ;;
describe-spot-price-history) printf '%b' "${PRICES-t4g.large\t0.0400\nt4g.small\t0.0100\n}" ;;
get-spot-placement-scores) echo "${SCORE-8}" ;;
esac
STUB
chmod +x "$WORK/bin/curl" "$WORK/bin/aws"

printf '%s 0.00\n' "${UPTIME_S:-20000}" >"$WORK/uptime"

# run_check [VAR=value...] [-- args]; defaults to valid args.
run_check() {
  : >"$CALLS"
  env PATH="$WORK/bin:$PATH" CALLS="$CALLS" UPTIME_FILE="$WORK/uptime" "$@" \
    sh "$CHECK" us-east-1 example-asg 3
}

aws_calls() { wc -l <"$CALLS" | tr -d ' '; }

assert_status "cheaper pool with capacity replaces" 0 run_check
assert_eq "score is read for the cheapest type" 1 \
  "$(grep -c -e 'get-spot-placement-scores --instance-types t4g.small ' "$CALLS")"

assert_eq "prices are read in the instance's AZ" 1 \
  "$(grep -c -e 'describe-spot-price-history .*--availability-zone us-east-1a ' "$CALLS")"

assert_status "two overrides replace" 0 run_check OVERRIDES=2
assert_eq "each override is resolved" 2 \
  "$(grep -c -e '^ec2 get-instance-types-from-instance-requirements' "$CALLS")"
assert_eq "each override's requirements are read" 2 \
  "$(grep -c -e 'Overrides\[[01]\].InstanceRequirements' "$CALLS")"

assert_status "on-demand stays" 1 run_check LIFECYCLE=normal
assert_eq "on-demand makes no aws call" 0 "$(aws_calls)"

printf '%s 0.00\n' 600 >"$WORK/uptime"
assert_status "under the cooldown stays" 1 run_check
assert_eq "cooldown makes no aws call" 0 "$(aws_calls)"
printf '%s 0.00\n' 20000 >"$WORK/uptime"

assert_status "price within the margin stays" 1 \
  run_check "PRICES=t4g.large\t0.0400\nt4g.small\t0.0350\n"
assert_status "own price missing stays" 1 run_check "PRICES=t4g.small\t0.0100\n"
assert_status "no prices stays" 1 run_check PRICES=
assert_status "score below the minimum stays" 1 run_check SCORE=4
assert_status "score at the minimum replaces" 0 run_check SCORE=5
assert_status "score unavailable stays" 1 run_check SCORE=None
assert_status "empty score stays" 1 run_check SCORE=

for _op in describe-auto-scaling-groups get-instance-types-from-instance-requirements \
  describe-spot-price-history get-spot-placement-scores; do
  assert_status "aws $_op failure stays" 1 run_check AWS_FAIL="$_op"
done

assert_status "missing args" 2 env PATH="$WORK/bin:$PATH" sh "$CHECK"
assert_status "non-numeric hours" 2 env PATH="$WORK/bin:$PATH" sh "$CHECK" us-east-1 example-asg soon
assert_eq "usage on stderr" "1" \
  "$(env PATH="$WORK/bin:$PATH" sh "$CHECK" 2>&1 >/dev/null | grep -c -i usage)"

finish
