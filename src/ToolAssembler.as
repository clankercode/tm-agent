import Json::Value@ PlaceBlock(Json::Value@ input) from "McpTM";
import Json::Value@ RemoveBlock(Json::Value@ input) from "McpTM";
import Json::Value@ GetCursor(Json::Value@ input) from "McpTM";
import Json::Value@ GetMapInfo(Json::Value@ input) from "McpTM";
import Json::Value@ GetBlocks(Json::Value@ input) from "McpTM";
import Json::Value@ GetItems(Json::Value@ input) from "McpTM";
import Json::Value@ GetInventorySummary(Json::Value@ input) from "McpTM";
import Json::Value@ FindInventory(Json::Value@ input) from "McpTM";
import Json::Value@ GetBlockAt(Json::Value@ input) from "McpTM";
import Json::Value@ GetPickedBlock(Json::Value@ input) from "McpTM";
import Json::Value@ GetPlacementMode(Json::Value@ input) from "McpTM";
import Json::Value@ GetEditMode(Json::Value@ input) from "McpTM";
import Json::Value@ Undo(Json::Value@ input) from "McpTM";
import Json::Value@ Redo(Json::Value@ input) from "McpTM";
import Json::Value@ TestMap(Json::Value@ input) from "McpTM";
import Json::Value@ SaveMap(Json::Value@ input) from "McpTM";
import Json::Value@ GetResult(Json::Value@ input) from "McpTM";
import Json::Value@ SetCursorBlock(Json::Value@ input) from "McpTM";
import Json::Value@ SetCursorItem(Json::Value@ input) from "McpTM";
import Json::Value@ GetRaceData(Json::Value@ input) from "McpTM";
import Json::Value@ GetPlayers(Json::Value@ input) from "McpTM";
import Json::Value@ GetMode(Json::Value@ input) from "McpTM";
import Json::Value@ GetServerInfo(Json::Value@ input) from "McpTM";

namespace ToolAssembler {
    Json::Value@ GetToolList() {
        Json::Value@ tools = Json::Array();
        
        AddTool(tools, "PlaceBlock",
            "Place a block in the editor. Inputs: blockName (string), x, y, z (int coords), dir (North/East/South/West)",
            '{"type": "object", "properties": {"blockName": {"type": "string"}, "x": {"type": "integer"}, "y": {"type": "integer"}, "z": {"type": "integer"}, "dir": {"type": "string", "enum": ["North", "East", "South", "West"]}}, "required": ["blockName", "x", "y", "z", "dir"]}'
        );
        
        AddTool(tools, "RemoveBlock",
            "Remove a block at coord. Inputs: x, y, z (int coords)",
            '{"type": "object", "properties": {"x": {"type": "integer"}, "y": {"type": "integer"}, "z": {"type": "integer"}}, "required": ["x", "y", "z"]}'
        );
        
        AddTool(tools, "GetCursor",
            "Get the cursor position, direction, and picked block/item",
            '{"type": "object", "properties": {}}'
        );
        
        AddTool(tools, "GetMapInfo",
            "Get map name and object counts",
            '{"type": "object", "properties": {}}'
        );
        
        AddTool(tools, "GetBlocks",
            "Get blocks near a point. Inputs: x, y, z (int coords), radius (int), filter (all/classic/ghost/terrain)",
            '{"type": "object", "properties": {"x": {"type": "integer"}, "y": {"type": "integer"}, "z": {"type": "integer"}, "radius": {"type": "integer"}, "filter": {"type": "string"}}, "required": ["x", "y", "z", "radius", "filter"]}'
        );
        
        AddTool(tools, "GetItems",
            "Get items near a point. Inputs: x, y, z (float coords), radius (float)",
            '{"type": "object", "properties": {"x": {"type": "number"}, "y": {"type": "number"}, "z": {"type": "number"}, "radius": {"type": "number"}}, "required": ["x", "y", "z", "radius"]}'
        );

        AddTool(tools, "GetInventorySummary",
            "Summarize the current inventory tree, current directory, and selected node.",
            '{"type": "object", "properties": {}}'
        );

        AddTool(tools, "FindInventory",
            "Search the inventory tree by query. Inputs: query (optional), type (all/directory/article), scope (all/currentDirectory), limit (optional).",
            '{"type": "object", "properties": {"query": {"type": "string"}, "type": {"type": "string", "enum": ["all", "directory", "article"]}, "scope": {"type": "string", "enum": ["all", "currentDirectory", "current"]}, "limit": {"type": "integer"}}, "required": []}'
        );
        
        AddTool(tools, "GetBlockAt",
            "Get block info at exact coord. Inputs: x, y, z",
            '{"type": "object", "properties": {"x": {"type": "integer"}, "y": {"type": "integer"}, "z": {"type": "integer"}}, "required": ["x", "y", "z"]}'
        );
        
        AddTool(tools, "GetPickedBlock",
            "Get the currently selected block at the cursor",
            '{"type": "object", "properties": {}}'
        );
        
        AddTool(tools, "GetPlacementMode",
            "Get current placement mode (Block/Item/Macroblock/etc)",
            '{"type": "object", "properties": {}}'
        );
        
        AddTool(tools, "GetEditMode",
            "Get current edit mode (Place/Erase/Pick/etc)",
            '{"type": "object", "properties": {}}'
        );
        
        AddTool(tools, "Undo",
            "Undo last editor action",
            '{"type": "object", "properties": {}}'
        );
        
        AddTool(tools, "Redo",
            "Redo last undone action",
            '{"type": "object", "properties": {}}'
        );
        
        AddTool(tools, "TestMap",
            "Test the map. Inputs: modeName (optional, e.g. TM_Race or empty for default). Returns a request_id - poll GetResult.",
            '{"type": "object", "properties": {"modeName": {"type": "string"}}, "required": []}'
        );
        
        AddTool(tools, "SaveMap",
            "Save the map. Inputs: fileName (optional, defaults to Autosave). Returns a request_id - poll GetResult.",
            '{"type": "object", "properties": {"fileName": {"type": "string"}}, "required": []}'
        );
        
        AddTool(tools, "GetResult",
            "Poll for async operation result. Inputs: requestId (from TestMap/SaveMap)",
            '{"type": "object", "properties": {"requestId": {"type": "string"}}, "required": ["requestId"]}'
        );
        
        AddTool(tools, "SetCursorBlock",
            "Set the cursor's selected block. Inputs: blockName",
            '{"type": "object", "properties": {"blockName": {"type": "string"}}, "required": ["blockName"]}'
        );
        
        AddTool(tools, "SetCursorItem",
            "Set the cursor's selected item. Inputs: itemName",
            '{"type": "object", "properties": {"itemName": {"type": "string"}}, "required": ["itemName"]}'
        );
        
        AddTool(tools, "GetRaceData",
            "Get current race data (players, times, checkpoints)",
            '{"type": "object", "properties": {}}'
        );
        
        AddTool(tools, "GetPlayers",
            "Get list of players with CP info",
            '{"type": "object", "properties": {}}'
        );
        
        AddTool(tools, "GetMode",
            "Get current mode (Editor/Race/Spectator/Menu/Unknown)",
            '{"type": "object", "properties": {}}'
        );
        
        AddTool(tools, "GetServerInfo",
            "Get server name and player count",
            '{"type": "object", "properties": {}}'
        );
        
        return tools;
    }

