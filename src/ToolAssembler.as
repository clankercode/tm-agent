import Json::Value@ PlaceBlock(Json::Value &in input) from "McpTM";
import Json::Value@ RemoveBlock(Json::Value &in input) from "McpTM";
import Json::Value@ GetCursor(Json::Value &in input) from "McpTM";
import Json::Value@ GetMapInfo(Json::Value &in input) from "McpTM";
import Json::Value@ GetBlocks(Json::Value &in input) from "McpTM";
import Json::Value@ GetItems(Json::Value &in input) from "McpTM";
import Json::Value@ GetBlockAt(Json::Value &in input) from "McpTM";
import Json::Value@ GetPickedBlock(Json::Value &in input) from "McpTM";
import Json::Value@ GetPlacementMode(Json::Value &in input) from "McpTM";
import Json::Value@ GetEditMode(Json::Value &in input) from "McpTM";
import Json::Value@ Undo(Json::Value &in input) from "McpTM";
import Json::Value@ Redo(Json::Value &in input) from "McpTM";
import Json::Value@ TestMap(Json::Value &in input) from "McpTM";
import Json::Value@ SaveMap(Json::Value &in input) from "McpTM";
import Json::Value@ GetResult(Json::Value &in input) from "McpTM";
import Json::Value@ SetCursorBlock(Json::Value &in input) from "McpTM";
import Json::Value@ SetCursorItem(Json::Value &in input) from "McpTM";
import Json::Value@ GetRaceData(Json::Value &in input) from "McpTM";
import Json::Value@ GetPlayers(Json::Value &in input) from "McpTM";
import Json::Value@ GetMode(Json::Value &in input) from "McpTM";
import Json::Value@ GetServerInfo(Json::Value &in input) from "McpTM";

namespace ToolAssembler {
    Json::Value@ GetToolList() {
        Json::Value tools = Json::Array();
        
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

    void AddTool(Json::Value &in tools, const string &in name, const string &in desc, const string &in inputSchemaJson) {
        Json::Value tool = Json::Object();
        tool["name"] = name;
        tool["description"] = desc;
        tool["input_schema"] = Json::Parse(inputSchemaJson);
        tools.Add(tool);
    }

    Json::Value@ ParseToolCalls(const Json::Value &in response) {
        Json::Value toolCalls = Json::Array();
        
        if (response.HasKey("content")) {
            auto content = response["content"];
            if (content.GetType() == Json::Type::Array) {
                for (uint i = 0; i < content.Size(); i++) {
                    auto &block = content[i];
                    if (block.HasKey("type") && string(block["type"]) == "tool_use") {
                        Json::Value tc = Json::Object();
                        tc["name"] = string(block["name"]);
                        tc["input"] = Json::Parse(string(block["input"]));
                        tc["id"] = block.HasKey("id") ? string(block["id"]) : "call_" + i;
                        toolCalls.Add(tc);
                    }
                }
            }
        }
        
        else if (response.HasKey("choices")) {
            auto choices = response["choices"];
            if (choices.Size() > 0) {
                auto &msg = choices[0]["message"];
                if (msg.HasKey("tool_calls")) {
                    auto &tcs = msg["tool_calls"];
                    for (uint i = 0; i < tcs.Size(); i++) {
                        auto &tc = tcs[i];
                        Json::Value item = Json::Object();
                        item["name"] = string(tc["function"]["name"]);
                        item["input"] = Json::Parse(string(tc["function"]["arguments"]));
                        item["id"] = string(tc["id"]);
                        toolCalls.Add(item);
                    }
                }
            }
        }
        
        return toolCalls;
    }

    Json::Value@ ExecuteToolCall(const Json::Value &in toolCall) {
        string name = string(toolCall["name"]);
        auto &input = toolCall["input"];
        
        if (name == "PlaceBlock") return PlaceBlock(input);
        else if (name == "RemoveBlock") return RemoveBlock(input);
        else if (name == "GetCursor") return GetCursor(input);
        else if (name == "GetMapInfo") return GetMapInfo(input);
        else if (name == "GetBlocks") return GetBlocks(input);
        else if (name == "GetItems") return GetItems(input);
        else if (name == "GetBlockAt") return GetBlockAt(input);
        else if (name == "GetPickedBlock") return GetPickedBlock(input);
        else if (name == "GetPlacementMode") return GetPlacementMode(input);
        else if (name == "GetEditMode") return GetEditMode(input);
        else if (name == "Undo") return Undo(input);
        else if (name == "Redo") return Redo(input);
        else if (name == "TestMap") return TestMap(input);
        else if (name == "SaveMap") return SaveMap(input);
        else if (name == "GetResult") return GetResult(input);
        else if (name == "SetCursorBlock") return SetCursorBlock(input);
        else if (name == "SetCursorItem") return SetCursorItem(input);
        else if (name == "GetRaceData") return GetRaceData(input);
        else if (name == "GetPlayers") return GetPlayers(input);
        else if (name == "GetMode") return GetMode(input);
        else if (name == "GetServerInfo") return GetServerInfo(input);
        
        Json::Value err = Json::Object();
        err["success"] = false;
        err["error"] = "unknown tool: " + name;
        return err;
    }

    string GetToolResultJson(const Json::Value &in result) {
        return Json::Stringify(result);
    }
}
