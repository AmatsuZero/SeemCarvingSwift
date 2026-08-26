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

[[ "$1" == 'run' ]] || exit 0
shift
command="$1"
shift
selector_processing_enabled=1
selected_toolchain=''
forwarded_argv=("${command}")
for argument in "$@"; do
  if [[ "${selector_processing_enabled}" -eq 0 ]]; then
    forwarded_argv+=("${argument}")
  elif [[ "${argument}" == '++' ]]; then
    selector_processing_enabled=0
  elif [[ "${argument}" == ++* ]]; then
    forwarded_argv+=("${argument:1}")
  elif [[ "${argument}" == +* ]]; then
    selected_toolchain="${argument}"
  else
    forwarded_argv+=("${argument}")
  fi
done

[[ -z "${SWIFTLY_SELECTED_TOOLCHAIN_LOG:-}" ]] ||
  print -r -- "${selected_toolchain}" > "${SWIFTLY_SELECTED_TOOLCHAIN_LOG}"
[[ -z "${SWIFTLY_FORWARDED_ARGV_LOG:-}" ]] ||
  printf '%s\n' "${forwarded_argv[@]}" > "${SWIFTLY_FORWARDED_ARGV_LOG}"
FAKE_SWIFTLY
chmod +x "${fake_swiftly}"

SWIFTLY_BIN="${fake_swiftly}" \
SWIFTLY_INVOCATION_LOG="${invocation_log}" \
  "${wrapper}" swift package describe

expected_invocation=$'run\nswift\n+6.3.3\npackage\ndescribe'
actual_invocation="$(<"${invocation_log}")"
[[ "${actual_invocation}" == "${expected_invocation}" ]] ||
  fail "expected Swiftly invocation ${expected_invocation@q}, got ${actual_invocation@q}"

escaped_invocation_log="${temporary_dir}/escaped-invocation.log"
escaped_selected_toolchain_log="${temporary_dir}/escaped-selected-toolchain.log"
escaped_forwarded_argv_log="${temporary_dir}/escaped-forwarded-argv.log"
SWIFTLY_BIN="${fake_swiftly}" \
SWIFTLY_INVOCATION_LOG="${escaped_invocation_log}" \
SWIFTLY_SELECTED_TOOLCHAIN_LOG="${escaped_selected_toolchain_log}" \
SWIFTLY_FORWARDED_ARGV_LOG="${escaped_forwarded_argv_log}" \
  "${wrapper}" swift package describe ++literal ++ +literal

expected_escaped_invocation=$'run\nswift\n+6.3.3\npackage\ndescribe\n++literal\n++\n+literal'
actual_escaped_invocation="$(<"${escaped_invocation_log}")"
[[ "${actual_escaped_invocation}" == "${expected_escaped_invocation}" ]] ||
  fail "expected escaped invocation ${expected_escaped_invocation@q}, got ${actual_escaped_invocation@q}"
[[ "$(<"${escaped_selected_toolchain_log}")" == '+6.3.3' ]] ||
  fail 'escaped literal arguments replaced the required Swiftly toolchain selector'
expected_forwarded_argv=$'swift\npackage\ndescribe\n+literal\n+literal'
actual_forwarded_argv="$(<"${escaped_forwarded_argv_log}")"
[[ "${actual_forwarded_argv}" == "${expected_forwarded_argv}" ]] ||
  fail "expected escaped literals to reach Swift as ${expected_forwarded_argv@q}, got ${actual_forwarded_argv@q}"

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
