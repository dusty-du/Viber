#!/bin/bash
#
# VibeProxy Update Script
#
# Manages upstream updates and local customizations via patches.
# This script handles:
#   - Fetching updates from upstream
#   - Resetting managed files to upstream state
#   - Re-applying local patches
#   - Generating patches from current changes
#
# Usage:
#   ./update.sh              Apply patches to managed files
#   ./update.sh --apply      Same as above (explicit)
#   ./update.sh --generate   Generate patches from current local changes
#   ./update.sh --status     Show patch status and managed file state

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCHES_DIR="$PROJECT_DIR/patches"
ASSETS_DIR="$PATCHES_DIR/assets"

# Files managed by vibeproxy patches (relative to PROJECT_DIR)
MANAGED_FILES=(
    "src/Sources/AuthStatus.swift"
    "src/Sources/ServerManager.swift"
    "src/Sources/SettingsView.swift"
    "src/Info.plist"
)

# Binary assets that can't be in patches
BINARY_ASSETS=(
    "icon-kimi.png:src/Sources/Resources/icon-kimi.png"
)

# Patch files
KIMI_UI_PATCH="$PATCHES_DIR/vibeproxy-kimi-ui.patch"
SPARKLE_FEED_PATCH="$PATCHES_DIR/vibeproxy-sparkle-feed.patch"

usage() {
    echo "Usage: $0 [--apply|--generate|--status]"
    echo ""
    echo "Commands:"
    echo "  (no args)    Apply patches to managed files (same as --apply)"
    echo "  --apply      Reset managed files to upstream and apply patches"
    echo "  --generate   Generate patches from current local changes"
    echo "  --status     Show patch status and managed file state"
    echo ""
    echo "Managed files:"
    for f in "${MANAGED_FILES[@]}"; do
        echo "  - $f"
    done
    echo ""
    echo "Binary assets (copied separately):"
    for asset in "${BINARY_ASSETS[@]}"; do
        src="${asset%%:*}"
        echo "  - $src"
    done
}

# Check if a file has local modifications
file_is_modified() {
    local file="$1"
    git diff --quiet HEAD -- "$file" 2>/dev/null
    return $?
}

# Show status of patches and managed files
show_status() {
    echo -e "${BLUE}=== Patch Status ===${NC}"
    echo ""

    # Check patches exist
    echo -e "${BLUE}Patch files:${NC}"
    if [ -f "$KIMI_UI_PATCH" ]; then
        echo -e "  ${GREEN}[EXISTS]${NC} vibeproxy-kimi-ui.patch"
    else
        echo -e "  ${RED}[MISSING]${NC} vibeproxy-kimi-ui.patch"
    fi

    if [ -f "$SPARKLE_FEED_PATCH" ]; then
        echo -e "  ${GREEN}[EXISTS]${NC} vibeproxy-sparkle-feed.patch"
    else
        echo -e "  ${RED}[MISSING]${NC} vibeproxy-sparkle-feed.patch"
    fi

    if [ -f "$PATCHES_DIR/cliproxyapiplus-kimi-support.patch" ]; then
        echo -e "  ${GREEN}[EXISTS]${NC} cliproxyapiplus-kimi-support.patch"
    else
        echo -e "  ${RED}[MISSING]${NC} cliproxyapiplus-kimi-support.patch"
    fi
    echo ""

    # Check binary assets
    echo -e "${BLUE}Binary assets:${NC}"
    for asset in "${BINARY_ASSETS[@]}"; do
        src="${asset%%:*}"
        if [ -f "$ASSETS_DIR/$src" ]; then
            echo -e "  ${GREEN}[EXISTS]${NC} $src"
        else
            echo -e "  ${RED}[MISSING]${NC} $src"
        fi
    done
    echo ""

    # Check managed file status
    echo -e "${BLUE}Managed files:${NC}"
    for file in "${MANAGED_FILES[@]}"; do
        if [ ! -f "$PROJECT_DIR/$file" ]; then
            echo -e "  ${RED}[NOT FOUND]${NC} $file"
        elif ! file_is_modified "$file"; then
            echo -e "  ${YELLOW}[MODIFIED]${NC} $file"
        else
            echo -e "  ${GREEN}[CLEAN]${NC} $file"
        fi
    done
    echo ""

    # Check if patches would apply cleanly
    echo -e "${BLUE}Patch applicability (dry-run):${NC}"
    if [ -f "$KIMI_UI_PATCH" ]; then
        if git apply --check "$KIMI_UI_PATCH" 2>/dev/null; then
            echo -e "  ${GREEN}[OK]${NC} vibeproxy-kimi-ui.patch"
        else
            echo -e "  ${YELLOW}[CONFLICT]${NC} vibeproxy-kimi-ui.patch (may already be applied)"
        fi
    fi

    if [ -f "$SPARKLE_FEED_PATCH" ]; then
        if git apply --check "$SPARKLE_FEED_PATCH" 2>/dev/null; then
            echo -e "  ${GREEN}[OK]${NC} vibeproxy-sparkle-feed.patch"
        else
            echo -e "  ${YELLOW}[CONFLICT]${NC} vibeproxy-sparkle-feed.patch (may already be applied)"
        fi
    fi
}

