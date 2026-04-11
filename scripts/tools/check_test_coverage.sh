#!/usr/bin/env bash
# Check that every script in scripts/ with logic has a corresponding test file.
# Matches by: test filename containing the script name, OR test file contents
# referencing the script path or class name.
#
# Usage:
#   ./scripts/tools/check_test_coverage.sh

set -euo pipefail
cd "$(git rev-parse --show-toplevel)"

# Scripts exempt from needing direct tests (pure wiring, declarative, no logic)
EXEMPT=(
    "scripts/main.gd"
    "scripts/autoload/ui_manager.gd"
    "scripts/autoload/asset_loader.gd"
    "scripts/autoload/theme_manager.gd"
    "scripts/theme_colors.gd"
    "scripts/game/space_grid.gd"
)

missing=()

for script in $(find scripts/ -name "*.gd" -not -path "scripts/tools/*" | sort); do
    # Check if exempt
    skip=false
    for exempt in "${EXEMPT[@]}"; do
        if [[ "$script" == "$exempt" ]]; then
            skip=true
            break
        fi
    done
    if $skip; then
        continue
    fi

    # Extract the base name without extension (e.g., "state_manager")
    base=$(basename "$script" .gd)

    # Check 1: test file named test_<base>.gd exists
    if find test/ -name "test_${base}.gd" 2>/dev/null | grep -q .; then
        continue
    fi

    # Check 2: any test file references this script by path
    if grep -rql "$script" test/ 2>/dev/null; then
        continue
    fi

    # Check 3: any test file references the PascalCase class name
    # Convert snake_case to PascalCase (e.g., state_manager -> StateManager)
    pascal=$(echo "$base" | sed -r 's/(^|_)([a-z])/\U\2/g')
    if grep -rql "$pascal" test/ 2>/dev/null; then
        continue
    fi

    missing+=("$script")
done

if [[ ${#missing[@]} -gt 0 ]]; then
    echo "Scripts without test coverage:"
    echo ""
    for m in "${missing[@]}"; do
        echo "  $m"
    done
    echo ""
    echo "${#missing[@]} script(s) have no tests. Add tests or update EXEMPT list in this script."
    exit 1
fi

echo "All non-exempt scripts have test coverage."
exit 0
