#!/bin/bash
# Capture TM Agent UI screenshot using tm-control-mcp TakeScreenshot tool
# Usage: ./capture_ui.sh

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MCP_DIR="$(dirname "$SCRIPT_DIR")/tm-control-mcp"

echo "Taking screenshot..."
RESULT="$("$MCP_DIR/tools/call.py" TakeScreenshot '{"format":"png"}' 2>&1)"

if echo "$RESULT" | grep -q '"ok"'; then
    LINUX_PATH=$(echo "$RESULT" | python3 -c "import sys,json; d=json.load(sys.stdin); print(d.get('data',{}).get('result',{}).get('output',{}).get('detectedScreenshot',{}).get('linuxPath',''))" 2>/dev/null)
    if [ -n "$LINUX_PATH" ] && [ -f "$LINUX_PATH" ]; then
        echo "Screenshot found at: $LINUX_PATH"
        cp "$LINUX_PATH" /tmp/tm_agent_ui.png
        echo "Copied to /tmp/tm_agent_ui.png"
        echo "PATH=/tmp/tm_agent_ui.png"
    else
        echo "Could not find screenshot file"
        echo "$RESULT"
    fi
else
    echo "Screenshot failed"
    echo "$RESULT"
fi
