enum Provider {
    MiniMax = 0,
    OpenAI = 1
}

namespace AgentSettings {
    [Setting category="API" name="MiniMax"]
    string S_MiniMaxApiKey = "";

    [Setting category="API" name="MiniMax Model"]
    string S_MiniMaxModel = "MiniMax-M2.7";

    [Setting category="API" name="OpenAI Key"]
    string S_OpenAIApiKey = "";

    [Setting category="API" name="OpenAI Model"]
    string S_OpenAIModel = "gpt-5.4-mini";

    [Setting category="API" name="OpenAI Effort"]
    string S_OpenAIReasoningEffort = "high";

    [Setting category="API" name="Provider"]
    Provider S_Provider = Provider::MiniMax;

    [Setting category="General" name="Max History Tokens"]
    int S_MaxHistoryTokens = 120000;

    [Setting category="UI" name="Show Window"]
    bool S_ShowWindow = true;
}