    void AddTool(Json::Value@ tools, const string &in name, const string &in desc, const string &in inputSchemaJson) {
        Json::Value tool = Json::Object();
        tool["name"] = name;
        tool["description"] = desc;
        tool["input_schema"] = Json::Parse(inputSchemaJson);
        tools.Add(tool);
    }

    array<Json::Value@> ParseToolCalls(const Json::Value &in response) {
        array<Json::Value@> toolCalls;
        
        if (response.HasKey("content")) {
            auto content = response["content"];
            if (content.GetType() == Json::Type::Array) {
                for (uint i = 0; i < content.Length; i++) {
                    const Json::Value@ block = content[i];
                    if (block !is null && block.HasKey("type") && string(block["type"]) == "tool_use") {
                        Json::Value tc = Json::Object();
                        tc["name"] = string(block["name"]);
                        tc["input"] = Json::Parse(string(block["input"]));
                        tc["id"] = block.HasKey("id") ? string(block["id"]) : "call_" + i;
                        toolCalls.InsertLast(tc);
                    }
                }
            }
        }
        
        else if (response.HasKey("choices")) {
            auto choices = response["choices"];
            if (choices.GetType() == Json::Type::Array && choices.Length > 0) {
                const Json::Value@ msg = choices[0]["message"];
                if (msg.HasKey("tool_calls")) {
                    const Json::Value@ tcs = msg["tool_calls"];
                    for (uint i = 0; i < tcs.Length; i++) {
                        const Json::Value@ tc = tcs[i];
                        Json::Value item = Json::Object();
                        item["name"] = string(tc["function"]["name"]);
                        item["input"] = Json::Parse(string(tc["function"]["arguments"]));
                        item["id"] = string(tc["id"]);
                        toolCalls.InsertLast(item);
                    }
                }
            }
        }
        
        return toolCalls;
    }

    bool IsFocusableTool(const string &in name) {
        return name == "PlaceBlock"
            || name == "RemoveBlock"
            || name == "GetBlockAt";
    }

