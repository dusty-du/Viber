#!/bin/bash
#
# CLIProxyAPIPlus Patcher
#
# Clones the CLIProxyAPIPlus repository and applies the Kimi support patch.
#
# Usage:
#   ./patch-cliproxy.sh                     Clone latest release and apply patch
#   ./patch-cliproxy.sh --tag v1.2.3        Clone a specific tag
#   ./patch-cliproxy.sh --dest ./my-dir     Clone into a custom directory
#   ./patch-cliproxy.sh --no-build           Clone and patch without building
#   ./patch-cliproxy.sh --status            Check if patch would apply cleanly

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PATCHES_DIR="$SCRIPT_DIR/patches"
PATCH_FILE="$PATCHES_DIR/cliproxyapiplus-kimi-support.patch"
REPO="router-for-me/CLIProxyAPIPlus"
REPO_URL="https://github.com/$REPO.git"
BINARY_DEST="$SCRIPT_DIR/src/Sources/Resources/cli-proxy-api-plus"

DEST_DIR=""
TAG=""
STATUS_ONLY=false
NO_BUILD=false

usage() {
    echo "Usage: $0 [options]"
    echo ""
    echo "Clones CLIProxyAPIPlus and applies the Kimi support patch."
    echo ""
    echo "Options:"
    echo "  --tag TAG      Clone a specific tag (default: latest release)"
    echo "  --dest DIR     Clone destination directory (default: cliproxy-src)"
    echo "  --no-build     Clone and patch only, skip building"
    echo "  --status       Only check if the patch exists and is valid"
    echo "  --help, -h     Show this help"
}

# Parse args
while [[ $# -gt 0 ]]; do
    case "$1" in
        --tag)
            TAG="$2"
            shift 2
            ;;
        --dest)
            DEST_DIR="$2"
            shift 2
            ;;
        --no-build)
            NO_BUILD=true
            shift
            ;;
        --status)
            STATUS_ONLY=true
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        *)
            echo -e "${RED}Unknown option: $1${NC}"
            usage
            exit 1
            ;;
    esac
done

# Defaults
DEST_DIR="${DEST_DIR:-$SCRIPT_DIR/cliproxy-src}"

# Status mode
if [ "$STATUS_ONLY" = true ]; then
    echo -e "${BLUE}=== CLIProxyAPIPlus Patch Status ===${NC}"
    echo ""
    if [ -f "$PATCH_FILE" ]; then
        echo -e "  ${GREEN}[EXISTS]${NC} cliproxyapiplus-kimi-support.patch"
    else
        echo -e "  ${RED}[MISSING]${NC} cliproxyapiplus-kimi-support.patch"
        exit 1
    fi
    if [ -d "$DEST_DIR/.git" ]; then
        echo -e "  ${GREEN}[CLONED]${NC} $DEST_DIR"
        cd "$DEST_DIR"
        if git apply --check "$PATCH_FILE" 2>/dev/null; then
            echo -e "  ${GREEN}[OK]${NC} Patch applies cleanly"
        else
            echo -e "  ${YELLOW}[CONFLICT]${NC} Patch may already be applied or has conflicts"
        fi
    else
        echo -e "  ${YELLOW}[NOT CLONED]${NC} $DEST_DIR"
    fi
    exit 0
fi

# Check patch file exists
if [ ! -f "$PATCH_FILE" ]; then
    echo -e "${RED}Patch file not found: $PATCH_FILE${NC}"
    exit 1
fi

# Resolve tag if not specified
if [ -z "$TAG" ]; then
    echo -e "${BLUE}Fetching latest release tag...${NC}"
    if command -v gh &>/dev/null; then
        TAG=$(gh release view --repo "$REPO" --json tagName -q '.tagName')
    else
        TAG=$(git ls-remote --tags --sort=-v:refname "$REPO_URL" | head -1 | sed 's|.*refs/tags/||')
    fi
    if [ -z "$TAG" ]; then
        echo -e "${RED}Could not determine latest release tag${NC}"
        exit 1
    fi
fi

echo -e "${BLUE}=== CLIProxyAPIPlus Patcher ===${NC}"
echo ""
echo -e "  Repository:  $REPO"
echo -e "  Tag:         $TAG"
echo -e "  Destination: $DEST_DIR"
echo ""

# Clone
if [ -d "$DEST_DIR/.git" ]; then
    echo -e "${YELLOW}Destination already exists, removing...${NC}"
    rm -rf "$DEST_DIR"
fi

echo -e "${BLUE}Cloning $REPO@$TAG...${NC}"
git clone --depth 1 --branch "$TAG" "$REPO_URL" "$DEST_DIR"
echo ""

# Apply patch
cd "$DEST_DIR"
echo -e "${BLUE}Applying Kimi support patch...${NC}"
if git apply "$PATCH_FILE"; then
    echo -e "  ${GREEN}Applied${NC} cliproxyapiplus-kimi-support.patch"
else
    echo -e "${YELLOW}Clean apply failed, trying 3-way merge...${NC}"
    if git apply --3way "$PATCH_FILE"; then
        echo -e "  ${GREEN}Applied${NC} cliproxyapiplus-kimi-support.patch (3-way merge)"
    else
        echo -e "  ${RED}Failed${NC} to apply patch"
        git status
        exit 1
    fi
fi

echo ""

# Build and install binary
if [ "$NO_BUILD" = true ]; then
    echo -e "${GREEN}Done! Patched source is in: $DEST_DIR${NC}"
    exit 0
fi

# Check Go is available
if ! command -v go &>/dev/null; then
    echo -e "${RED}Go is not installed. Install it or use --no-build to skip compilation.${NC}"
    exit 1
fi

echo -e "${BLUE}Building cli-proxy-api-plus (darwin/arm64)...${NC}"
export GOOS=darwin
export GOARCH=arm64
export CGO_ENABLED=0

go build -ldflags="-s -w" -o cli-proxy-api-plus ./cmd/server
echo -e "  ${GREEN}Built${NC} cli-proxy-api-plus ($(du -h cli-proxy-api-plus | cut -f1))"

echo -e "${BLUE}Installing binary to resources...${NC}"
cp cli-proxy-api-plus "$BINARY_DEST"
chmod +x "$BINARY_DEST"
echo -e "  ${GREEN}Copied${NC} -> $BINARY_DEST"

echo ""
echo -e "${GREEN}Done! Binary installed to src/Sources/Resources/cli-proxy-api-plus${NC}"
