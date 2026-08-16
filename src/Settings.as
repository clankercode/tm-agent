enum Provider {
    MiniMax = 0,
    OpenAI = 1,
    CustomOpenAI = 2,
    CustomAnthropic = 3
}

namespace AgentSettings {

    [Setting category="API" name="MiniMax" password]
    string S_MiniMaxApiKey = "";

    [Setting category="API" name="MiniMax Model"]
    string S_MiniMaxModel = "MiniMax-M2.7";

    [Setting category="API" name="OpenAI Key" password]
    string S_OpenAIApiKey = "";

    [Setting category="API" name="OpenAI Model"]
    string S_OpenAIModel = "gpt-5.4-mini";

    [Setting category="API" name="OpenAI Effort"]
    string S_OpenAIReasoningEffort = "high";

    [Setting category="API" name="Custom OpenAI Base URL"]
    string S_CustomOpenAIBaseUrl = "";

    [Setting category="API" name="Custom OpenAI Key" password]
    string S_CustomOpenAIApiKey = "";

    [Setting category="API" name="Custom OpenAI Model"]
    string S_CustomOpenAIModel = "";

    [Setting category="API" name="Custom OpenAI Effort"]
    string S_CustomOpenAIReasoningEffort = "high";

    [Setting category="API" name="Custom Anthropic Base URL"]
    string S_CustomAnthropicBaseUrl = "";

    [Setting category="API" name="Custom Anthropic Key" password]
    string S_CustomAnthropicApiKey = "";

    [Setting category="API" name="Custom Anthropic Model"]
    string S_CustomAnthropicModel = "";

    [Setting category="API" name="Provider"]
    Provider S_Provider = Provider::MiniMax;

    [Setting category="General" name="Max History Tokens"]
    int S_MaxHistoryTokens = 120000;

    [Setting category="General" name="Compact Button Threshold (tokens)" description="Show the Compact button once used context passes this threshold" min="4000" max="200000"]
    int S_CompactButtonThreshold = 50000;

    [Setting category="UI" name="Show Window"]
    bool S_ShowWindow = true;

    // ------------------------------------------------------------------
    // Provider helpers — shared by AgentLoop, LlmHistory, ChatUI, tests.
    // ------------------------------------------------------------------

    bool ProviderUsesAnthropicShape(Provider p) {
        return p == Provider::MiniMax || p == Provider::CustomAnthropic;
    }

    string CurrentApiKey() {
        switch (S_Provider) {
            case Provider::MiniMax:
                return S_MiniMaxApiKey;
            case Provider::OpenAI:
                return S_OpenAIApiKey;
            case Provider::CustomOpenAI:
                return S_CustomOpenAIApiKey;
            case Provider::CustomAnthropic:
                return S_CustomAnthropicApiKey;
        }
        return "";
    }

    string CurrentModel() {
        switch (S_Provider) {
            case Provider::MiniMax:
                return S_MiniMaxModel;
            case Provider::OpenAI:
                return S_OpenAIModel;
            case Provider::CustomOpenAI:
                return S_CustomOpenAIModel;
            case Provider::CustomAnthropic:
                return S_CustomAnthropicModel;
        }
        return "";
    }

    string CurrentReasoningEffort() {
        switch (S_Provider) {
            case Provider::OpenAI:
                return S_OpenAIReasoningEffort;
            case Provider::CustomOpenAI:
                return S_CustomOpenAIReasoningEffort;
        }
        return "";
    }

    string CurrentProviderLabel() {
        switch (S_Provider) {
            case Provider::MiniMax: return "minimax";
            case Provider::OpenAI: return "openai";
            case Provider::CustomOpenAI: return "custom-openai";
            case Provider::CustomAnthropic: return "custom-anthropic";
        }
        return "unknown";
    }
}
