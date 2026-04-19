#!/bin/bash
# Analyze TM Agent UI screenshot using ccc with gemini
# Usage: ./analyze_ui.sh

SCREENSHOT="/tmp/tm_agent_ui.png"

if [ ! -f "$SCREENSHOT" ]; then
    echo "Screenshot not found at $SCREENSHOT"
    exit 1
fi

PROMPT="Look at the screenshot at $SCREENSHOT. This is the Trackmania editor with a TM Agent plugin window.

Describe in detail:
1. The TM Agent window layout and visual design
2. The stats display - what progress bars, numbers, colors do you see?
3. The message/chat area
4. What looks good and what could be improved?
5. Create an ASCII art mockup of the TM Agent window showing its structure

Save your detailed analysis to /tmp/tm_agent_analysis.txt"

echo "Analyzing screenshot with gemini (4 min timeout)..."
ccc gemini "$PROMPT" 2>&1

echo ""
echo "Done. Check /tmp/tm_agent_analysis.txt for results."
