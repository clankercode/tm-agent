enum Provider {
    MiniMax = 0,
    OpenAI = 1
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

    [Setting category="API" name="Provider"]
    Provider S_Provider = Provider::MiniMax;

    [Setting category="General" name="Max History Tokens"]
    int S_MaxHistoryTokens = 120000;

    [Setting category="General" name="Compact Button Threshold (tokens)" description="Show the Compact button once used context passes this threshold" min="4000" max="200000"]
    int S_CompactButtonThreshold = 50000;

    [Setting category="UI" name="Show Window"]
    bool S_ShowWindow = true;
}