# Generate patches from current changes
generate_patches() {
    echo -e "${BLUE}=== Generating Patches ===${NC}"
    echo ""

    mkdir -p "$PATCHES_DIR"
    mkdir -p "$ASSETS_DIR"

    # Generate Kimi UI patch (Swift files)
    echo -e "${BLUE}Generating vibeproxy-kimi-ui.patch...${NC}"
    KIMI_UI_FILES=(
        "src/Sources/AuthStatus.swift"
        "src/Sources/ServerManager.swift"
        "src/Sources/SettingsView.swift"
    )

    # Check if any Kimi UI files have changes
    has_kimi_changes=false
    for file in "${KIMI_UI_FILES[@]}"; do
        if ! file_is_modified "$file"; then
            has_kimi_changes=true
            break
        fi
    done

    if [ "$has_kimi_changes" = true ]; then
        git diff HEAD -- "${KIMI_UI_FILES[@]}" > "$KIMI_UI_PATCH"
        if [ -s "$KIMI_UI_PATCH" ]; then
            echo -e "  ${GREEN}Created${NC} vibeproxy-kimi-ui.patch"
        else
            rm -f "$KIMI_UI_PATCH"
            echo -e "  ${YELLOW}No changes${NC} in Kimi UI files"
        fi
    else
        echo -e "  ${YELLOW}No changes${NC} in Kimi UI files"
    fi

    # Generate Sparkle feed patch
    echo -e "${BLUE}Generating vibeproxy-sparkle-feed.patch...${NC}"
    SPARKLE_FEED_FILES=(
        "src/Info.plist"
    )

    # Check if any Sparkle feed files have changes
    has_sparkle_changes=false
    for file in "${SPARKLE_FEED_FILES[@]}"; do
        if ! file_is_modified "$file"; then
            has_sparkle_changes=true
            break
        fi
    done

    if [ "$has_sparkle_changes" = true ]; then
        git diff HEAD -- "${SPARKLE_FEED_FILES[@]}" > "$SPARKLE_FEED_PATCH"
        if [ -s "$SPARKLE_FEED_PATCH" ]; then
            echo -e "  ${GREEN}Created${NC} vibeproxy-sparkle-feed.patch"
        else
            rm -f "$SPARKLE_FEED_PATCH"
            echo -e "  ${YELLOW}No changes${NC} in Sparkle feed files"
        fi
    else
        echo -e "  ${YELLOW}No changes${NC} in Sparkle feed files"
    fi

    # Copy binary assets
    echo ""
    echo -e "${BLUE}Copying binary assets...${NC}"
    for asset in "${BINARY_ASSETS[@]}"; do
        src="${asset%%:*}"
        dest="${asset#*:}"
        if [ -f "$PROJECT_DIR/$dest" ]; then
            cp "$PROJECT_DIR/$dest" "$ASSETS_DIR/$src"
            echo -e "  ${GREEN}Copied${NC} $src"
        else
            echo -e "  ${YELLOW}Not found${NC} $dest"
        fi
    done

    echo ""
    echo -e "${GREEN}Patch generation complete!${NC}"
    echo ""
    echo "To commit patches:"
    echo "  git add patches/"
    echo "  git commit -m \"Update VibeProxy patches\""
}

