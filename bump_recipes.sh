#!/bin/bash
# Bump recipes in all subfolders that contain a recipe.yaml

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

for recipe in "$SCRIPT_DIR"/*/recipe.yaml; do
    dir="$(dirname "$recipe")"
    name="$(basename "$dir")"
    echo "==> Bumping $name ..."
    rattler-build bump-recipe -r "$dir" || echo "  !! Failed to bump $name, skipping."
done

echo "Done."
