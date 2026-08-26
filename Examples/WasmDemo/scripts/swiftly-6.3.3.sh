#!/bin/zsh
set -euo pipefail

required_toolchain='6.3.3'
required_selector="+${required_toolchain}"

fail() {
  print -u2 "$*"
  exit 1
}

if [[ $# -eq 0 ]]; then
  fail "Usage: ${0:t} <Swift command> [arguments...]"
fi

if [[ -n "${SWIFTLY_BIN:-}" ]]; then
  swiftly_bin="${SWIFTLY_BIN}"
elif [[ -x "${HOME}/.swiftly/bin/swiftly" ]]; then
  swiftly_bin="${HOME}/.swiftly/bin/swiftly"
elif swiftly_bin="$(command -v swiftly 2>/dev/null)"; then
  :
else
  fail 'Swiftly executable not found: set SWIFTLY_BIN or install Swiftly from https://www.swift.org/install/'
fi

[[ -x "${swiftly_bin}" ]] ||
  fail "Swiftly executable not found: ${swiftly_bin}. Set SWIFTLY_BIN to an executable Swiftly binary."

for argument in "$@"; do
  if [[ "${argument}" == +* ]]; then
    fail "WASM Swift toolchain mismatch: required selector is ${required_selector}; received ${argument}."
  fi
done

if ! installed_toolchains="$("${swiftly_bin}" list 2>&1)"; then
  fail "Unable to inspect Swiftly toolchains with ${swiftly_bin}. Ensure Swiftly is initialized."
fi

if ! grep -Eq "^Swift ${required_toolchain//./\\.}([[:space:]]|$)" <<< "${installed_toolchains}"; then
  fail "Required Swiftly toolchain ${required_toolchain} is not installed. Run: ${swiftly_bin} install ${required_toolchain}"
fi

exec "${swiftly_bin}" run "$@" "${required_selector}"
