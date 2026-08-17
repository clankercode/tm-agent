namespace AgentStats {
    [Setting category="Stats" name="Total input tokens" hidden]
    int S_TotalInputTokens = 0;

    [Setting category="Stats" name="Total cached read tokens" hidden]
    int S_TotalCachedReadTokens = 0;

    [Setting category="Stats" name="Total cache write tokens" hidden]
    int S_TotalCacheWriteTokens = 0;

    [Setting category="Stats" name="Total output tokens" hidden]
    int S_TotalOutputTokens = 0;

    [Setting category="Stats" name="Total user messages" hidden]
    int S_TotalUserMessages = 0;

    [Setting category="Stats" name="Total turns" hidden]
    int S_TotalTurns = 0;

    [Setting category="Stats" name="Total steps" hidden]
    int S_TotalSteps = 0;

    [Setting category="Stats" name="Total blocks placed" hidden]
    int S_TotalBlocksPlaced = 0;

    [Setting category="Stats" name="Total blocks removed" hidden]
    int S_TotalBlocksRemoved = 0;

    // Test-mode suspend latch: while >0, every Record* and ResetAll is a
    // no-op so unit tests and DEV session fixtures never touch the user's
    // persisted lifetime counters (they are Openplanet [Setting]s — writes
    // hit disk). Depth-counted so nested suspends unwind correctly.
    int g_SuspendCount = 0;

    void SuspendRecording() { g_SuspendCount++; }
    void ResumeRecording() { if (g_SuspendCount > 0) g_SuspendCount--; }
    bool RecordingSuspended() { return g_SuspendCount > 0; }

    // cachedRead/cacheWrite are the prompt-cache split of the request's input
    // tokens (ai-api normalizes both provider shapes). Defaulted so existing
    // two-arg callers keep compiling.
    void RecordTokens(int inTok, int outTok, int cachedRead = 0, int cacheWrite = 0) {
        if (g_SuspendCount > 0) return;
        if (inTok > 0) S_TotalInputTokens += inTok;
        if (outTok > 0) S_TotalOutputTokens += outTok;
        if (cachedRead > 0) S_TotalCachedReadTokens += cachedRead;
        if (cacheWrite > 0) S_TotalCacheWriteTokens += cacheWrite;
    }

    void RecordUserMessage() {
        if (g_SuspendCount > 0) return;
        S_TotalUserMessages++;
        S_TotalTurns++;
    }

    void RecordStep() { if (g_SuspendCount > 0) return; S_TotalSteps++; }
    void RecordBlockPlaced() { if (g_SuspendCount > 0) return; S_TotalBlocksPlaced++; }
    void RecordBlockRemoved() { if (g_SuspendCount > 0) return; S_TotalBlocksRemoved++; }

    void ResetAll() {
        if (g_SuspendCount > 0) return;
        S_TotalInputTokens = 0;
        S_TotalCachedReadTokens = 0;
        S_TotalCacheWriteTokens = 0;
        S_TotalOutputTokens = 0;
        S_TotalUserMessages = 0;
        S_TotalTurns = 0;
        S_TotalSteps = 0;
        S_TotalBlocksPlaced = 0;
        S_TotalBlocksRemoved = 0;
    }
}
