const int STATE_IDLE = 0;
const int STATE_AWAITING_LLM = 1;
const int STATE_TOOL_CALLS_PENDING = 2;
const int STATE_EXECUTING_TOOLS = 3;

int g_State = STATE_IDLE;
array<Json::Value@> g_PendingToolCalls;
uint g_RunGeneration = 0;

#if UNITTEST
bool g_TestAsyncPollHarnessEnabled = false;
bool g_TestAsyncPollSuspended = false;
bool g_TestAsyncPollResume = false;
#endif

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
    FollowCam::SetAgentBusy(true);
    AgentUI::SetStatus(AgentUI::StatusKind::CallingLLM);
    uint generation = ++g_RunGeneration;
    startnew(CoroutineFuncUserdata(AgentLoopCoroutine), AgentRunRequest(generation, content));
}

// Mirror of g_State for FollowCam: busy while a run is in flight. Every
// terminal path funnels through MarkIdle() so the follow camera always
// hands control back.
void MarkIdle() {
    g_State = STATE_IDLE;
    FollowCam::SetAgentBusy(false);
}

// Minimal provider ping used by the "Test Provider" button in Settings.
// Lives next to AgentLoopCoroutine because the AiApi::* cross-plugin
// imports only bind correctly when invoked from this file.
void ProviderTestCoro() {
    try {
        ProviderTestCoroImpl();
    } catch {
        string error = getExceptionInfo();
        print("[tm-agent] provider test exception: " + error);
        AgentUI::g_TestResult = "Provider exception";
        AgentUI::g_TestColor = vec4(0.96, 0.32, 0.30, 1.0);
        AgentUI::g_TestRunning = false;
    }
}