    Json::Value@ ExecuteToolCall(Json::Value@ toolCall) {
        string name = string(toolCall["name"]);
        Json::Value@ input = toolCall["input"];
        Json::Value@ result;

        if (name == "PlaceBlock") @result = PlaceBlock(input);
        else if (name == "RemoveBlock") @result = RemoveBlock(input);
        else if (name == "GetCursor") @result = GetCursor(input);
        else if (name == "GetMapInfo") @result = GetMapInfo(input);
        else if (name == "GetBlocks") @result = GetBlocks(input);
        else if (name == "GetItems") @result = GetItems(input);
        else if (name == "GetInventorySummary") @result = GetInventorySummary(input);
        else if (name == "FindInventory") @result = FindInventory(input);
        else if (name == "GetBlockAt") @result = GetBlockAt(input);
        else if (name == "GetPickedBlock") @result = GetPickedBlock(input);
        else if (name == "GetPlacementMode") @result = GetPlacementMode(input);
        else if (name == "GetEditMode") @result = GetEditMode(input);
        else if (name == "Undo") @result = Undo(input);
        else if (name == "Redo") @result = Redo(input);
        else if (name == "TestMap") @result = TestMap(input);
        else if (name == "SaveMap") @result = SaveMap(input);
        else if (name == "GetResult") @result = GetResult(input);
        else if (name == "SetCursorBlock") @result = SetCursorBlock(input);
        else if (name == "SetCursorItem") @result = SetCursorItem(input);
        else if (name == "GetRaceData") @result = GetRaceData(input);
        else if (name == "GetPlayers") @result = GetPlayers(input);
        else if (name == "GetMode") @result = GetMode(input);
        else if (name == "GetServerInfo") @result = GetServerInfo(input);
        else {
            Json::Value err = Json::Object();
            err["success"] = false;
            err["error"] = "unknown tool: " + name;
            return err;
        }

        if (IsFocusableTool(name) && result !is null) {
            CameraFocus::TryFocusFromResult(result, input);
        }
        return result;
    }

    string GetToolResultJson(const Json::Value &in result) {
        return Json::Write(result);
    }

    string GetEditorStateSnapshot() {
        string state = "EDITOR STATE:\n";

        Json::Value@ empty = Json::Object();

        Json::Value@ mapInfo = GetMapInfo(empty);
        if (mapInfo !is null && mapInfo.HasKey("output")) {
            Json::Value@ mapOut = mapInfo["output"];
            string mapName = mapOut.HasKey("name") ? string(mapOut["name"]) : "unknown";
            string nbBlocks = mapOut.HasKey("nbBlocks") ? string(mapOut["nbBlocks"]) : "?";
            string nbItems = mapOut.HasKey("nbItems") ? string(mapOut["nbItems"]) : "?";
            state += "- Map: " + mapName + " (" + nbBlocks + " blocks, " + nbItems + " items)\n";
        }

        Json::Value@ cursor = GetCursor(empty);
        if (cursor !is null && cursor.HasKey("output")) {
            Json::Value@ curOut = cursor["output"];
            string coord = curOut.HasKey("coord") ? Json::Write(curOut["coord"]) : "[?]";
            string dir = curOut.HasKey("dir") ? string(curOut["dir"]) : "?";
            string pickedBlock = "!";
            string pickedItem = "!";
            if (curOut.HasKey("pickedBlock") && curOut["pickedBlock"].GetType() != Json::Type::Null) {
                pickedBlock = string(curOut["pickedBlock"]);
            }
            if (curOut.HasKey("pickedItem") && curOut["pickedItem"].GetType() != Json::Type::Null) {
                pickedItem = string(curOut["pickedItem"]);
            }
            state += "- Cursor: " + coord + " dir=" + dir + " pickedBlock=" + pickedBlock + " pickedItem=" + pickedItem + "\n";
        }

        Json::Value@ placement = GetPlacementMode(empty);
        if (placement !is null && placement.HasKey("output")) {
            Json::Value@ placeOut = placement["output"];
            if (placeOut.HasKey("mode")) {
                state += "- Placement mode: " + string(placeOut["mode"]) + "\n";
            }
        }

        Json::Value@ inv = GetInventorySummary(empty);
        if (inv !is null && inv.HasKey("output")) {
            Json::Value@ invOut = inv["output"];
            string invStatus = "unknown";
            string currentDir = "";
            string selectedNode = "";
            if (invOut.HasKey("loadingStatusShort")) {
                invStatus = string(invOut["loadingStatusShort"]);
            }
            if (invOut.HasKey("currentDirectoryPath")) {
                currentDir = string(invOut["currentDirectoryPath"]);
            }
            if (invOut.HasKey("currentSelectedNode") && invOut["currentSelectedNode"].GetType() != Json::Type::Null) {
                Json::Value@ selNode = invOut["currentSelectedNode"];
                if (selNode.HasKey("path")) {
                    selectedNode = string(selNode["path"]);
                }
            }
            state += "- Inventory: " + invStatus;
            if (currentDir.Length > 0) state += " dir=" + currentDir;
            if (selectedNode.Length > 0) state += " selected=" + selectedNode;
            state += "\n";
        }

        return state.Trim();
    }
}
