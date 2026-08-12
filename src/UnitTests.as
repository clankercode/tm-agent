#if UNITTEST
namespace AgentUnitTests {
    void Assert(bool condition, const string &in message) {
        if (!condition) {
            throw("Assert failed: " + message);
        }
    }

    string RepeatText(const string &in text, int count) {
        string result = "";
        for (int i = 0; i < count; i++) {
            result += text;
        }
        return result;
    }

    void Test_OpenAISettings_AreExpected() {
        Assert(int(Provider::OpenAI) == 1, "OpenAI enum value should stay stable");
        Assert(AgentSettings::S_OpenAIModel == "gpt-5.4-mini", "default OpenAI model should match");
        Assert(AgentSettings::S_OpenAIReasoningEffort == "high", "default OpenAI effort should be high");
    }

    void Test_ProviderEnum_AssignsCleanly() {
        Provider previous = AgentSettings::S_Provider;
        AgentSettings::S_Provider = Provider::OpenAI;
        Assert(AgentSettings::S_Provider == Provider::OpenAI, "provider should switch to OpenAI");
        AgentSettings::S_Provider = previous;
    }

    void Test_SystemPrompt_TracksToolList() {
        Json::Value@ tools = ToolAssembler::GetToolList();
        string toolJson = Json::Write(tools);
        string prompt = LlmHistory::BuildSystemPrompt(tools);
        Assert(tools.Length > 0, "tool list should not be empty");
        Assert(toolJson.Contains("GetCursor"), "assembled tool list should mention GetCursor");
        Assert(toolJson.Contains("GetServerInfo"), "assembled tool list should mention GetServerInfo");
        Assert(prompt.Contains(toolJson), "system prompt should embed the serialized tool list");
        Assert(prompt.Contains("TOOLS:"), "system prompt should contain a tool catalog");
    }

    void Test_InventoryTools_ArePresent() {
        Json::Value@ tools = ToolAssembler::GetToolList();
        string toolJson = Json::Write(tools);
        Assert(toolJson.Contains("GetInventorySummary"), "inventory summary tool should be registered");
        Assert(toolJson.Contains("SearchInventory"), "inventory search tool should be registered");
    }

    void Test_ContextStats_GrowWithMessages() {
        LlmHistory::ClearHistory();
        Json::Value@ tools = ToolAssembler::GetToolList();

        Json::Value@ emptyStats = LlmHistory::BuildContextStats(tools, AgentSettings::S_MaxHistoryTokens);
        LlmHistory::AddUserMessage(RepeatText("history growth ", 40));
        LlmHistory::AddAssistantMessage(RepeatText("assistant growth ", 20));
        Json::Value@ grownStats = LlmHistory::BuildContextStats(tools, AgentSettings::S_MaxHistoryTokens);

        Assert(int(grownStats["historyTokens"]) > int(emptyStats["historyTokens"]), "history token estimate should grow with messages");
        Assert(int(grownStats["estimatedTotalTokens"]) > int(emptyStats["estimatedTotalTokens"]), "total token estimate should grow with messages");
        Assert(int(grownStats["toolSchemaTokens"]) > 0, "tool schema should contribute tokens");
    }

    void Test_Compaction_PreservesToolPair() {
        LlmHistory::ClearHistory();
        Json::Value@ tools = ToolAssembler::GetToolList();

        LlmHistory::AddUserMessage(RepeatText("very old context ", 6000));
        LlmHistory::AddAssistantMessage(RepeatText("very old assistant response ", 500));
        LlmHistory::AddUserMessage("middle turn");

        Json::Value@ toolCall = Json::Object();
        toolCall["name"] = "GetCursor";
        toolCall["input"] = Json::Object();
        toolCall["id"] = "call_1";
        array<Json::Value@> toolCalls;
        toolCalls.Resize(1);
        @toolCalls[0] = toolCall;

        LlmHistory::AddAssistantToolCalls("calling a tool", toolCalls);
        LlmHistory::AddToolResult("call_1", "GetCursor", '{"success":true,"output":{"coord":[1,2,3]}}');
        LlmHistory::AddUserMessage("latest turn");

        LlmHistory::CompactHistory(tools, 25000);

        Assert(LlmHistory::g_CompactedSummary.Length > 0, "compaction summary should be populated");
        Assert(LlmHistory::g_Messages.Length > 0, "history should still contain recent turns");

        bool sawToolCall = false;
        bool sawToolResult = false;
        uint toolCallIndex = 999999;
        uint toolResultIndex = 999999;
        for (uint i = 0; i < LlmHistory::g_Messages.Length; i++) {
            Json::Value@ msg = LlmHistory::g_Messages[i];
            if (msg.HasKey("tool_calls")) {
                sawToolCall = true;
                if (toolCallIndex == 999999) toolCallIndex = i;
            }
            if (msg.HasKey("tool_result")) {
                sawToolResult = true;
                if (toolResultIndex == 999999) toolResultIndex = i;
            }
        }

        Assert(sawToolCall, "tool call should survive compaction");
        Assert(sawToolResult, "tool result should survive compaction");
        Assert(toolCallIndex < toolResultIndex, "tool call should stay before tool result");
        Assert(string(LlmHistory::g_Messages[LlmHistory::g_Messages.Length - 1]["content"]) == "latest turn", "latest turn should remain at the end");
    }

    void RegisterAll() {
        RegisterUnitTest("openai defaults stay expected", Test_OpenAISettings_AreExpected);
        RegisterUnitTest("provider enum assigns cleanly", Test_ProviderEnum_AssignsCleanly);
        RegisterUnitTest("system prompt tracks tool list", Test_SystemPrompt_TracksToolList);
        RegisterUnitTest("inventory tools are present", Test_InventoryTools_ArePresent);
        RegisterUnitTest("context stats grow with messages", Test_ContextStats_GrowWithMessages);
        RegisterUnitTest("compaction preserves tool pair", Test_Compaction_PreservesToolPair);
    }

    bool unitTestsRegistered = runAsync(RegisterAll);
}
#endif
