#if UNITTEST
namespace AgentUnitTests {
    enum TestStatus {
        Waiting = 0,
        Started = 1,
        Failed = 2,
        Passed = 3
    }

    array<TestStatus> g_Statuses = {};
    array<CoroutineFunc@> g_Funcs = {};
    array<string> g_Names = {};
    dictionary@ g_FailureMessages = dictionary();
    uint g_Counter = 0;
    uint g_Started = 0;
    uint g_Running = 0;
    uint g_Done = 0;
    uint g_Passed = 0;
    uint g_StartedAt = 0;

    bool runAsync(CoroutineFunc@ func) {
        startnew(func);
        return true;
    }

    bool RegisterUnitTest(const string &in name, CoroutineFunc@ func) {
        if (g_StartedAt == 0) {
            g_StartedAt = Time::Now;
        }
        uint id = g_Counter++;
        g_Statuses.InsertLast(TestStatus::Waiting);
        g_Funcs.InsertLast(func);
        g_Names.InsertLast(name);
        return true;
    }

    bool UnitTest_StartMainLoop() {
        startnew(UnitTest_MainLoop);
        return true;
    }

    void UnitTest_MainLoop() {
        while (g_Statuses.Length == 0) {
            yield();
        }
        sleep(25);
        // Test mode: freeze lifetime stats for the whole suite — tests call
        // Record* incidentally and those counters are persisted [Setting]s
        // (writes hit the user's disk). Suspended for the suite duration.
        AgentStats::SuspendRecording();
        while (g_Counter > g_Done) {
            if (g_Running < 10) {
                startnew(UnitTest_RunNext);
            }
            yield();
        }
        UnitTest_SuiteComplete_PrintResults();
        print("Completed " + g_Counter + " unit tests.");
    }

    void UnitTest_RunNext() {
        while (g_Started >= g_Counter) {
            yield();
        }
        uint id = g_Started++;
        g_Running++;
        g_Statuses[id] = TestStatus::Started;
        try {
            g_Funcs[id]();
            g_Statuses[id] = TestStatus::Passed;
            g_Passed++;
        } catch {
            g_Statuses[id] = TestStatus::Failed;
            string exInfo = getExceptionInfo();
            g_FailureMessages["" + id] = exInfo;
            print("\\$f21Test failed: " + g_Names[id] + " => " + exInfo);
        }
        g_Running--;
        g_Done++;
        print("Test completed: " + g_Names[id]);
    }

    void UnitTest_SuiteComplete_PrintResults() {
        print("\\$3a3Tests run: " + g_Counter);
        print("\\$3a3Tests passed: " + g_Passed);
        for (uint id = 0; id < g_Counter; id++) {
            if (g_Statuses[id] == TestStatus::Failed) {
                print("\\$f61" + g_Names[id] + " failed with message: " + string(g_FailureMessages["" + id]));
            }
        }
        print("Tests took: " + (Time::Now - g_StartedAt) + " ms");
    }

    bool unitTestsStarted = UnitTest_StartMainLoop();
}
#endif
