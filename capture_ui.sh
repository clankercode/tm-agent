#!/bin/bash
# Capture TM Agent UI screenshot using xdotool + ImageMagick
# Usage: ./capture_ui.sh

OUTPUT="/tmp/tm_agent_ui.png"

# Find window with exact name "Trackmania" (not CodeBrowser/Ghidra)
WID=$(xdotool search --name "Trackmania" 2>&1 | while read wid; do
  name=$(xdotool getwindowname "$wid" 2>/dev/null)
  if [ "$name" = "Trackmania" ]; then
    echo "$wid"
    break
  fi
done)

if [ -z "$WID" ]; then
    echo "Error: Trackmania window not found"
    exit 1
fi

import -window "$WID" "$OUTPUT" 2>&1
if [ ! -f "$OUTPUT" ]; then
    echo "Screenshot failed"
    exit 1
fi

# Crop to the pinned window region (set by ChatUI::Render)
# g_WindowPos = (120, 120), g_WindowSize = (440, 620), plus titlebar padding.
CROPPED="/tmp/tm_agent_ui_crop.png"
mogrify -crop 460x640+110+110 -path /tmp -format png -write "$CROPPED" "$OUTPUT" 2>/dev/null || \
  convert "$OUTPUT" -crop 460x640+110+110 +repage "$CROPPED"

echo "PATH=$OUTPUT"
echo "CROP=$CROPPED"
