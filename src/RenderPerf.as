// Render-time profiler for the chat UI.
//
// RenderPerf::Tick() brackets each AgentUI::Render() call; ::Mark(label)
// accumulates the wall time since the previous mark into a per-label bucket.
// Buckets are reported at most every REPORT_MS as a single trace line with
// rolling averages, so we can see exactly which part of the frame is eating
// the ~100ms without spamming the log per frame.
//
// Enable/disable at runtime via the DEV driver ("renderperf" op), or flip
// g_Enabled in code. When disabled the marks are no-ops (a few ns each).
namespace RenderPerf {
    bool g_Enabled = true;
    const uint REPORT_MS = 3000;
    const uint MAX_BUCKETS = 32;

    array<string> g_Labels;
    array<uint64> g_Sums;      // total ms accumulated per bucket
    array<uint> g_Counts;      // frames that contributed to the bucket
    uint g_WindowStart = 0;    // Time::Now when current report window began
    uint g_FrameStart = 0;     // Time::Now at Tick()
    uint g_LastMark = 0;       // Time::Now at previous Mark/Tick
    uint g_Frames = 0;         // frames in current window
    uint g_FrameSumMs = 0;     // sum of full-frame ms in current window
    uint g_FrameMaxMs = 0;     // worst single-frame ms in current window

    void Reset() {
        g_Labels.Resize(0);
        g_Sums.Resize(0);
        g_Counts.Resize(0);
        g_WindowStart = Time::Now;
        g_Frames = 0;
        g_FrameSumMs = 0;
        g_FrameMaxMs = 0;
    }

    int BucketIx(const string &in label) {
        for (uint i = 0; i < g_Labels.Length; i++) {
            if (g_Labels[i] == label) return int(i);
        }
        if (g_Labels.Length >= MAX_BUCKETS) return -1;
        g_Labels.InsertLast(label);
        g_Sums.InsertLast(0);
        g_Counts.InsertLast(0);
        return int(g_Labels.Length - 1);
    }

    // Call once at the very start of AgentUI::Render().
    void Tick() {
        if (!g_Enabled) return;
        uint now = Time::Now;
        if (g_WindowStart == 0) g_WindowStart = now;
        g_FrameStart = now;
        g_LastMark = now;
    }

    // Record elapsed time since the previous mark under `label`.
    void Mark(const string &in label) {
        if (!g_Enabled || g_FrameStart == 0) return;
        uint now = Time::Now;
        uint elapsed = now - g_LastMark;
        g_LastMark = now;
        int ix = BucketIx(label);
        if (ix < 0) return;
        g_Sums[ix] += elapsed;
        g_Counts[ix]++;
    }

    // Call once at the very end of AgentUI::Render(). Reports when due.
    void Flush() {
        if (!g_Enabled || g_FrameStart == 0) return;
        uint now = Time::Now;
        uint frameMs = now - g_FrameStart;
        g_FrameStart = 0;
        g_Frames++;
        g_FrameSumMs += frameMs;
        if (frameMs > g_FrameMaxMs) g_FrameMaxMs = frameMs;

        if (now - g_WindowStart < REPORT_MS) return;

        uint denom = g_Frames > 0 ? g_Frames : 1;
        string line = "[renderperf] frames=" + g_Frames
            + " avg=" + Text::Format("%.1f", float(g_FrameSumMs) / float(denom)) + "ms"
            + " max=" + g_FrameMaxMs + "ms";
        for (uint i = 0; i < g_Labels.Length; i++) {
            if (g_Counts[i] == 0) continue;
            float avg = float(g_Sums[i]) / float(g_Counts[i]);
            line += " | " + g_Labels[i] + "=" + Text::Format("%.1f", avg) + "ms";
        }
        trace(line);
        Reset();
    }
}
