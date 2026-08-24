#!/usr/bin/env bash
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd -- "$script_dir/.." && pwd)"
cd "$repo_root"

fail() {
    echo "Target-boundary check failed: $*" >&2
    exit 1
}

require_allowed_imports() {
    local target="$1"
    shift
    local allowed=("$@")
    local files=()
    local module

    while IFS= read -r -d '' file; do
        files+=("$file")
    done < <(find "$target" -type f -name '*.swift' -print0)

    [[ "${#files[@]}" -gt 0 ]] || fail "$target has no Swift sources to scan."

    while IFS= read -r module; do
        local accepted=false
        local candidate
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

require_no_conditionals() {
    local target="$1"
    if grep -R -nE '^[[:space:]]*#(if|elseif|else|endif)([[:space:]]|$)' "$target"; then
        fail "$target must not contain conditional compilation."
    fi
}

require_no_imports() {
    local target="$1"
    local forbidden="$2"
    if grep -R -nE "^[[:space:]]*import[[:space:]]+(${forbidden})([[:space:]]|$)" "$target"; then
        fail "$target imports a forbidden framework."
    fi
}

require_outer_framework_guard() {
    local target="$1"
    local framework="$2"
    local file first last conditional_count

    while IFS= read -r -d '' file; do
        first="$(awk 'NF { print; exit }' "$file")"
        last="$(awk 'NF { line = $0 } END { print line }' "$file")"
        conditional_count="$(grep -Ec '^[[:space:]]*#(if|elseif|else|endif)([[:space:]]|$)' "$file" || true)"

        [[ "$first" == "#if canImport($framework)" ]] \
            || fail "$file must start with '#if canImport($framework)'."
        [[ "$last" == '#endif' ]] \
            || fail "$file must end with '#endif'."
        [[ "$conditional_count" == '2' ]] \
            || fail "$file may contain only one outer canImport guard."
    done < <(find "$target" -type f -name '*.swift' -print0)
}

core='Sources/SeamCarvingCore'
runtime='Sources/SeamCarvingAppleRuntime'
imaging='Sources/SeamCarvingAppleImaging'
core_video='Sources/SeamCarvingCoreVideo'
uikit='Sources/SeamCarvingUIKit'
appkit='Sources/SeamCarvingAppKit'

# Core is intentionally portable: Foundation and Dispatch are the only allowed
# host modules, and no compile-time platform selection may enter this target.
require_allowed_imports "$core" Foundation Dispatch
require_no_conditionals "$core"

# Runtime chooses capabilities through its Apple backend implementations, not
# through platform compilation branches.
require_allowed_imports "$runtime" Foundation SeamCarvingCore SeamCarvingAccelerate SeamCarvingMetal
require_no_conditionals "$runtime"

require_no_imports "$imaging" 'UIKit|AppKit|CoreVideo'
require_no_conditionals "$imaging"

require_no_imports "$core_video" 'UIKit|AppKit'
require_no_conditionals "$core_video"

# SwiftPM may discover these targets on a host without their framework. The
# sole exception to the no-conditional rule is one whole-file own-framework
# guard per source file; no sibling framework or Catalyst branch is permitted.
require_no_imports "$uikit" 'AppKit|CoreVideo'
require_no_imports "$appkit" 'UIKit|CoreVideo'
if grep -R -n 'targetEnvironment' "$uikit" "$appkit"; then
    fail 'UIKit and AppKit adapters must not contain targetEnvironment branches.'
fi
require_outer_framework_guard "$uikit" UIKit
require_outer_framework_guard "$appkit" AppKit
