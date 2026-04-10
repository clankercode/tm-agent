namespace LlmHistory {
    array<Json::Value@> g_Messages;

    const string SYSTEM_PROMPT = 
        "You are an expert Trackmania map editor agent. You have access to tools to view and modify the current map.\n\n"
        + "TOOLS:\n"
        + "- GetCursor(): Get current cursor position, direction, and picked block/item\n"
        + "- GetMapInfo(): Get map name and object counts\n"
        + "- GetBlocks(x, y, z, radius, filter): List blocks near a point. filter=\"all\"|\"classic\"|\"ghost\"|\"terrain\"\n"
        + "- GetItems(x, y, z, radius): List items near a point\n"
        + "- GetBlockAt(x, y, z): Get block info at exact coordinate\n"
        + "- GetPickedBlock(): Get the cursor's currently selected block\n"
        + "- GetPlacementMode(): Get current placement mode\n"
        + "- GetRaceData(): Get race information (players, times, checkpoints)\n"
        + "- GetPlayers(): Get list of players with CP info\n"
        + "- GetMode(): Get current game mode (Editor/Race/Spectator/Menu)\n"
        + "- GetServerInfo(): Get server name and player count\n"
        + "- PlaceBlock(blockName, x, y, z, dir): Place a block. dir=\"North\"|\"East\"|\"South\"|\"West\"\n"
        + "- RemoveBlock(x, y, z): Remove a block at coordinate\n"
        + "- Undo(): Undo last action\n"
        + "- Redo(): Redo last undone action\n"
        + "- TestMap(modeName): Test the map. modeName e.g. \"TM_Race\" or \"\" for default\n"
        + "- SaveMap(fileName): Save the map to a file\n"
        + "- SetCursorBlock(blockName): Set the cursor's selected block\n"
        + "- SetCursorItem(itemName): Set the cursor's selected item\n\n"
        + "IMPORTANT:\n"
        + "- Coordinates are in block units. 1 block = 32 units horizontally, 8 units vertically\n"
        + "- Use GetBlocks() to explore the map before making changes\n"
        + "- After TestMap(), use GetRaceData() to see results\n"
        + "- Be precise with coordinates";

    void AddUserMessage(const string &in content) {
        Json::Value msg = Json::Object();
        msg["role"] = "user";
        msg["content"] = content;
        g_Messages.InsertLast(msg);
    }

    void AddAssistantMessage(const string &in content) {
        Json::Value msg = Json::Object();
        msg["role"] = "assistant";
        msg["content"] = content;
        g_Messages.InsertLast(msg);
    }

    void AddToolResult(const string &in toolCallId, const string &in toolName, const string &in resultJson) {
        Json::Value msg = Json::Object();
        msg["role"] = "user";
        msg["content"] = "";
        Json::Value toolResult = Json::Object();
        toolResult[toolName] = Json::Parse(resultJson);
        msg["tool_result"] = toolResult;
        g_Messages.InsertLast(msg);
    }

    void ClearHistory() {
        g_Messages.RemoveRange(0, g_Messages.Length);
    }

    int CountMessageTokens(const Json::Value &in msg) {
        string s = msg.HasKey("content") ? string(msg["content"]) : "";
        return (s.Length + 3) / 4;
    }

    int CountAllTokens() {
        int total = 0;
        total += (SYSTEM_PROMPT.Length + 3) / 4;
        for (uint i = 0; i < g_Messages.Length; i++) {
            total += CountMessageTokens(g_Messages[i]);
        }
        return total;
    }

    void TruncateHistory(int maxTokens) {
        while (g_Messages.Length > 20 && CountAllTokens() > maxTokens) {
            g_Messages.RemoveAt(0);
        }
    }

    Json::Value@ GetMessagesForLlm(const Json::Value &in tools) {
        Json::Value msgs = Json::Array();

        Json::Value system = Json::Object();
        system["role"] = "system";
        system["content"] = SYSTEM_PROMPT;
        msgs.Add(system);

        for (uint i = 0; i < g_Messages.Length; i++) {
            msgs.Add(g_Messages[i]);
        }

        return msgs;
    }

    const string& GetSystemPrompt() {
        return SYSTEM_PROMPT;
    }
}
