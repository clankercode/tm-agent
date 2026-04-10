namespace AgentSettings {
    [Setting category="API" name="MiniMax"]
    string S_MiniMaxApiKey = "";

    [Setting category="API" name="MiniMax Model"]
    string S_MiniMaxModel = "mini-max-01";

    [Setting category="API" name="OpenAI Key"]
    string S_OpenAIApiKey = "";

    [Setting category="API" name="OpenAI Model"]
    string S_OpenAIModel = "gpt-4o";

    [Setting category="API" name="Provider"]
    string S_Provider = "minimax";

    [Setting category="General" name="Max History Tokens"]
    int S_MaxHistoryTokens = 120000;
}
