const int STATE_IDLE = 0;
const int STATE_AWAITING_LLM = 1;
const int STATE_TOOL_CALLS_PENDING = 2;
const int STATE_EXECUTING_TOOLS = 3;

int g_State = STATE_IDLE;
array<Json::Value@> g_PendingToolCalls;

void SendMessage(const string &in content) {
    if (g_State != STATE_IDLE) {
        return;
    }
    LlmHistory::AddUserMessage(content);
    g_State = STATE_AWAITING_LLM;
    AgentUI::SetStatus("Calling LLM...");
    startnew(AgentLoopCoroutine, content);
}

// Minimal provider ping used by the "Test Provider" button in Settings.
// Lives next to AgentLoopCoroutine because the AiApi::* cross-plugin
// imports only bind correctly when invoked from this file.
void ProviderTestCoro() {
    uint tStart = Time::Now;
    Provider provider = AgentSettings::S_Provider;
    string provLabel = (provider == Provider::MiniMax) ? "minimax" : "openai";
    string apiKey;
    string model;
    if (provider == Provider::MiniMax) {
        apiKey = AgentSettings::S_MiniMaxApiKey;
        model = AgentSettings::S_MiniMaxModel;
    } else {
        apiKey = AgentSettings::S_OpenAIApiKey;
        model = AgentSettings::S_OpenAIModel;
    }

    print("[tm-agent] test: provider=" + provLabel + " model=" + model + " keyLen=" + apiKey.Length);

    if (apiKey.Length == 0) {
        AgentUI::g_TestResult = "No API key set";
        AgentUI::g_TestColor = vec4(0.96, 0.32, 0.30, 1.0);
        AgentUI::g_TestRunning = false;
        return;
    }

    Json::Value@ msgs = Json::Array();
    msgs.Add(AiApi::NewMessage("user", "ping"));
    Json::Value@ tools = Json::Array();

    print("[tm-agent] test: calling " + provLabel + " Complete()...");
    AgentUI::g_TestResult = "Calling " + provLabel + "…";
    Json::Value@ resp;
    if (provider == Provider::MiniMax) {
        @resp = AiApi::Anthropic_Complete(apiKey, model, msgs, tools);
    } else {
        // Use the configured effort so "Test Provider" validates the
        // actual config you use in real turns, not a hardcoded placeholder.
        array<string> responsesPrefixes = {"gpt-5"};
        AiApi::ILlmProvider@ oai = AiApi::NewOpenAIProvider(apiKey, responsesPrefixes);
        @resp = oai.Complete(model, AgentSettings::S_OpenAIReasoningEffort, msgs, tools);
    }
    uint elapsed = Time::Now - tStart;
    print("[tm-agent] test: returned after " + elapsed + "ms");

    if (resp is null) {
        print("[tm-agent] test: resp is null");
        AgentUI::g_TestResult = "No response";
        AgentUI::g_TestColor = vec4(0.96, 0.32, 0.30, 1.0);
    } else if (resp.HasKey("error") && resp["error"].GetType() != Json::Type::Null) {
        string err = string(resp["error"]);
        print("[tm-agent] test: error=" + err);
        string shown = err;
        if (shown.Length > 48) shown = shown.SubStr(0, 45) + "…";
        AgentUI::g_TestResult = shown;
        AgentUI::g_TestColor = vec4(0.96, 0.32, 0.30, 1.0);
    } else {
        string respSummary = Json::Write(resp);
        if (respSummary.Length > 200) respSummary = respSummary.SubStr(0, 200) + "…";
        print("[tm-agent] test: ok; resp=" + respSummary);
        AgentUI::g_TestResult = "OK  " + model + "  (" + elapsed + "ms)";
        AgentUI::g_TestColor = vec4(0.32, 0.86, 0.45, 1.0);
    }
    AgentUI::g_TestRunning = false;
}

