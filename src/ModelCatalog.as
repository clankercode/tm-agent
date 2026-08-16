// Model catalog for the settings UI: fetches the /models list from the
// configured provider (where supported), looks up model metadata from the
// models.dev cache (via ai-api), and auto-populates model-dependent
// settings (max output tokens, reasoning effort, context budget).
//
// UI stays in ChatUI; this module owns state + coroutines. All network
// work happens in coroutines started via StartFetchCatalogCoro.

namespace ModelCatalog {

string _pendingModelSelection = "";

// catalog id -> sorted model ids. Persisted only in memory; refetched on
// demand (TTL'd for models.dev but direct API listings are on-demand).
dictionary g_Catalogs;
uint g_FetchRunningCount = 0;

bool IsFetching() {
    return g_FetchRunningCount > 0;
}

// ---------------------------------------------------------------------------
// models.dev-backed metadata for the current provider+model
// ---------------------------------------------------------------------------

// Provider id used for models.dev lookups for each agent provider.
string ModelsDevProviderFor(Provider p) {
    switch (p) {
        case Provider::MiniMax: return "minimax";
        case Provider::OpenAI: return "openai";
        case Provider::CustomAnthropic: return "anthropic";
        case Provider::CustomOpenAI: return ""; // unknown host — try Any
    }
    return "";
}

class ModelMeta {
    string model;
    int contextTokens = 0;
    int outputTokens = 0;
    bool reasoning = false;
    bool known = false;
}

ModelMeta@ CurrentModelMeta() {
    ModelMeta meta;
    meta.model = AgentSettings::CurrentModel();
    Json::Value@ entry = null;
    string pid = ModelsDevProviderFor(AgentSettings::S_Provider);
    if (pid.Length > 0) {
        @entry = AiApi::LookupModelInfo(pid, meta.model);
    }
    if (entry is null) {
        @entry = AiApi::LookupModelInfoAny(meta.model);
    }
    if (entry !is null) {
        meta.known = true;
        if (entry.HasKey("limit") && entry["limit"].GetType() == Json::Type::Object) {
            Json::Value@ limit = entry["limit"];
            if (limit.HasKey("context")) meta.contextTokens = int(limit["context"]);
            if (limit.HasKey("output")) meta.outputTokens = int(limit["output"]);
        }
        if (entry.HasKey("reasoning") && entry["reasoning"].GetType() == Json::Type::Boolean) {
            meta.reasoning = bool(entry["reasoning"]);
        }
    }
    return meta;
}

// Apply models.dev metadata to agent settings: clamp the history budget to
// the model's context window and default the effort from reasoning_values.
void ApplyModelMetaToSettings() {
    ModelMeta@ meta = CurrentModelMeta();
    if (!meta.known) return;

    if (meta.contextTokens > 0) {
        int budget = int(Math::Min(int64(meta.contextTokens), int64(1000000)));
        AgentSettings::S_MaxHistoryTokens = budget;
    }
    if (meta.reasoning) {
        // Only set effort for providers that take one.
        string pid = ModelsDevProviderFor(AgentSettings::S_Provider);
        if (pid == "openai") {
            AgentSettings::S_OpenAIReasoningEffort = DefaultEffortFor(meta.model, "openai");
        } else if (AgentSettings::S_Provider == Provider::CustomOpenAI) {
            AgentSettings::S_CustomOpenAIReasoningEffort = DefaultEffortFor(meta.model, "custom-openai");
        }
    }
}

// Preferred effort for a reasoning model from models.dev reasoning_values.
string DefaultEffortFor(const string &in model, const string &in providerKey) {
    Json::Value@ entry = AiApi::LookupModelInfoAny(model);
    if (entry is null) return "high";
    if (!entry.HasKey("reasoning_values")) return "high";
    Json::Value@ values = entry["reasoning_values"];
    array<string> vals;
    for (uint i = 0; i < values.Length; i++) vals.InsertLast(string(values[i]));
    // "high" if listed, else the middle entry, else the last.
    for (uint i = 0; i < vals.Length; i++) {
        if (vals[i] == "high") return "high";
    }
    if (vals.Length > 0) return vals[vals.Length / 2];
    return "high";
}

// Effort options for the effort combo: models.dev reasoning_values for
// the current model when known, else the classic list.
array<string> EffortChoicesFor(const string &in providerKey) {
    string model = AgentSettings::CurrentModel();
    Json::Value@ entry = AiApi::LookupModelInfoAny(model);
    array<string> choices;
    if (entry !is null && entry.HasKey("reasoning_values")) {
        Json::Value@ values = entry["reasoning_values"];
        for (uint i = 0; i < values.Length; i++) {
            choices.InsertLast(string(values[i]));
        }
        if (choices.Length > 0) return choices;
    }
    choices = { "none", "minimal", "low", "medium", "high", "xhigh", "max" };
    return choices;
}

// ---------------------------------------------------------------------------
// Direct API model listing (custom providers, openai /models)
// ---------------------------------------------------------------------------

class FetchCatalogRequest {
    string catalogId;
    bool anthropicShape;
    string apiKey;
    string baseUrl;
}

array<string>@ GetCatalog(const string &in catalogId) {
    array<string>@ models = null;
    if (g_Catalogs.Get(catalogId, @models)) {
        return models;
    }
    return null;
}

void SetCatalog(const string &in catalogId, array<string>@ models) {
    g_Catalogs.Set(catalogId, models);
}

// Start a background fetch of the model list for the given provider
// config. Retries are gated by a config fingerprint (baseUrl + key
// length): one attempt per distinct config, so a failing endpoint
// (mid-typed URL, unreachable host) produces one attempt per edit
// instead of one per UI frame. Editing the base URL or key re-arms it.
void StartFetchCatalog(const string &in catalogId, bool anthropicShape, const string &in apiKey, const string &in baseUrl) {
    array<string>@ existing = GetCatalog(catalogId);
    if (existing !is null) return; // success already cached for this session
    string fingerprint = baseUrl + "\n" + apiKey.Length;
    string attemptedFingerprint;
    if (_fetchAttempted.Get(catalogId, attemptedFingerprint)) {
        if (attemptedFingerprint == fingerprint) return; // tried this exact config already
    }
    auto req = FetchCatalogRequest();
    req.catalogId = catalogId;
    req.anthropicShape = anthropicShape;
    req.apiKey = apiKey;
    req.baseUrl = baseUrl;
    g_FetchRunningCount++;
    startnew(CoroutineFuncUserdata(FetchCatalogCoro), req);
}

void FetchCatalogCoro(ref@ requestRef) {
    FetchCatalogRequest@ req = cast<FetchCatalogRequest>(requestRef);
    if (req is null) {
        g_FetchRunningCount--;
        return;
    }
    array<string> models;
    string error;
    if (req.anthropicShape) {
        Json::Value@ ids = AiApi::ListCustomAnthropicModels(req.apiKey, req.baseUrl, error);
        for (uint i = 0; i < ids.Length; i++) models.InsertLast(string(ids[i]));
    } else {
        Json::Value@ ids = AiApi::ListCustomOpenAIModels(req.apiKey, req.baseUrl, error);
        for (uint i = 0; i < ids.Length; i++) models.InsertLast(string(ids[i]));
    }
    if (models.Length > 0) {
        // Alphabetical order for a stable, greppable combo.
        for (uint i = 0; i < models.Length; i++) {
            uint best = i;
            for (uint j = i + 1; j < models.Length; j++) {
                if (models[j] < models[best]) best = j;
            }
            if (best != i) {
                string tmp = models[i];
                models[i] = models[best];
                models[best] = tmp;
            }
        }
        SetCatalog(req.catalogId, models);
        print("[tm-agent] catalog " + req.catalogId + ": " + models.Length + " models");
    } else {
        // Zero models with or without an error — note the attempt either
        // way so StartFetchCatalog can distinguish "not tried yet" from
        // "tried and listing unsupported/empty".
        NoteFetchAttempted(req.catalogId, req.baseUrl + "\n" + req.apiKey.Length);
        if (error.Length > 0) {
            print("[tm-agent] catalog " + req.catalogId + " fetch failed: " + error);
        } else {
            print("[tm-agent] catalog " + req.catalogId + ": endpoint returned no models");
        }
    }
    g_FetchRunningCount--;
}

void ClearCatalog(const string &in catalogId) {
    g_Catalogs.Delete(catalogId);
    _fetchAttempted.Delete(catalogId);
}

dictionary _fetchAttempted;

// Record the config fingerprint that was just attempted so
// StartFetchCatalog can avoid re-trying the same failing config every
// frame.
void NoteFetchAttempted(const string &in catalogId, const string &in fingerprint) {
    _fetchAttempted.Set(catalogId, fingerprint);
}

}
