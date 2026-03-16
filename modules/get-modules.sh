#!/bin/sh
set -e
set -u

# Get the directory where this script resides
MODULES_DIR="$(cd "$(dirname "$0")" && pwd)"

# Path to modules.txt inside the modules folder
MODULES_FILE="$MODULES_DIR/modules.txt"

# --- Check prerequisites ---
if [ ! -d "$MODULES_DIR" ]; then
    echo "ERROR: Modules folder not found at '$MODULES_DIR'."
    echo "The script must be placed inside the AzerothCore folder,"
    echo "and the 'modules' folder must already exist."
    exit 1
fi

if [ ! -f "$MODULES_FILE" ]; then
    echo "ERROR: modules.txt not found at '$MODULES_FILE'."
    echo "Please create a modules.txt file inside the 'modules' folder,"
    echo "listing your module Git repositories, one per line."
    exit 1
fi

echo "Installing modules from $MODULES_FILE into $MODULES_DIR..."

# --- Clone each module ---
while IFS= read -r line || [ -n "$line" ]; do
    # Skip empty lines or comments
    [ -z "$line" ] && continue
    case "$line" in \#*) continue ;; esac

    repo="$line"
    ref=""

    # Parse repo:ref format (only split on colon after .git)
    case "$line" in
        *.git:*)
            repo="${line%.git:*}.git"
            ref="${line#*.git:}"
            ;;
        *)
            repo="$line"
            ref=""
            ;;
    esac

    name="$(basename "$repo")"
    name="${name%.git}"

    TARGET_DIR="$MODULES_DIR/$name"

    if [ -d "$TARGET_DIR" ]; then
        echo "Skipping $repo (already exists at $TARGET_DIR)"
        continue
    fi

    echo "Cloning $repo..."
    git clone "$repo" "$TARGET_DIR"

    if [ -n "$ref" ]; then
        echo "Checking out $ref..."
        (
            cd "$TARGET_DIR"
            git checkout "$ref"
        )
    fi

done < "$MODULES_FILE"

echo "All modules installed successfully (or already present)."
