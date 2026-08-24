#!/usr/bin/env bash
# Verifies the deliberately narrow imports at the isolated browser-WASM bridge.
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
demo_dir="$(cd -- "$script_dir/.." && pwd)"
swift_dir="$demo_dir/swift"

fail() {
  printf 'WASM boundary check failed: %s\n' "$*" >&2
  exit 1
}

require_allowed_imports() {
  local target="$1"
  shift
  local allowed=("$@")
  local files=()
  local module candidate accepted

  while IFS= read -r -d '' file; do
    files+=("$file")
  done < <(find "$target" -type f -name '*.swift' -print0)
  ((${#files[@]} > 0)) || fail "$target has no Swift sources to scan."

  while IFS= read -r module; do
    accepted=false
    for candidate in "${allowed[@]}"; do
      if [[ "$module" == "$candidate" ]]; then
        accepted=true
        break
      fi
    done
    "$accepted" || fail "$target imports unapproved module '$module'."
  done < <(awk '
    /^[[:space:]]*(@[^[:space:]]+[[:space:]]+)*import[[:space:]]+/ {
      for (i = 1; i <= NF; i++) {
        if ($i == "import" && (i + 1) <= NF) {
          print $(i + 1)
          break
        }
      }
    }
  ' "${files[@]}")
}

# The host-testable bridge must remain free of browser and Apple SDK imports.
require_allowed_imports "$swift_dir/Sources/WasmBridgeCore" SeamCarvingCore
# JavaScriptEventLoop is the JavaScriptKit executor product used by the worker.
require_allowed_imports "$swift_dir/Sources/WasmBridgeWorker" \
  WasmBridgeCore JavaScriptKit JavaScriptEventLoop

printf 'WASM bridge import boundaries passed.\n'
