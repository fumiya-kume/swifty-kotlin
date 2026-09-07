#if canImport(Testing)
@testable import Runtime
import Testing

@Suite(.runtimeIsolation(.gcOnly))
struct RuntimeMemoryTests {
    @Test
    func testRuntimeGetRuntimeReturnsStableSingletonHandle() {
        #expect(__kk_runtime_getRuntime() == __kk_runtime_getRuntime())
    }

    @Test
    func testMemoryMetricsStayWithinExpectedBounds() {
        let runtimeHandle = __kk_runtime_getRuntime()
        #expect(runtimeHandle != 0)

        let total = __kk_runtime_totalMemory()
        let free = __kk_runtime_freeMemory()
        let max = __kk_runtime_maxMemory()

        #expect(total > 0)
        #expect(free >= 0)
        #expect(max >= total)
    }

    @Test
    func testSystemGCLeavesMetricsQueryable() {
        __kk_system_gc()

        #expect(__kk_runtime_totalMemory() > 0)
        #expect(__kk_runtime_maxMemory() >= __kk_runtime_totalMemory())
    }

    @Test
    func testAnyJavaClassReturnsNonNullObjectHandle() {
        let handle1 = __kk_any_javaClass(0)
        let handle2 = __kk_any_javaClass(42)

        #expect(handle1 != 0)
        #expect(handle2 != 0)
        #expect(handle1 != handle2)
    }
}
#endif
