#!/usr/bin/env bash
# ─────────────────────────────────────────────────────────────────────────────
#  Dictation AI v2 — Setup Script
#  Generates the Xcode project from project.yml, resolves Swift packages,
#  and optionally opens Xcode.
# ─────────────────────────────────────────────────────────────────────────────
set -euo pipefail

CYAN='\033[0;36m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; NC='\033[0m'

echo -e "${CYAN}Dictation AI v2 — Setup${NC}"
echo "────────────────────────"

# ── 1. Check Xcode command-line tools ─────────────────────────────────────────
if ! command -v xcodebuild &> /dev/null; then
    echo -e "${YELLOW}⚠ Xcode command-line tools not found.${NC}"
    echo "Install with: xcode-select --install"
    exit 1
fi
echo -e "${GREEN}✓${NC} Xcode: $(xcodebuild -version | head -1)"

# ── 2. Install / check XcodeGen ───────────────────────────────────────────────
if ! command -v xcodegen &> /dev/null; then
    echo ""
    echo "XcodeGen is required. Install it with Homebrew:"
    echo "  brew install xcodegen"
    echo ""
    read -p "Install now via Homebrew? [y/N] " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        brew install xcodegen
    else
        echo "Skipping XcodeGen install. Run 'brew install xcodegen' then re-run setup.sh"
        exit 1
    fi
fi
echo -e "${GREEN}✓${NC} XcodeGen: $(xcodegen --version 2>/dev/null || echo 'installed')"

# ── 3. Generate Xcode project ─────────────────────────────────────────────────
echo ""
echo "Generating DictationAI.xcodeproj…"
xcodegen generate
echo -e "${GREEN}✓${NC} DictationAI.xcodeproj generated"

# ── 4. Resolve Swift Package dependencies ────────────────────────────────────
echo ""
echo "Resolving Swift Package dependencies (WhisperKit)…"
xcodebuild -resolvePackageDependencies -project DictationAI.xcodeproj 2>&1 | tail -5
echo -e "${GREEN}✓${NC} Packages resolved"

# ── 5. Print next steps ───────────────────────────────────────────────────────
echo ""
echo -e "${CYAN}All done!${NC} Next steps:"
echo ""
echo "  1. Open DictationAI.xcodeproj in Xcode:"
echo "       open DictationAI.xcodeproj"
echo ""
echo "  2. In Xcode → Signing & Capabilities:"
echo "       • Set your Team (Apple ID)"
echo "       • Bundle ID: com.sirnoeris.DictationAI (or change to yours)"
echo ""
echo "  3. Build & Run  (⌘R)"
echo ""
echo "  4. On first launch, grant Accessibility in:"
echo "       System Settings → Privacy & Security → Accessibility"
echo ""
echo "  5. Set Fn/Globe key: System Settings → Keyboard → Press Globe key to → Do Nothing"
echo ""
echo "  6. Enter your xAI API key in Settings (click the mic icon in menu bar)"
echo ""
echo -e "${YELLOW}Globe key tip:${NC} Set it to 'Do Nothing' or the app won't see it."
echo ""
