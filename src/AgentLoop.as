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

void AgentLoopCoroutine(const string &in userContent) {
    LlmHistory::TruncateHistory(AgentSettings::S_MaxHistoryTokens);
    Json::Value@ messages = LlmHistory::GetMessagesForLlm(ToolAssembler::GetToolList());

    string provider = AgentSettings::S_Provider;
    string apiKey;
    string model;

    if (provider == "minimax" && AgentSettings::S_MiniMaxApiKey.Length > 0) {
        apiKey = AgentSettings::S_MiniMaxApiKey;
        model = AgentSettings::S_MiniMaxModel;
    } else if (provider == "openai" && AgentSettings::S_OpenAIApiKey.Length > 0) {
        apiKey = AgentSettings::S_OpenAIApiKey;
        model = AgentSettings::S_OpenAIModel;
    } else {
        AgentUI::SetStatus("Error: No valid API key configured");
        AgentUI::AddMessage(AgentUI::MsgType::Assistant, "Error: No valid API key configured. Please check your settings.");
        g_State = STATE_IDLE;
        return;
    }

    Json::Value@ resp;
    if (provider == "minimax") {
        resp = AiApi::Anthropic_Complete(apiKey, model, messages, ToolAssembler::GetToolList());
    } else {
        resp = AiApi::OpenAI_Complete(apiKey, model, messages, ToolAssembler::GetToolList());
    }

    if (resp.HasKey("error") && !resp["error"].IsNull()) {
        string errorMsg = resp["error"].IsString() ? string(resp["error"]) : Json::Stringify(resp["error"]);
        AgentUI::SetStatus("Error: " + errorMsg);
        AgentUI::AddMessage(AgentUI::MsgType::Assistant, "Error: " + errorMsg);
        g_State = STATE_IDLE;
        return;
    }

    string text = "";
    if (resp.HasKey("text") && !resp["text"].IsNull()) {
        text = string(resp["text"]);
    }

    Json::Value@ toolCalls = null;
    if (resp.HasKey("tool_calls") && !resp["tool_calls"].IsNull()) {
        toolCalls = resp["tool_calls"];
    }

    if (toolCalls !is null && toolCalls.Length > 0) {
        LlmHistory::AddAssistantMessage(text);
        AgentUI::AddMessage(AgentUI::MsgType::Assistant, text);
        AgentUI::IncrementStep();
        g_PendingToolCalls = ToolAssembler::ParseToolCalls(resp);
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

        AgentUI::AddToolCall(name, Json::Stringify(input));
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
                        if (pollResult.HasKey("data")) {
                            actualResult = pollResult["data"];
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

        AgentUI::AddToolResult(name, Json::Stringify(actualResult));
        // LlmHistory::AddToolResult(toolCallId, name, Json::Stringify(actualResult));
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