void ProviderTestCoroImpl() {
    uint tStart = Time::Now;
    Provider provider = AgentSettings::S_Provider;
    string provLabel = AgentSettings::CurrentProviderLabel();
    string apiKey = AgentSettings::CurrentApiKey();
    string model = AgentSettings::CurrentModel();

    print("[tm-agent] test: provider=" + provLabel + " model=" + model + " keyLen=" + apiKey.Length);

    if (apiKey.Length == 0) {
        AgentUI::g_TestResult = "No API key set";
        AgentUI::g_TestColor = vec4(0.96, 0.32, 0.30, 1.0);
        AgentUI::g_TestRunning = false;
        return;
    }
    if (provider == Provider::CustomOpenAI && AgentSettings::S_CustomOpenAIBaseUrl.Length == 0) {
        AgentUI::g_TestResult = "No base URL set";
        AgentUI::g_TestColor = vec4(0.96, 0.32, 0.30, 1.0);
        AgentUI::g_TestRunning = false;
        return;
    }
    if (provider == Provider::CustomAnthropic && AgentSettings::S_CustomAnthropicBaseUrl.Length == 0) {
        AgentUI::g_TestResult = "No base URL set";
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
    } else if (provider == Provider::CustomAnthropic) {
        AiApi::ILlmProvider@ custom = AiApi::NewCustomAnthropicProvider(apiKey, AgentSettings::S_CustomAnthropicBaseUrl);
        @resp = custom.CompleteAnthropicMessages(model, msgs, tools);
    } else if (provider == Provider::CustomOpenAI) {
        // Use the configured effort so "Test Provider" validates the
        // actual config you use in real turns, not a hardcoded placeholder.
        AiApi::ILlmProvider@ custom = AiApi::NewCustomOpenAIProvider(apiKey, AgentSettings::S_CustomOpenAIBaseUrl);
        @resp = custom.Complete(model, AgentSettings::S_CustomOpenAIReasoningEffort, msgs, tools);
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
    try {
        AgentLoopCoroutineImpl(requestRef);
    } catch {
        if (request !is null && request.generation == g_RunGeneration) {
            string error = getExceptionInfo();
            print("[tm-agent] agent loop exception: " + error);
            SessionLog::LogError("agent loop exception: " + error);
            RecordPendingToolFailures("Agent request aborted unexpectedly");
            AgentUI::SetStatus(AgentUI::StatusKind::Error, "Agent request failed");
            AgentUI::AddMessage(AgentUI::MsgType::Assistant, "Error: Agent request failed unexpectedly.");
            MarkIdle();
        }
    }
}

void AgentLoopCoroutineImpl(ref@ requestRef) {
    AgentRunRequest@ request = cast<AgentRunRequest>(requestRef);
    if (request is null || request.generation != g_RunGeneration) return;

    Json::Value@ tools = ToolAssembler::GetToolList();
    // Real request: bypass the UI's snapshot TTL so the model sees current
    // editor state, not something up to 5s old.
    ToolAssembler::InvalidateEditorStateCache();
    string editorState = LlmHistory::BoundEditorStateForBudget(
        tools, AgentSettings::S_MaxHistoryTokens, ToolAssembler::GetEditorStateSnapshot());
    if (!LlmHistory::CompactHistory(tools, AgentSettings::S_MaxHistoryTokens, editorState)) {
        SessionLog::LogError("History exceeds configured token ceiling");
        AgentUI::SetStatus(AgentUI::StatusKind::Error, "History exceeds configured token ceiling");
        AgentUI::AddMessage(AgentUI::MsgType::Assistant,
            "Error: The current complete turn cannot fit within Max History Tokens. Increase the limit or start a new conversation.");
        MarkIdle();
        return;
    }
    Json::Value@ messages = LlmHistory::GetMessagesForLlm(tools, editorState);

    Provider provider = AgentSettings::S_Provider;
    string apiKey = AgentSettings::CurrentApiKey();
    string model = AgentSettings::CurrentModel();

    bool missingConfig = apiKey.Length == 0;
    if (!missingConfig && provider == Provider::CustomOpenAI) {
        missingConfig = AgentSettings::S_CustomOpenAIBaseUrl.Length == 0;
    } else if (!missingConfig && provider == Provider::CustomAnthropic) {
        missingConfig = AgentSettings::S_CustomAnthropicBaseUrl.Length == 0;
    }
    if (missingConfig) {
        SessionLog::LogError("No valid API key/base URL configured");
        AgentUI::SetStatus(AgentUI::StatusKind::Error, "No valid API key configured");
        AgentUI::AddMessage(AgentUI::MsgType::Assistant, "Error: No valid API key/base URL configured. Please check your settings.");
        MarkIdle();
        return;
    }

    Json::Value@ resp;
    if (provider == Provider::MiniMax) {
        string system;
        Json::Value@ anthropicMessages = LlmHistory::GetMessagesForAnthropic(tools, system, editorState);
        @resp = AiApi::Anthropic_Complete(apiKey, model, anthropicMessages, ToolAssembler::GetToolList(), system);
    } else if (provider == Provider::CustomAnthropic) {
        AiApi::ILlmProvider@ custom = AiApi::NewCustomAnthropicProvider(apiKey, AgentSettings::S_CustomAnthropicBaseUrl);
        string system;
        Json::Value@ anthropicMessages = LlmHistory::GetMessagesForAnthropic(tools, system, editorState);
        @resp = custom.CompleteAnthropicMessages(model, anthropicMessages, ToolAssembler::GetToolList(), system);
    } else if (provider == Provider::CustomOpenAI) {
        AiApi::ILlmProvider@ custom = AiApi::NewCustomOpenAIProvider(apiKey, AgentSettings::S_CustomOpenAIBaseUrl);
        @resp = custom.Complete(
            model,
            AgentSettings::S_CustomOpenAIReasoningEffort,
            messages,
            ToolAssembler::GetToolList()
        );
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
        SessionLog::LogError("Provider returned no response");
        AgentUI::SetStatus(AgentUI::StatusKind::Error, "Provider returned no response");
        AgentUI::AddMessage(AgentUI::MsgType::Assistant, "Error: Provider returned no response.");
        MarkIdle();
        return;
    }

    string respDumpFull = Json::Write(resp);
    {
        string respDump = respDumpFull.Length > 1200 ? respDumpFull.SubStr(0, 1200) + "…" : respDumpFull;
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
        SessionLog::LogError(errorMsg);
        AgentUI::SetStatus(AgentUI::StatusKind::Error, errorMsg);
        AgentUI::AddMessage(AgentUI::MsgType::Assistant, "Error: " + errorMsg);
        MarkIdle();
        return;
    }

    int lastIn = 0;
    int lastOut = 0;
    int lastTot = 0;
    if (resp.HasKey("usage") && resp["usage"].GetType() == Json::Type::Object) {
        Json::Value@ usage = resp["usage"];
        lastIn = usage.HasKey("input_tokens") ? int(usage["input_tokens"]) : 0;
        lastOut = usage.HasKey("output_tokens") ? int(usage["output_tokens"]) : 0;
        lastTot = usage.HasKey("total_tokens") ? int(usage["total_tokens"]) : 0;
        AgentUI::UpdateTokenStats(lastIn, lastOut, lastTot);
    }

    string text = "";
    if (resp.HasKey("text") && resp["text"].GetType() != Json::Type::Null) {
        text = string(resp["text"]);
    }
    auto parsedToolCalls = ToolAssembler::ParseToolCalls(resp);
    if (parsedToolCalls.Length > 0) {
        Json::Value@ reasoningItems = resp.HasKey("reasoning_items") ? resp["reasoning_items"] : null;
        // Log-before-UI: persist the exchange and the assistant turn before
        // any history/UI state mutates, so a crash cannot lose the response.
        SessionLog::LogLlmExchange(lastIn, lastOut, lastTot, respDumpFull);
        SessionLog::LogAssistantMessage(text);
        LlmHistory::AddAssistantToolCalls(text, parsedToolCalls, reasoningItems);
        AgentUI::AddMessage(AgentUI::MsgType::Assistant, text);
        AgentUI::IncrementStep();
        g_PendingToolCalls = parsedToolCalls;
        g_State = STATE_TOOL_CALLS_PENDING;
        ProcessToolCalls(request.generation);
    } else {
        Json::Value@ reasoningItems = resp.HasKey("reasoning_items") ? resp["reasoning_items"] : null;
        SessionLog::LogLlmExchange(lastIn, lastOut, lastTot, respDumpFull);
        SessionLog::LogAssistantMessage(text);
        LlmHistory::AddAssistantMessage(text, reasoningItems);
        AgentUI::AddMessage(AgentUI::MsgType::Assistant, text);
        AgentUI::IncrementStep();
        MarkIdle();
        AgentUI::SetStatus(AgentUI::StatusKind::Idle);
    }
}

void ProcessToolCalls(uint generation) {
    try {
        ProcessToolCallsImpl(generation);
    } catch {
        if (generation == g_RunGeneration) {
            string error = getExceptionInfo();
            print("[tm-agent] tool execution exception: " + error);
            SessionLog::LogError("tool execution exception: " + error);
            // The assistant tool-call message is already durable history at
            // this point. Close every remaining call before returning so both
            // Responses and Anthropic histories remain structurally valid.
            RecordPendingToolFailures("Tool execution aborted unexpectedly");
            AgentUI::SetStatus(AgentUI::StatusKind::Error, "Tool execution failed");
            AgentUI::AddMessage(AgentUI::MsgType::Assistant, "Error: Tool execution failed unexpectedly.");
            MarkIdle();
        }
    }
}

Json::Value@ NewToolError(const string &in message) {
    Json::Value@ result = Json::Object();
    result["success"] = false;
    result["error"] = message;
    return result;
}

string SafeToolCallString(Json::Value@ toolCall, const string &in key, const string &in fallback) {
    if (toolCall is null || toolCall.GetType() != Json::Type::Object) return fallback;
    return JsonX::Lookup_StringOrDefault(toolCall, key, fallback);
}

void RecordToolResult(Json::Value@ toolCall, Json::Value@ actualResult) {
    string name = SafeToolCallString(toolCall, "name", "invalid_tool_call");
    string toolCallId = SafeToolCallString(toolCall, "id", "invalid_call");
    string resultJson = Json::Write(actualResult);
    // Log-before-UI: the durable record is written before the UI chip and
    // provider history are updated.
    SessionLog::LogToolResult(name, resultJson);
    AgentUI::AddToolResult(name, resultJson);
    LlmHistory::AddToolResult(toolCallId, name, resultJson);
}

void RecordPendingToolFailures(const string &in message) {
    while (g_PendingToolCalls.Length > 0) {
        Json::Value@ toolCall = g_PendingToolCalls[0];
        RecordToolResult(toolCall, NewToolError(message));
        g_PendingToolCalls.RemoveAt(0);
    }
}

bool CommitToolResultIfCurrent(uint generation, Json::Value@ toolCall, Json::Value@ actualResult) {
    if (generation != g_RunGeneration || g_PendingToolCalls.Length == 0) return false;
    string expectedId = SafeToolCallString(toolCall, "id", "invalid_call");
    string pendingId = SafeToolCallString(g_PendingToolCalls[0], "id", "invalid_call");
    if (expectedId != pendingId) return false;

    RecordToolResult(toolCall, actualResult);
    g_PendingToolCalls.RemoveAt(0);
    return true;
}

Json::Value@ ExecutePendingToolCall(Json::Value@ toolCall, uint generation) {
    if (toolCall is null || toolCall.GetType() != Json::Type::Object) {
        return NewToolError("Malformed tool call: expected an object");
    }

    string name = SafeToolCallString(toolCall, "name", "");
    if (name.Length == 0) {
        return NewToolError("Malformed tool call: missing tool name");
    }
    if (!toolCall.HasKey("input") || toolCall["input"].GetType() != Json::Type::Object) {
        return NewToolError("Malformed tool call for " + name + ": input must be an object");
    }

    Json::Value@ input = toolCall["input"];
    // Log-before-UI: the outgoing call is logged before the UI chip renders.
    SessionLog::LogToolCall(name, Json::Write(input));
    AgentUI::AddToolCall(name, Json::Write(input));

    Json::Value@ result;
#if UNITTEST
    if (g_TestAsyncPollHarnessEnabled) {
        @result = Json::Object();
        result["request_id"] = "unit_test_async_request";
    } else {
#endif
    try {
        @result = ToolAssembler::ExecuteToolCall(toolCall);
    } catch {
        string error = getExceptionInfo();
        print("[tm-agent] tool " + name + " threw: " + error);
        return NewToolError("Tool " + name + " failed unexpectedly");
    }
#if UNITTEST
    }
#endif

    if (result is null) {
        return NewToolError("Tool returned no response");
    }
    if (!result.HasKey("request_id")) return result;

    string requestId = JsonX::Lookup_StringOrDefault(result, "request_id", "");
    if (requestId.Length == 0) return NewToolError("Tool returned an invalid request id");
    Json::Value@ pollReq = Json::Object();
    pollReq["requestId"] = requestId;
    uint pollStartedAt = Time::Now;

    while (true) {
#if UNITTEST
        if (g_TestAsyncPollHarnessEnabled) {
            g_TestAsyncPollSuspended = true;
            while (!g_TestAsyncPollResume) yield();
        } else {
#endif
        yield();
        sleep(500);
#if UNITTEST
        }
#endif
        if (generation != g_RunGeneration) return NewToolError("Tool run was cancelled");
        if (Time::Now - pollStartedAt >= 120000) {
            return NewToolError("Timed out waiting for tool result");
        }

        Json::Value@ pollResult;
        try {
            @pollResult = TmMcp::GetResult(pollReq);
        } catch {
            print("[tm-agent] tool polling threw: " + getExceptionInfo());
            return NewToolError("Tool polling failed unexpectedly");
        }
        if (pollResult is null) return NewToolError("Tool polling returned no response");
        if (!pollResult.HasKey("status")) return pollResult;

        string status = JsonX::Lookup_StringOrDefault(pollResult, "status", "");
        if (status == "done") {
            if (pollResult.HasKey("result")) return pollResult["result"];
            Json::Value@ done = Json::Object();
            done["result"] = "done";
            return done;
        }
        if (status == "error") {
            string message = JsonX::Lookup_StringOrDefault(pollResult, "error", "Unknown error");
            return NewToolError(message);
        }
    }
    return NewToolError("Tool polling ended unexpectedly");
}

void ProcessToolCallsImpl(uint generation) {
    if (generation != g_RunGeneration || g_State != STATE_TOOL_CALLS_PENDING) {
        return;
    }
    g_State = STATE_EXECUTING_TOOLS;

    while (g_PendingToolCalls.Length > 0) {
        if (generation != g_RunGeneration) {
            RecordPendingToolFailures("Tool run was cancelled");
            return;
        }

        Json::Value@ toolCall = g_PendingToolCalls[0];
        string name = SafeToolCallString(toolCall, "name", "invalid_tool_call");
        Json::Value@ actualResult = ExecutePendingToolCall(toolCall, generation);
        // ExecutePendingToolCall can suspend while polling. Cancellation owns
        // terminal results for the queue, so a stale worker must not write or
        // remove anything after it resumes.
        if (!CommitToolResultIfCurrent(generation, toolCall, actualResult)) return;

        // Follow camera: one ping per executed tool call (sync and async
        // alike), success or not — it tracks where work happens, not whether
        // it succeeded. ToolFocus::ExtractFocusPos filters non-positional
        // tools cheaply.
        FollowCam::OnAgentActivity(name, toolCall.HasKey("input") ? toolCall["input"] : null);

        if (IsToolResultSuccess(actualResult)) {
            if (name == "PlaceBlock") AgentStats::RecordBlockPlaced();
            else if (name == "RemoveBlock") AgentStats::RecordBlockRemoved();
        }
    }

    if (generation != g_RunGeneration) return;
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
    // Cancellation can race with a persisted assistant tool-call turn. Close
    // those calls before clearing the queue so future provider requests never
    // contain dangling call ids.
    RecordPendingToolFailures("Tool run was cancelled");
    MarkIdle();
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
