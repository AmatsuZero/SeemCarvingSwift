#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
wrapper="${script_dir:h}/swiftly-6.3.3.sh"
temporary_dir="$(mktemp -d)"
trap 'rm -rf "${temporary_dir}"' EXIT

fail() {
  print -u2 "FAIL: $*"
  exit 1
}

fake_swiftly="${temporary_dir}/swiftly"
invocation_log="${temporary_dir}/invocation.log"
cat > "${fake_swiftly}" <<'FAKE_SWIFTLY'
#!/bin/zsh
set -euo pipefail

if [[ "$1" == "list" ]]; then
  print 'Installed release toolchains'
  print '----------------------------'
  print "${SWIFTLY_LIST_OUTPUT:-Swift 6.3.3 (in use) (default)}"
  exit 0
fi

printf '%s\n' "$@" > "${SWIFTLY_INVOCATION_LOG}"
FAKE_SWIFTLY
chmod +x "${fake_swiftly}"

SWIFTLY_BIN="${fake_swiftly}" \
SWIFTLY_INVOCATION_LOG="${invocation_log}" \
  "${wrapper}" swift package describe

expected_invocation=$'run\nswift\npackage\ndescribe\n+6.3.3'
actual_invocation="$(<"${invocation_log}")"
[[ "${actual_invocation}" == "${expected_invocation}" ]] ||
  fail "expected Swiftly invocation ${expected_invocation@q}, got ${actual_invocation@q}"

missing_toolchain_output="${temporary_dir}/missing-toolchain.out"
if SWIFTLY_BIN="${fake_swiftly}" \
  SWIFTLY_LIST_OUTPUT='Swift 6.3.2 (in use) (default)' \
  "${wrapper}" swift package describe >"${missing_toolchain_output}" 2>&1; then
  fail 'expected a missing required Swiftly toolchain failure'
fi
grep -Fq 'Required Swiftly toolchain 6.3.3 is not installed.' "${missing_toolchain_output}" ||
  fail 'missing toolchain error did not identify the required version'

mismatch_output="${temporary_dir}/mismatch.out"
if SWIFTLY_BIN="${fake_swiftly}" \
  "${wrapper}" swift package describe +6.3.2 >"${mismatch_output}" 2>&1; then
  fail 'expected a conflicting toolchain selector failure'
fi
grep -Fq 'WASM Swift toolchain mismatch: required selector is +6.3.3; received +6.3.2.' \
  "${mismatch_output}" || fail 'mismatch error did not identify both selectors'

missing_swiftly_output="${temporary_dir}/missing-swiftly.out"
if SWIFTLY_BIN="${temporary_dir}/not-swiftly" \
  "${wrapper}" swift package describe >"${missing_swiftly_output}" 2>&1; then
  fail 'expected a missing Swiftly failure'
fi
grep -Fq 'Swiftly executable not found:' "${missing_swiftly_output}" ||
  fail 'missing Swiftly error was not clear'

print 'Swiftly 6.3.3 wrapper test passed.'