void AgentLoopCoroutine(const string &in userContent) {
    Json::Value@ tools = ToolAssembler::GetToolList();
    LlmHistory::CompactHistory(tools, AgentSettings::S_MaxHistoryTokens);
    Json::Value@ messages = LlmHistory::GetMessagesForLlm(tools);

    Provider provider = AgentSettings::S_Provider;
    string apiKey;
    string model;

    if (provider == Provider::MiniMax && AgentSettings::S_MiniMaxApiKey.Length > 0) {
        apiKey = AgentSettings::S_MiniMaxApiKey;
        model = AgentSettings::S_MiniMaxModel;
    } else if (provider == Provider::OpenAI && AgentSettings::S_OpenAIApiKey.Length > 0) {
        apiKey = AgentSettings::S_OpenAIApiKey;
        model = AgentSettings::S_OpenAIModel;
    } else {
        AgentUI::SetStatus("Error: No valid API key configured");
        AgentUI::AddMessage(AgentUI::MsgType::Assistant, "Error: No valid API key configured. Please check your settings.");
        g_State = STATE_IDLE;
        return;
    }

    Json::Value@ resp;
    if (provider == Provider::MiniMax) {
        @resp = AiApi::Anthropic_Complete(apiKey, model, messages, ToolAssembler::GetToolList());
    } else {
        array<string> responsesPrefixes = {"gpt-5"};
        AiApi::ILlmProvider@ oai = AiApi::NewOpenAIProvider(apiKey, responsesPrefixes);
        @resp = oai.Complete(
            model,
            AgentSettings::S_OpenAIReasoningEffort,
            messages,
            ToolAssembler::GetToolList()
        );
    }

    if (resp.HasKey("error") && resp["error"].GetType() != Json::Type::Null) {
        string errorMsg = string(resp["error"]);
        AgentUI::SetStatus("Error: " + errorMsg);
        AgentUI::AddMessage(AgentUI::MsgType::Assistant, "Error: " + errorMsg);
        g_State = STATE_IDLE;
        return;
    }

    if (resp.HasKey("usage") && resp["usage"].GetType() == Json::Type::Object) {
        Json::Value@ usage = resp["usage"];
        int inToks = usage.HasKey("input_tokens") ? int(usage["input_tokens"]) : 0;
        int outToks = usage.HasKey("output_tokens") ? int(usage["output_tokens"]) : 0;
        int totToks = usage.HasKey("total_tokens") ? int(usage["total_tokens"]) : 0;
        AgentUI::UpdateTokenStats(inToks, outToks, totToks);
    }

    string text = "";
    if (resp.HasKey("text") && resp["text"].GetType() != Json::Type::Null) {
        text = string(resp["text"]);
    }

    auto parsedToolCalls = ToolAssembler::ParseToolCalls(resp);
    if (parsedToolCalls.Length > 0) {
        LlmHistory::AddAssistantToolCalls(text, parsedToolCalls);
        AgentUI::AddMessage(AgentUI::MsgType::Assistant, text);
        AgentUI::IncrementStep();
        g_PendingToolCalls = parsedToolCalls;
        g_State = STATE_TOOL_CALLS_PENDING;
        ProcessToolCalls();
    } else {
        LlmHistory::AddAssistantMessage(text);
        AgentUI::AddMessage(AgentUI::MsgType::Assistant, text);
        AgentUI::IncrementStep();
        g_State = STATE_IDLE;
        AgentUI::SetStatus("Idle");
    }
}

void ProcessToolCalls() {
    if (g_State != STATE_TOOL_CALLS_PENDING) {
        return;
    }
    g_State = STATE_EXECUTING_TOOLS;

    for (uint i = 0; i < g_PendingToolCalls.Length; i++) {
        Json::Value@ toolCall = g_PendingToolCalls[i];
        string name = toolCall["name"];
        Json::Value@ input = toolCall["input"];
        string toolCallId = toolCall["id"];

        AgentUI::AddToolCall(name, Json::Write(input));
        Json::Value@ result = ToolAssembler::ExecuteToolCall(toolCall);

        Json::Value@ actualResult;
        if (result.HasKey("request_id")) {
            string requestId = result["request_id"];
            Json::Value@ pollReq = Json::Object();
            pollReq["requestId"] = requestId;

            while (true) {
                yield();
                sleep(500);
                Json::Value@ pollResult = McpTM::GetResult(pollReq);
                if (pollResult.HasKey("status")) {
                    string status = pollResult["status"];
                    if (status == "done") {
                        if (pollResult.HasKey("result")) {
                            actualResult = pollResult["result"];
                        } else {
                            actualResult = Json::Object();
                            actualResult["result"] = "done";
                        }
                        break;
                    } else if (status == "error") {
                        if (pollResult.HasKey("error")) {
                            actualResult = Json::Object();
                            actualResult["error"] = pollResult["error"];
                        } else {
                            actualResult = Json::Object();
                            actualResult["error"] = "Unknown error";
                        }
                        break;
                    }
                } else {
                    actualResult = pollResult;
                    break;
                }
            }
        } else {
            actualResult = result;
        }

        AgentUI::AddToolResult(name, Json::Write(actualResult));
        LlmHistory::AddToolResult(toolCallId, name, Json::Write(actualResult));
    }

    g_PendingToolCalls.RemoveRange(0, g_PendingToolCalls.Length);
    g_State = STATE_AWAITING_LLM;
    AgentUI::IncrementStep();
    startnew(AgentLoopCoroutine, "");
}

void CancelCurrentRun() {
    g_State = STATE_IDLE;
    g_PendingToolCalls.RemoveRange(0, g_PendingToolCalls.Length);
    AgentUI::SetStatus("Cancelled");
}

string GetStateString() {
    switch (g_State) {
        case STATE_IDLE:
            return "IDLE";
        case STATE_AWAITING_LLM:
            return "AWAITING_LLM";
        case STATE_TOOL_CALLS_PENDING:
            return "TOOL_CALLS_PENDING";
        case STATE_EXECUTING_TOOLS:
            return "EXECUTING_TOOLS";
        default:
            return "UNKNOWN";
    }
}
