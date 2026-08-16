// ToolImages.as — multimodal screenshot support.
//
// When the agent calls TakeScreenshot (or any tool whose result carries a
// screenshot path), this module:
//   1. renders the image in the chatlog (texture cache, capped), and
//   2. appends a follow-up user message containing the image as a data-URL
//      content part, so multimodal models can actually see the screenshot.
//
// Wire shapes (OpenAI chat-completions style):
//   { role:"user", image_part:true, content: [
//       { type:"text", text:"..." },
//       { type:"image_url", image_url:{ url:"data:image/jpeg;base64,..." } } ] }
// ai-api's ConvertMessagesForChat passes content through verbatim, so this
// reaches vision-capable providers unchanged. The Anthropic converter in
// LlmHistory maps it to { type:"image", source:{ type:"base64", ... } }.
//
// Base64 payloads are never persisted to the session log (path + size only)
// and are dropped from older messages when the texture/text cache caps hit.

namespace ToolImages {

    // Flat estimate per image part (vision models charge a flat tile cost,
    // nowhere near the raw base64 byte count).
    const int IMAGE_TOKEN_ALLOWANCE = 2000;

    // Live UI texture cap. Older chips degrade to a text note.
    const uint MAX_TEXTURES = 16;

    class Entry {
        string path;          // absolute file path (session-log + dedup key)
        string mediaType;     // "jpeg" | "png" | "webp"
        string base64;        // encoded payload for the LLM
        UI::Texture@ texture; // null until first draw or if capped/failed
        int w = 0;
        int h = 0;
    }

    array<Entry@> g_Entries;

    // ------------------------------------------------------------------
    // Result -> image descriptor
    // ------------------------------------------------------------------

    // Returns the screenshot file path from a TakeScreenshot-shaped result
    // (accepts both the nested {ok, output:{fullName}} and flat shapes).
    // Empty for non-screenshot results.
    string ExtractScreenshotPath(Json::Value@ result) {
        if (result is null || result.GetType() != Json::Type::Object) return "";
        if (result.HasKey("error")) return "";
        Json::Value@ node = result;
        if (node.HasKey("output") && node["output"].GetType() == Json::Type::Object
            && node["output"].HasKey("fullName")) {
            @node = node["output"];
        }
        if (!node.HasKey("fullName")) return "";
        string path = string(node["fullName"]);
        if (path.Length == 0) return "";
        string lower = path.ToLower();
        if (!(lower.EndsWith(".jpg") || lower.EndsWith(".jpeg") || lower.EndsWith(".png")
            || lower.EndsWith(".webp"))) {
            return "";
        }
        return path;
    }

    string MediaTypeForPath(const string &in path) {
        string lower = path.ToLower();
        if (lower.EndsWith(".png")) return "png";
        if (lower.EndsWith(".webp")) return "webp";
        return "jpeg";
    }

    // ------------------------------------------------------------------
    // LLM message building
    // ------------------------------------------------------------------

    bool ShouldSendImageToModel() {
        return AgentSettings::S_SendToolImages;
    }

    // Data-URL content part for OpenAI-shape requests.
    Json::Value@ BuildImageUrlPart(const string &in mediaType, const string &in base64) {
        Json::Value@ part = Json::Object();
        part["type"] = "image_url";
        Json::Value@ imageUrl = Json::Object();
        imageUrl["url"] = "data:image/" + mediaType + ";base64," + base64;
        part["image_url"] = imageUrl;
        return part;
    }

    Json::Value@ BuildImageUserMessage(const string &in caption, const string &in mediaType, const string &in base64) {
        Json::Value@ msg = Json::Object();
        msg["role"] = "user";
        msg["image_part"] = true;
        msg["tool_name"] = "TakeScreenshot";
        Json::Value@ content = Json::Array();
        Json::Value@ text = Json::Object();
        text["type"] = "text";
        text["text"] = caption;
        content.Add(text);
        content.Add(BuildImageUrlPart(mediaType, base64));
        msg["content"] = content;
        return msg;
    }

    // Anthropic content block for the same image.
    Json::Value@ BuildAnthropicImageBlock(const string &in mediaType, const string &in base64) {
        Json::Value@ block = Json::Object();
        block["type"] = "image";
        Json::Value@ source = Json::Object();
        source["type"] = "base64";
        source["media_type"] = "image/" + mediaType;
        source["data"] = base64;
        block["source"] = source;
        return block;
    }

    // ------------------------------------------------------------------
    // Loading + texture cache
    // ------------------------------------------------------------------

    // Reads the file into base64 (STANDARD alphabet — providers reject the
    // URL-safe variant ReadToBase64(size, true) emits: / and + become _ and -).
    string ReadBase64(const string &in path) {
        if (!IO::FileExists(path)) return "";
        IO::File f(path, IO::FileMode::Read);
        uint64 sz = f.Size();
        if (sz == 0 || sz > 12582912) return "";
        MemoryBuffer@ buf = f.Read(sz);
        if (buf is null) return "";
        buf.Seek(0);
        return buf.ReadToBase64(buf.GetSize(), false);
    }

    // Registers a screenshot in the chatlog. Returns the Entry (texture may
    // still be null if capped — the chip renders a note instead).
    Entry@ RegisterForChat(const string &in path) {
        // Dedup on path.
        for (uint i = 0; i < g_Entries.Length; i++) {
            if (g_Entries[i].path == path) return g_Entries[i];
        }
        Entry@ e = Entry();
        e.path = path;
        e.mediaType = MediaTypeForPath(path);
        if (g_Entries.Length < MAX_TEXTURES) {
            @e.texture = LoadTextureFromPath(path);
            if (e.texture !is null) {
                e.w = int(e.texture.GetSize().x);
                e.h = int(e.texture.GetSize().y);
            }
        }
        g_Entries.InsertLast(e);
        return e;
    }

    UI::Texture@ LoadTextureFromPath(const string &in path) {
        if (!IO::FileExists(path)) return null;
        try {
            IO::File f(path, IO::FileMode::Read);
            MemoryBuffer@ buf = f.Read(f.Size());
            if (buf is null) return null;
            return UI::LoadTexture(buf);
        } catch {
            return null;
        }
    }

    // Finds the chat entry for a screenshot path (null if not registered).
    Entry@ FindEntry(const string &in path) {
        for (uint i = 0; i < g_Entries.Length; i++) {
            if (g_Entries[i].path == path) return g_Entries[i];
        }
        return null;
    }

    void ResetForTest() {
        g_Entries.RemoveRange(0, g_Entries.Length);
    }
}
