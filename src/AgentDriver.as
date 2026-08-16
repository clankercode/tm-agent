namespace AgentDriver {
    uint g_LastPollAt = 0;
    const uint POLL_INTERVAL_MS = 250;
    // Handle of the most recent async call_tool dispatch (see poll_async).
    string g_AsyncHandle = "";

    string CmdPath() { return IO::FromStorageFolder("driver_cmd.json"); }
    string RespPath() { return IO::FromStorageFolder("driver_resp.json"); }

    void Poll() {
        if (Time::Now - g_LastPollAt < POLL_INTERVAL_MS) return;
        g_LastPollAt = Time::Now;

        string path = CmdPath();
        if (!IO::FileExists(path)) return;

        string raw;
        {
            IO::File f(path, IO::FileMode::Read);
            raw = f.ReadToEnd();
            f.Close();
        }
        IO::Delete(path);

        Json::Value@ req = Json::Parse(raw);
        Json::Value@ resp = Execute(req);

        IO::File rf(RespPath(), IO::FileMode::Write);
        rf.Write(Json::Write(resp));
        rf.Close();
    }

    Json::Value@ Execute(Json::Value@ req) {
        Json::Value resp = Json::Object();
        if (req is null || req.GetType() != Json::Type::Object || !req.HasKey("op")) {
            resp["ok"] = false;
            resp["error"] = "missing op";
            return resp;
        }
        string op = string(req["op"]);
        resp["op"] = op;

        if (op == "get_state") {
            resp["ok"] = true;
            resp["input"] = AgentUI::g_InputText;
            resp["status"] = AgentUI::g_Status.Wire;
            resp["turn"] = AgentUI::g_CurrentTurn;
            resp["step"] = AgentUI::g_StepCount;
            resp["showSettings"] = AgentUI::g_ShowSettings;
            resp["showWindow"] = AgentSettings::S_ShowWindow;
            resp["messageCount"] = int(AgentUI::g_Messages.Length);
            return resp;
        }
        if (op == "set_input") {
            if (!req.HasKey("text")) { resp["ok"] = false; resp["error"] = "text required"; return resp; }
            AgentUI::g_InputText = string(req["text"]);
            resp["ok"] = true;
            return resp;
        }
        if (op == "append_input") {
            if (!req.HasKey("text")) { resp["ok"] = false; resp["error"] = "text required"; return resp; }
            AgentUI::g_InputText += string(req["text"]);
            resp["ok"] = true;
            return resp;
        }
        if (op == "send") {
            if (AgentUI::g_InputText.Length == 0) { resp["ok"] = false; resp["error"] = "input empty"; return resp; }
            if (!AgentUI::SendMessage(AgentUI::g_InputText)) {
                resp["ok"] = false;
                resp["error"] = "agent busy";
                return resp;
            }
            AgentUI::g_InputText = "";
            resp["ok"] = true;
            return resp;
        }
        if (op == "new") {
            AgentUI::ClearMessages();
            resp["ok"] = true;
            return resp;
        }
        if (op == "open_settings") {
            AgentUI::g_ShowSettings = true;
            resp["ok"] = true;
            return resp;
        }
        if (op == "close_settings") {
            AgentUI::g_ShowSettings = false;
            resp["ok"] = true;
            return resp;
        }
        if (op == "toggle_settings") {
            AgentUI::g_ShowSettings = !AgentUI::g_ShowSettings;
            resp["ok"] = true;
            resp["showSettings"] = AgentUI::g_ShowSettings;
            return resp;
        }
        if (op == "show_window") {
            bool v = req.HasKey("value") ? bool(req["value"]) : true;
            AgentSettings::S_ShowWindow = v;
            resp["ok"] = true;
            return resp;
        }
        if (op == "compact") {
            Json::Value@ tools = ToolAssembler::GetToolList();
            LlmHistory::CompactHistory(tools, AgentSettings::S_MaxHistoryTokens);
            resp["ok"] = true;
            return resp;
        }
        if (op == "ping") {
            resp["ok"] = true;
            resp["pong"] = Time::Now;
            return resp;
        }
        if (op == "test_provider") {
            AgentUI::StartProviderTest();
            resp["ok"] = true;
            return resp;
        }
        if (op == "get_test") {
            resp["ok"] = true;
            resp["running"] = AgentUI::g_TestRunning;
            resp["result"] = AgentUI::g_TestResult;
            return resp;
        }
        if (op == "get_windows") {
            resp["ok"] = true;

            Json::Value agent = Json::Object();
            agent["visible"] = AgentSettings::S_ShowWindow;
            Json::Value agentPos = Json::Array();
            agentPos.Add(int(AgentUI::g_WindowPos.x));
            agentPos.Add(int(AgentUI::g_WindowPos.y));
            agent["pos"] = agentPos;
            Json::Value agentSize = Json::Array();
            agentSize.Add(int(AgentUI::g_WindowWidth));
            agentSize.Add(int(AgentUI::g_WindowHeight));
            agent["size"] = agentSize;
            resp["agent"] = agent;

            Json::Value settings = Json::Object();
            settings["visible"] = AgentUI::g_ShowSettings;
            Json::Value settingsPos = Json::Array();
            settingsPos.Add(int(AgentUI::g_SettingsPos.x));
            settingsPos.Add(int(AgentUI::g_SettingsPos.y));
            settings["pos"] = settingsPos;
            Json::Value settingsSize = Json::Array();
            settingsSize.Add(int(AgentUI::g_SettingsSize.x));
            settingsSize.Add(int(AgentUI::g_SettingsSize.y));
            settings["size"] = settingsSize;
            resp["settings"] = settings;

            return resp;
        }
        if (op == "add_message") {
            if (!req.HasKey("role") || !req.HasKey("text")) {
                resp["ok"] = false; resp["error"] = "role and text required"; return resp;
            }
            string role = string(req["role"]);
            string text = string(req["text"]);
            AgentUI::MsgType t;
            if (role == "user") t = AgentUI::MsgType::User;
            else if (role == "assistant" || role == "agent") t = AgentUI::MsgType::Assistant;
            else if (role == "tool_call") t = AgentUI::MsgType::ToolCall;
            else if (role == "tool_result") t = AgentUI::MsgType::ToolResult;
            else if (role == "system") t = AgentUI::MsgType::System;
            else { resp["ok"] = false; resp["error"] = "unknown role"; return resp; }
            // Driver-injected messages are part of the session too (demo
            // seeding, tests): log before the UI mutation.
            string injectedTool = req.HasKey("tool") ? string(req["tool"]) : "";
            if (t == AgentUI::MsgType::User) SessionLog::LogUserMessage(text);
            else if (t == AgentUI::MsgType::Assistant) SessionLog::LogAssistantMessage(text);
            else if (t == AgentUI::MsgType::ToolCall) SessionLog::LogToolCall(injectedTool, text);
            else if (t == AgentUI::MsgType::ToolResult) SessionLog::LogToolResult(injectedTool, text);
            else SessionLog::WriteRecord("system", text);
            // Tool roles must go through AddToolCall/AddToolResult so
            // msg.toolName is set (chips render it; the eye button needs it).
            if (t == AgentUI::MsgType::ToolCall) AgentUI::AddToolCall(injectedTool, text);
            else if (t == AgentUI::MsgType::ToolResult) AgentUI::AddToolResult(injectedTool, text);
            else AgentUI::AddMessage(t, text);
            resp["ok"] = true;
            return resp;
        }
        if (op == "set_status") {
            if (!req.HasKey("status")) { resp["ok"] = false; resp["error"] = "status required"; return resp; }
            string wire = string(req["status"]);
            if (!AgentUI::g_Status.FromWire(wire)) {
                resp["ok"] = false;
                resp["error"] = "unknown status: " + wire;
                return resp;
            }
            resp["ok"] = true;
            return resp;
        }
        if (op == "seed_demo") {
            AgentUI::ClearMessages();
            SessionLog::LogUserMessage("What blocks are on the current map?");
            AgentUI::AddMessage(AgentUI::MsgType::User, "What blocks are on the current map?");
            SessionLog::LogToolCall("GetMapBlocks", "{\"detail\":\"summary\"}");
            AgentUI::AddToolCall("GetMapBlocks", "{\"detail\":\"summary\"}");
            SessionLog::LogToolResult("GetMapBlocks", "{\"total\":247,\"top\":[{\"name\":\"RoadTechStraight\",\"count\":84},{\"name\":\"RoadDirtStraight\",\"count\":36},{\"name\":\"RoadBumpStraight\",\"count\":22}]}");
            AgentUI::AddToolResult("GetMapBlocks", "{\"total\":247,\"top\":[{\"name\":\"RoadTechStraight\",\"count\":84},{\"name\":\"RoadDirtStraight\",\"count\":36},{\"name\":\"RoadBumpStraight\",\"count\":22}]}");
            SessionLog::LogAssistantMessage("The map has 247 blocks total. Most common:\n\n- RoadTechStraight x84\n- RoadDirtStraight x36\n- RoadBumpStraight x22\n\nWant me to list a specific type or region?");
            AgentUI::AddMessage(AgentUI::MsgType::Assistant, "The map has 247 blocks total. Most common:\n\n- RoadTechStraight x84\n- RoadDirtStraight x36\n- RoadBumpStraight x22\n\nWant me to list a specific type or region?");
            SessionLog::LogUserMessage("Place a start block at the cursor.");
            AgentUI::AddMessage(AgentUI::MsgType::User, "Place a start block at the cursor.");
            SessionLog::LogToolCall("PlaceBlock", "{\"block\":\"RoadTechStart\",\"pos\":[24,12,16],\"rot\":\"North\"}");
            AgentUI::AddToolCall("PlaceBlock", "{\"block\":\"RoadTechStart\",\"pos\":[24,12,16],\"rot\":\"North\"}");
            SessionLog::LogToolResult("PlaceBlock", "{\"ok\":true,\"placedAt\":[24,12,16]}");
            AgentUI::AddToolResult("PlaceBlock", "{\"ok\":true,\"placedAt\":[24,12,16]}");
            SessionLog::LogAssistantMessage("Done. Placed RoadTechStart at (24, 12, 16) facing North.");
            AgentUI::AddMessage(AgentUI::MsgType::Assistant, "Done. Placed RoadTechStart at (24, 12, 16) facing North.");
            resp["ok"] = true;
            return resp;
        }
        if (op == "dump_chat") {
            Json::Value arr = Json::Array();
            for (uint i = 0; i < AgentUI::g_Messages.Length; i++) {
                AgentUI::Message@ m = AgentUI::g_Messages[i];
                Json::Value entry = Json::Object();
                string role = "user";
                if (m.type == AgentUI::MsgType::User) role = "user";
                else if (m.type == AgentUI::MsgType::Assistant) role = "assistant";
                else if (m.type == AgentUI::MsgType::ToolCall) role = "tool_call";
                else if (m.type == AgentUI::MsgType::ToolResult) role = "tool_result";
                else if (m.type == AgentUI::MsgType::System) role = "system";
                entry["role"] = role;
                entry["content"] = m.content;
                if (m.toolName.Length > 0) entry["tool"] = m.toolName;
                arr.Add(entry);
            }
            resp["ok"] = true;
            resp["chat"] = arr;
            return resp;
        }
        if (op == "load_chat") {
            if (!req.HasKey("chat")) { resp["ok"] = false; resp["error"] = "chat required"; return resp; }
            Json::Value@ arr = req["chat"];
            if (arr is null || arr.GetType() != Json::Type::Array) { resp["ok"] = false; resp["error"] = "chat must be array"; return resp; }
            AgentUI::ClearMessages();
            for (uint i = 0; i < arr.Length; i++) {
                Json::Value@ e = arr[i];
                if (e is null || !e.HasKey("role")) continue;
                string role = string(e["role"]);
                string content = e.HasKey("content") ? string(e["content"]) : "";
                string toolName = e.HasKey("tool") ? string(e["tool"]) : "";
                if (role == "tool_call") { SessionLog::LogToolCall(toolName, content); AgentUI::AddToolCall(toolName, content); }
                else if (role == "tool_result") { SessionLog::LogToolResult(toolName, content); AgentUI::AddToolResult(toolName, content); }
                else if (role == "assistant" || role == "agent") { SessionLog::LogAssistantMessage(content); AgentUI::AddMessage(AgentUI::MsgType::Assistant, content); }
                else if (role == "system") { SessionLog::WriteRecord("system", content); AgentUI::AddMessage(AgentUI::MsgType::System, content); }
                else { SessionLog::LogUserMessage(content); AgentUI::AddMessage(AgentUI::MsgType::User, content); }
            }
            resp["ok"] = true;
            return resp;
        }
        if (op == "expand_msg") {
            if (!req.HasKey("index")) { resp["ok"] = false; resp["error"] = "index required"; return resp; }
            int ix = int(req["index"]);
            bool value = req.HasKey("value") ? bool(req["value"]) : true;
            if (ix < 0 || uint(ix) >= AgentUI::g_Messages.Length) {
                resp["ok"] = false; resp["error"] = "index out of range"; return resp;
            }
            AgentUI::g_Messages[uint(ix)].expanded = value;
            AgentUI::g_Messages[uint(ix)].InvalidateLayout();
            resp["ok"] = true;
            return resp;
        }
        if (op == "demo_mode") {
            if (req.HasKey("value")) {
                AgentUI::g_DemoMode = bool(req["value"]);
            } else {
                AgentUI::g_DemoMode = !AgentUI::g_DemoMode;
            }
            resp["ok"] = true;
            resp["demoMode"] = AgentUI::g_DemoMode;
            return resp;
        }

        if (op == "call_tool") {
            // Verification helper: invoke any MCP tool by name through the
            // plugin's own dispatch path (exercises the same code the LLM
            // loop uses). Suspending tools (e.g. TakeScreenshot) can't run
            // here (Poll runs in the render context — no suspension), so
            // async:true dispatches and returns a handle; poll it with the
            // poll_async op.
            if (!req.HasKey("tool")) { resp["ok"] = false; resp["error"] = "tool required"; return resp; }
            Json::Value input = req.HasKey("input") ? req["input"] : Json::Object();
            resp["ok"] = true;
            if (req.HasKey("async") && bool(req["async"])) {
                Json::Value@ h = TmMcp::DispatchAsync(string(req["tool"]), input);
                if (h is null || !h.HasKey("request_id")) {
                    resp["error"] = "dispatch failed";
                    if (h !is null && h.HasKey("error")) resp["detail"] = string(h["error"]);
                    return resp;
                }
                g_AsyncHandle = string(h["request_id"]);
                resp["request_id"] = g_AsyncHandle;
                return resp;
            }
            resp["result"] = TmMcp::CallTool(string(req["tool"]), input);
            return resp;
        }
        if (op == "poll_async") {
            // Poll the handle from the last async call_tool. Returns the
            // GetResult payload ({status: pending|done|error, result?}).
            if (g_AsyncHandle.Length == 0) { resp["ok"] = false; resp["error"] = "no async handle"; return resp; }
            Json::Value h = Json::Object();
            h["request_id"] = g_AsyncHandle;
            resp["ok"] = true;
            resp["result"] = TmMcp::CallTool("GetResult", h);
            return resp;
        }
        if (op == "get_cam") {
            // Verification helper: current editor camera target via the MCP
            // surface (works regardless of which camera tool moved it).
            resp["ok"] = true;
            Json::Value empty = Json::Object();
            Json::Value@ cam = TmMcp::CallTool("GetEditorCamera", empty);
            if (cam !is null && cam.HasKey("success") && bool(cam["success"])) {
                resp["cam"] = cam;
            } else {
                resp["ok"] = false;
                resp["error"] = cam is null ? "GetEditorCamera returned null" : Json::Write(cam);
            }
            return resp;
        }
        if (op == "focus_click") {
            // Verification helper: simulate the eye-button click on the most
            // recent tool call that has a focusable position. Returns the
            // focus result so the driver can assert camera movement.
            resp["ok"] = true;
            for (int i = int(AgentUI::g_Messages.Length) - 1; i >= 0; i--) {
                auto m = AgentUI::g_Messages[i];
                if (m.type == AgentUI::MsgType::ToolCall && ToolFocus::ToolHasFocusTarget(m.toolName)) {
                    string err = ToolFocus::FocusOnToolCall(m.toolName, m.content);
                    resp["tool"] = m.toolName;
                    resp["error"] = err;
                    resp["focusCount"] = ToolFocus::g_FocusCount;
                    return resp;
                }
            }
            resp["error"] = "no focusable tool call in history";
            return resp;
        }
        if (op == "set_scroll_sim") {
            // Crash-repro harness: simulate a scroll position to force cull
            // conditions in DrawMessages without real input. -1 = real.
            AgentUI::g_ForceScrollY = req.HasKey("value") ? float(req["value"]) : -1.0;
            resp["ok"] = true;
            resp["forced"] = AgentUI::g_ForceScrollY;
            return resp;
        }

        resp["ok"] = false;
        resp["error"] = "unknown op: " + op;
        return resp;
    }
}
