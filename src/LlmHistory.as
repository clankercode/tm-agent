namespace LlmHistory {
    array<Json::Value@> g_Messages;

    const string SYSTEM_PROMPT = "You are an expert Trackmania map editor agent. "
        + "You can use tools to view and modify the current map. "
        + "When you test a map, wait for test results before continuing. "
        + "Be precise with block coordinates.";

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
        while (g_Messages.Length > 1 && CountAllTokens() > maxTokens) {
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
