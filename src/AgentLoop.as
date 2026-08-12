const int STATE_IDLE = 0;
const int STATE_AWAITING_LLM = 1;
const int STATE_TOOL_CALLS_PENDING = 2;
const int STATE_EXECUTING_TOOLS = 3;

int g_State = STATE_IDLE;
array<Json::Value@> g_PendingToolCalls;
uint g_RunGeneration = 0;

class AgentRunRequest {
    uint generation;
    string content;

    AgentRunRequest(uint generation, const string &in content) {
        this.generation = generation;
        this.content = content;
    }
}

void SendMessage(const string &in content) {
    if (g_State != STATE_IDLE) {
        return;
    }
    LlmHistory::AddUserMessage(content);
    g_State = STATE_AWAITING_LLM;
    AgentUI::SetStatus(AgentUI::StatusKind::CallingLLM);
    uint generation = ++g_RunGeneration;
    startnew(CoroutineFuncUserdata(AgentLoopCoroutine), AgentRunRequest(generation, content));
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
        Json::Value@ errNode = resp["error"];
        string err;
        if (errNode.GetType() == Json::Type::String) {
            err = string(errNode);
        } else if (errNode.GetType() == Json::Type::Object && errNode.HasKey("message")) {
            err = string(errNode["message"]);
        } else {
            err = Json::Write(errNode);
        }
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

void AgentLoopCoroutine(ref@ requestRef) {
    AgentRunRequest@ request = cast<AgentRunRequest>(requestRef);
    if (request is null || request.generation != g_RunGeneration) return;

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
        AgentUI::SetStatus(AgentUI::StatusKind::Error, "No valid API key configured");
        AgentUI::AddMessage(AgentUI::MsgType::Assistant, "Error: No valid API key configured. Please check your settings.");
        g_State = STATE_IDLE;
        return;
    }

    Json::Value@ resp;
    if (provider == Provider::MiniMax) {
        string system;
        Json::Value@ anthropicMessages = LlmHistory::GetMessagesForAnthropic(tools, system);
        @resp = AiApi::Anthropic_Complete(apiKey, model, anthropicMessages, ToolAssembler::GetToolList(), system);
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

    // HTTP requests cannot be interrupted, so cancellation invalidates their
    // generation and discards the eventual response before it can mutate UI,
    // history, or execute tools in a newer conversation.
    if (request.generation != g_RunGeneration) return;

    if (resp is null) {
        AgentUI::SetStatus(AgentUI::StatusKind::Error, "Provider returned no response");
        AgentUI::AddMessage(AgentUI::MsgType::Assistant, "Error: Provider returned no response.");
        g_State = STATE_IDLE;
        return;
    }

    {
        string respDump = Json::Write(resp);
        if (respDump.Length > 1200) respDump = respDump.SubStr(0, 1200) + "…";
        print("[tm-agent] LLM resp: " + respDump);
    }

    if (resp.HasKey("error") && resp["error"].GetType() != Json::Type::Null) {
        Json::Value@ errNode = resp["error"];
        string errorMsg;
        if (errNode.GetType() == Json::Type::String) {
            errorMsg = string(errNode);
        } else if (errNode.GetType() == Json::Type::Object && errNode.HasKey("message")) {
            errorMsg = string(errNode["message"]);
        } else {
            errorMsg = Json::Write(errNode);
        }
        AgentUI::SetStatus(AgentUI::StatusKind::Error, errorMsg);
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
        ProcessToolCalls(request.generation);
    } else {
        LlmHistory::AddAssistantMessage(text);
        AgentUI::AddMessage(AgentUI::MsgType::Assistant, text);
        AgentUI::IncrementStep();
        g_State = STATE_IDLE;
        AgentUI::SetStatus(AgentUI::StatusKind::Idle);
    }
}

void ProcessToolCalls(uint generation) {
    if (generation != g_RunGeneration || g_State != STATE_TOOL_CALLS_PENDING) {
        return;
    }
    g_State = STATE_EXECUTING_TOOLS;

    for (uint i = 0; i < g_PendingToolCalls.Length; i++) {
        if (generation != g_RunGeneration) return;

        Json::Value@ toolCall = g_PendingToolCalls[i];
        string name = toolCall["name"];
        Json::Value@ input = toolCall["input"];
        string toolCallId = toolCall["id"];

        AgentUI::AddToolCall(name, Json::Write(input));
        Json::Value@ result = ToolAssembler::ExecuteToolCall(toolCall);

        Json::Value@ actualResult;
        if (result is null) {
            @actualResult = Json::Object();
            actualResult["error"] = "Tool returned no response";
        } else if (result.HasKey("request_id")) {
            string requestId = result["request_id"];
            Json::Value@ pollReq = Json::Object();
            pollReq["requestId"] = requestId;
            uint pollStartedAt = Time::Now;

            while (true) {
                yield();
                sleep(500);
                if (generation != g_RunGeneration) return;
                if (Time::Now - pollStartedAt >= 120000) {
                    @actualResult = Json::Object();
                    actualResult["error"] = "Timed out waiting for tool result";
                    break;
                }
                Json::Value@ pollResult = McpTM::GetResult(pollReq);
                if (pollResult is null) {
                    @actualResult = Json::Object();
                    actualResult["error"] = "Tool polling returned no response";
                    break;
                } else if (pollResult.HasKey("status")) {
                    string status = pollResult["status"];
                    if (status == "done") {
                        if (pollResult.HasKey("result")) {
                            @actualResult = pollResult["result"];
                        } else {
                            @actualResult = Json::Object();
                            actualResult["result"] = "done";
                        }
                        break;
                    } else if (status == "error") {
                        if (pollResult.HasKey("error")) {
                            @actualResult = Json::Object();
                            actualResult["error"] = pollResult["error"];
                        } else {
                            @actualResult = Json::Object();
                            actualResult["error"] = "Unknown error";
                        }
                        break;
                    }
                } else {
                    @actualResult = pollResult;
                    break;
                }
            }
        } else {
            @actualResult = result;
        }

        AgentUI::AddToolResult(name, Json::Write(actualResult));
        LlmHistory::AddToolResult(toolCallId, name, Json::Write(actualResult));

        if (IsToolResultSuccess(actualResult)) {
            if (name == "PlaceBlock") AgentStats::RecordBlockPlaced();
            else if (name == "RemoveBlock") AgentStats::RecordBlockRemoved();
        }
    }

    if (generation != g_RunGeneration) return;
    g_PendingToolCalls.RemoveRange(0, g_PendingToolCalls.Length);
    g_State = STATE_AWAITING_LLM;
    AgentUI::IncrementStep();
    startnew(CoroutineFuncUserdata(AgentLoopCoroutine), AgentRunRequest(generation, ""));
}

bool IsToolResultSuccess(Json::Value@ r) {
    if (r is null || r.GetType() != Json::Type::Object) return false;
    if (r.HasKey("error")) return false;
    if (r.HasKey("success") && !bool(r["success"])) return false;
    if (r.HasKey("ok") && !bool(r["ok"])) return false;
    if (r.HasKey("output") && r["output"].GetType() == Json::Type::Object) {
        Json::Value@ output = r["output"];
        if (output.HasKey("error")) return false;
        if (output.HasKey("success") && !bool(output["success"])) return false;
        if (output.HasKey("ok") && !bool(output["ok"])) return false;
    }
    return true;
}

void CancelCurrentRun() {
    g_RunGeneration++;
    g_State = STATE_IDLE;
    g_PendingToolCalls.RemoveRange(0, g_PendingToolCalls.Length);
    AgentUI::SetStatus(AgentUI::StatusKind::Cancelled);
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
