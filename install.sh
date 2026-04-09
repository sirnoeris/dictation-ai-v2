#!/bin/bash
# install.sh — copies the latest Xcode debug build to /Applications and relaunches.
# Run this after each Xcode build to keep /Applications up to date.
# Permissions (Microphone, Accessibility) granted once to /Applications/DictationAI.app
# persist across every reinstall — no more re-granting after each rebuild.

set -euo pipefail

APP_NAME="DictationAI.app"
DEST="/Applications/$APP_NAME"

# Find the most recently modified debug build
SRC=$(find ~/Library/Developer/Xcode/DerivedData -name "$APP_NAME" \
        -path "*/Debug/*" 2>/dev/null \
      | xargs ls -dt 2>/dev/null \
      | head -1)

if [ -z "$SRC" ]; then
  echo "❌  Could not find a Debug build of $APP_NAME in DerivedData."
  echo "   Build the project in Xcode first (⌘B), then run this script."
  exit 1
fi

echo "📦  Source:      $SRC"
echo "🎯  Destination: $DEST"

# Stop any running instance
if pgrep -x DictationAI > /dev/null; then
  echo "⏹   Stopping running DictationAI…"
  pkill -x DictationAI
  sleep 0.8
fi

# Copy (overwrite)
echo "📋  Copying…"
rm -rf "$DEST"
cp -r "$SRC" "$DEST"

echo "✅  Installed to $DEST"
echo ""
echo "🚀  Launching from /Applications…"
echo "   (First launch: if Gatekeeper blocks it, right-click → Open)"
open "$DEST"
