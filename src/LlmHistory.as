namespace LlmHistory {
    array<Json::Value@> g_Messages;
    string g_CompactedSummary = "";
    uint g_LastCompactionAt = 0;
    int g_CompactionCount = 0;

    const string BASE_SYSTEM_PROMPT =
        "You are an expert Trackmania map editor agent. You have access to tools to view and modify the current map.\n\n"
        + "IMPORTANT:\n"
        + "- Coordinates are in block units. 1 block = 32 units horizontally, 8 units vertically\n"
        + "- Use GetBlocks() to explore the map before making changes\n"
        + "- After TestMap(), use GetRaceData() to see results\n"
        + "- Be precise with coordinates\n"
        + "- Always query the current editor state before guessing: call GetMapInfo, GetCursor, GetPlacementMode, and GetInventorySummary early in a session\n"
        + "- When searching for blocks, items, or macroblocks, prefer SearchInventory with appropriate queries over guessing names";

    string TrimForSummary(const string &in text, uint maxLen = 180) {
        if (uint(text.Length) <= maxLen) return text;
        if (maxLen <= 3) return text.SubStr(0, maxLen);
        return text.SubStr(0, maxLen - 3) + "...";
    }

    string JoinStrings(const array<string> &in items, const string &in separator) {
        string joined = "";
        for (uint i = 0; i < items.Length; i++) {
            if (i > 0) joined += separator;
            joined += items[i];
        }
        return joined;
    }

    string BuildToolCatalog(Json::Value@ tools) {
        if (tools is null || tools.GetType() != Json::Type::Array || tools.Length == 0) {
            return "TOOLS:\n- None available.";
        }

        return "TOOLS:\n" + Json::Write(tools);
    }

    string BuildSystemPrompt(Json::Value@ tools) {
        return BASE_SYSTEM_PROMPT + "\n\n" + BuildToolCatalog(tools);
    }

    string GetSystemPrompt() {
        return BuildSystemPrompt(null);
    }

    void AddUserMessage(const string &in content) {
        g_Messages.InsertLast(AiApi::NewMessage("user", content));
    }

    void AddAssistantMessage(const string &in content) {
        g_Messages.InsertLast(AiApi::NewMessage("assistant", content));
    }

    void AddAssistantToolCalls(const string &in content, const array<Json::Value@> &in toolCalls) {
        Json::Value msg = Json::Object();
        msg["role"] = "assistant";
        msg["content"] = content;
        Json::Value calls = Json::Array();
        for (uint i = 0; i < toolCalls.Length; i++) {
            calls.Add(toolCalls[i]);
        }
        msg["tool_calls"] = calls;
        g_Messages.InsertLast(msg);
    }

    void AddToolResult(const string &in toolCallId, const string &in toolName, const string &in resultJson) {
        Json::Value msg = Json::Object();
        msg["role"] = "user";
        msg["content"] = resultJson;
        msg["tool_call_id"] = toolCallId;
        msg["tool_name"] = toolName;
        Json::Value toolResult = Json::Object();
        toolResult["name"] = toolName;
        toolResult["result"] = Json::Parse(resultJson);
        msg["tool_result"] = toolResult;
        g_Messages.InsertLast(msg);
    }

    void ClearHistory() {
        g_Messages.RemoveRange(0, g_Messages.Length);
        g_CompactedSummary = "";
        g_LastCompactionAt = 0;
        g_CompactionCount = 0;
    }

    int CountMessageTokens(const Json::Value@ msg) {
        if (msg is null) return 0;
        return AiApi::CountTokens(Json::Write(msg));
    }

    int CountHistoryTokens() {
        int total = 0;
        for (uint i = 0; i < g_Messages.Length; i++) {
            total += CountMessageTokens(g_Messages[i]);
        }
        return total;
    }

    int CountSummaryTokens() {
        return AiApi::CountTokens(g_CompactedSummary);
    }

    int CountSystemPromptTokens(Json::Value@ tools) {
        return AiApi::CountTokens(BuildSystemPrompt(tools));
    }

    int CountToolSchemaTokens(Json::Value@ tools) {
        if (tools is null) return 0;
        return AiApi::CountTokens(Json::Write(tools));
    }

    int CountAllTokens() {
        return CountSystemPromptTokens(null) + CountSummaryTokens() + CountHistoryTokens();
    }

    array<uint> GetTurnStartIndices() {
        array<uint> turnStarts;
        for (uint i = 0; i < g_Messages.Length; i++) {
            Json::Value@ msg = g_Messages[i];
            if (msg !is null && msg.HasKey("role") && string(msg["role"]) == "user" && !msg.HasKey("tool_result")) {
                turnStarts.InsertLast(i);
            }
        }
        return turnStarts;
    }

    string DescribeToolCalls(const Json::Value@ msg) {
        array<string> names;
        const Json::Value@ toolCalls = msg["tool_calls"];
        if (toolCalls !is null && toolCalls.GetType() == Json::Type::Array) {
            for (uint i = 0; i < toolCalls.Length; i++) {
                const Json::Value@ toolCall = toolCalls[i];
                if (toolCall is null) continue;
                names.InsertLast(toolCall.HasKey("name") ? string(toolCall["name"]) : "unknown");
            }
        }
        string content = msg.HasKey("content") ? string(msg["content"]) : "";
        string summary = "assistant tool_calls=" + JoinStrings(names, ", ");
        if (content.Length > 0) {
            summary += " content=" + TrimForSummary(content, 120);
        }
        return summary;
    }

    string DescribeToolResult(const Json::Value@ msg) {
        string toolName = msg.HasKey("tool_name") ? string(msg["tool_name"]) : "";
        string toolCallId = msg.HasKey("tool_call_id") ? string(msg["tool_call_id"]) : "";
        string resultText = msg.HasKey("content") ? string(msg["content"]) : "";
        if (resultText.Length == 0 && msg.HasKey("tool_result")) {
            resultText = Json::Write(msg["tool_result"]);
        }
        return "tool result " + toolName + (toolCallId.Length > 0 ? " (" + toolCallId + ")" : "") + ": " + TrimForSummary(resultText, 120);
    }

    string DescribeMessage(const Json::Value@ msg) {
        if (msg is null) return "null";

        string role = msg.HasKey("role") ? string(msg["role"]) : "unknown";
        if (msg.HasKey("tool_calls")) {
            return DescribeToolCalls(msg);
        }
        if (msg.HasKey("tool_result")) {
            return DescribeToolResult(msg);
        }

        string content = msg.HasKey("content") ? string(msg["content"]) : "";
        return role + ": " + TrimForSummary(content, 120);
    }

    string BuildCompactionChunk(uint startIx, uint endIx) {
        if (endIx <= startIx) return "";

        string chunk = "Compacted context from earlier turns (" + ("" + (endIx - startIx)) + " messages):\n";
        for (uint i = startIx; i < endIx; i++) {
            chunk += "- " + DescribeMessage(g_Messages[i]) + "\n";
        }
        return chunk.Trim();
    }

    Json::Value@ BuildContextStats(Json::Value@ tools, int maxTokens) {
        Json::Value stats = Json::Object();
        int systemPromptTokens = CountSystemPromptTokens(tools);
        int summaryTokens = CountSummaryTokens();
        int historyTokens = CountHistoryTokens();
        int toolSchemaTokens = CountToolSchemaTokens(tools);
        int estimatedTotalTokens = systemPromptTokens + summaryTokens + historyTokens + toolSchemaTokens;

        stats["systemPromptTokens"] = systemPromptTokens;
        stats["summaryTokens"] = summaryTokens;
        stats["historyTokens"] = historyTokens;
        stats["toolSchemaTokens"] = toolSchemaTokens;
        stats["estimatedTotalTokens"] = estimatedTotalTokens;
        int remainingBudgetTokens = maxTokens - estimatedTotalTokens;
        if (remainingBudgetTokens < 0) {
            remainingBudgetTokens = 0;
        }
        stats["remainingBudgetTokens"] = maxTokens > 0 ? remainingBudgetTokens : 0;
        stats["messageCount"] = int(g_Messages.Length);
        stats["hasCompactedHistory"] = g_CompactedSummary.Length > 0;
        stats["lastCompactionAt"] = g_LastCompactionAt;
        stats["compactionCount"] = g_CompactionCount;
        stats["maxTokens"] = maxTokens;
        return stats;
    }

    void CompactHistory(Json::Value@ tools, int maxTokens) {
        if (maxTokens <= 0) return;

        int keepTurns = 2;
        while (keepTurns > 0) {
            Json::Value@ stats = BuildContextStats(tools, maxTokens);
            if (int(stats["estimatedTotalTokens"]) <= maxTokens) {
                return;
            }

            array<uint> turnStarts = GetTurnStartIndices();
            if (turnStarts.Length <= uint(keepTurns)) {
                return;
            }

            uint keepStart = turnStarts[turnStarts.Length - keepTurns];
            if (keepStart == 0) {
                return;
            }

            string chunk = BuildCompactionChunk(0, keepStart);
            if (chunk.Length == 0) {
                return;
            }

            if (g_CompactedSummary.Length > 0) {
                g_CompactedSummary += "\n\n";
            }
            g_CompactedSummary += "Compaction #" + (g_CompactionCount + 1) + " at " + ("" + Time::Now) + "\n" + chunk;
            g_Messages.RemoveRange(0, keepStart);
            g_LastCompactionAt = Time::Now;
            g_CompactionCount++;
            keepTurns--;
        }
    }

    void TruncateHistory(int maxTokens) {
        CompactHistory(null, maxTokens);
    }

    Json::Value@ GetMessagesForLlm(Json::Value@ tools) {
        Json::Value msgs = Json::Array();

        Json::Value system = Json::Object();
        system["role"] = "system";
        system["content"] = BuildSystemPrompt(tools);
        msgs.Add(system);

        string editorState = ToolAssembler::GetEditorStateSnapshot();
        if (editorState.Length > 0) {
            Json::Value editorMsg = Json::Object();
            editorMsg["role"] = "system";
            editorMsg["content"] = editorState;
            msgs.Add(editorMsg);
        }

        if (g_CompactedSummary.Length > 0) {
            Json::Value summary = Json::Object();
            summary["role"] = "system";
            summary["content"] = "Compacted prior context:\n" + g_CompactedSummary;
            msgs.Add(summary);
        }

        for (uint i = 0; i < g_Messages.Length; i++) {
            msgs.Add(g_Messages[i]);
        }

        return msgs;
    }
}
