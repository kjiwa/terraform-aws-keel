#!/bin/sh
# Tests for scripts/tf.sh with a stub terraform that records its arguments.
set -eu

TESTS_DIR="$(
  unset CDPATH
  cd -- "$(dirname -- "$0")" && pwd
)"
readonly TESTS_DIR
readonly TF="$TESTS_DIR/../tf.sh"
# shellcheck source=lib.sh
. "$TESTS_DIR/lib.sh"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
mkdir -p "$WORK/bin" "$WORK/root" "$WORK/cfg"
cat >"$WORK/bin/terraform" <<'STUB'
#!/bin/sh
echo "$TF_DATA_DIR $*"
STUB
chmod +x "$WORK/bin/terraform"
: >"$WORK/cfg/terraform.tfvars"
: >"$WORK/cfg/backend.hcl"

run_tf() {
  PATH="$WORK/bin:$PATH" sh "$TF" "$WORK/root" "$WORK/cfg" "$@"
}

assert_eq "plan gets tfvars" \
  "$WORK/cfg/.terraform -chdir=$WORK/root plan -var-file=$WORK/cfg/terraform.tfvars -refresh=false" \
  "$(run_tf plan -refresh=false)"
assert_eq "init gets backend config" \
  "$WORK/cfg/.terraform -chdir=$WORK/root init -backend-config=$WORK/cfg/backend.hcl" \
  "$(run_tf init)"
assert_eq "output passes through" \
  "$WORK/cfg/.terraform -chdir=$WORK/root output -raw x" \
  "$(run_tf output -raw x)"
assert_status "missing args prints usage" 2 env PATH="$WORK/bin:$PATH" sh "$TF"
assert_status "missing root dir" 1 env PATH="$WORK/bin:$PATH" sh "$TF" "$WORK/none" "$WORK/cfg" plan

finish
