namespace AgentDriver {
    uint g_LastPollAt = 0;
    const uint POLL_INTERVAL_MS = 250;

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
            resp["status"] = AgentUI::g_Status;
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
            AgentUI::SendMessage(AgentUI::g_InputText);
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
            AgentUI::AddMessage(t, text);
            resp["ok"] = true;
            return resp;
        }
        if (op == "set_status") {
            if (!req.HasKey("status")) { resp["ok"] = false; resp["error"] = "status required"; return resp; }
            AgentUI::g_Status = string(req["status"]);
            resp["ok"] = true;
            return resp;
        }
        if (op == "seed_demo") {
            AgentUI::ClearMessages();
            AgentUI::AddMessage(AgentUI::MsgType::User, "What blocks are on the current map?");
            AgentUI::AddMessage(AgentUI::MsgType::Assistant, "The map has 247 blocks total. Most common:\n\n- RoadTechStraight x84\n- RoadDirtStraight x36\n- RoadBumpStraight x22\n\nWant me to list a specific type or region?");
            AgentUI::AddMessage(AgentUI::MsgType::User, "Place a start block at the cursor.");
            AgentUI::AddMessage(AgentUI::MsgType::Assistant, "Done. Placed RoadTechStart at (24, 12, 16) facing North.");
            resp["ok"] = true;
            return resp;
        }

        resp["ok"] = false;
        resp["error"] = "unknown op: " + op;
        return resp;
    }
}