# Apply patches to managed files
apply_patches() {
    echo -e "${BLUE}=== Applying VibeProxy Patches ===${NC}"
    echo ""

    # Check if patches exist
    if [ ! -f "$KIMI_UI_PATCH" ] && [ ! -f "$SPARKLE_FEED_PATCH" ]; then
        echo -e "${YELLOW}No patches found. Run './update.sh --generate' first.${NC}"
        exit 1
    fi

    # Determine the upstream reference to reset to
    # In CI, we have an 'upstream' remote; locally we use 'origin/main'
    if git remote | grep -q '^upstream$'; then
        UPSTREAM_REF="upstream/main"
    else
        UPSTREAM_REF="origin/main"
    fi

    # Reset managed files to upstream state
    echo -e "${BLUE}Resetting managed files to upstream state ($UPSTREAM_REF)...${NC}"
    for file in "${MANAGED_FILES[@]}"; do
        if [ -f "$PROJECT_DIR/$file" ]; then
            git checkout "$UPSTREAM_REF" -- "$file" 2>/dev/null || git checkout HEAD -- "$file" 2>/dev/null || true
            echo -e "  ${GREEN}Reset${NC} $file"
        fi
    done
    echo ""

    # Apply patches
    echo -e "${BLUE}Applying patches...${NC}"

    if [ -f "$KIMI_UI_PATCH" ]; then
        if git apply "$KIMI_UI_PATCH"; then
            echo -e "  ${GREEN}Applied${NC} vibeproxy-kimi-ui.patch"
        else
            echo -e "  ${RED}Failed${NC} vibeproxy-kimi-ui.patch"
            exit 1
        fi
    fi

    if [ -f "$SPARKLE_FEED_PATCH" ]; then
        if git apply "$SPARKLE_FEED_PATCH"; then
            echo -e "  ${GREEN}Applied${NC} vibeproxy-sparkle-feed.patch"
        else
            echo -e "  ${RED}Failed${NC} vibeproxy-sparkle-feed.patch"
            exit 1
        fi
    fi
    echo ""

    # Copy binary assets
    echo -e "${BLUE}Copying binary assets...${NC}"
    for asset in "${BINARY_ASSETS[@]}"; do
        src="${asset%%:*}"
        dest="${asset#*:}"
        if [ -f "$ASSETS_DIR/$src" ]; then
            mkdir -p "$(dirname "$PROJECT_DIR/$dest")"
            cp "$ASSETS_DIR/$src" "$PROJECT_DIR/$dest"
            echo -e "  ${GREEN}Copied${NC} $src -> $dest"
        else
            echo -e "  ${YELLOW}Not found${NC} $src in patches/assets/"
        fi
    done

    echo ""
    echo -e "${GREEN}Patches applied successfully!${NC}"
}

# Main
cd "$PROJECT_DIR"

case "${1:-}" in
    --help|-h)
        usage
        exit 0
        ;;
    --status)
        show_status
        ;;
    --generate)
        generate_patches
        ;;
    --apply|"")
        apply_patches
        ;;
    *)
        echo -e "${RED}Unknown option: $1${NC}"
        usage
        exit 1
        ;;
esac
