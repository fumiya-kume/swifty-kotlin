@testable import Runtime
import XCTest

final class RuntimeMemoryTests: XCTestCase {
    func testRuntimeGetRuntimeReturnsStableSingletonHandle() {
        XCTAssertEqual(kk_runtime_getRuntime(), kk_runtime_getRuntime())
    }

    func testMemoryMetricsStayWithinExpectedBounds() {
        let runtimeHandle = kk_runtime_getRuntime()
        XCTAssertNotEqual(runtimeHandle, 0)

        let total = kk_runtime_totalMemory()
        let free = kk_runtime_freeMemory()
        let max = kk_runtime_maxMemory()

        XCTAssertGreaterThan(total, 0)
        XCTAssertGreaterThanOrEqual(free, 0)
        XCTAssertGreaterThanOrEqual(max, total)
    }

    func testSystemGCLeavesMetricsQueryable() {
        kk_system_gc()

        XCTAssertGreaterThan(kk_runtime_totalMemory(), 0)
        XCTAssertGreaterThanOrEqual(kk_runtime_maxMemory(), kk_runtime_totalMemory())
    }

    func testLeakDetectionReportUsesDeltasAndThresholds() {
        let baseline = RuntimeMemorySnapshot(
            usedBytes: 1_024,
            totalBytes: 1_024,
            freeBytes: 8_192,
            maxBytes: 9_216,
            heapObjectCount: 2,
            uptimeNanos: 10
        )
        let current = RuntimeMemorySnapshot(
            usedBytes: 4_096,
            totalBytes: 4_096,
            freeBytes: 5_120,
            maxBytes: 9_216,
            heapObjectCount: 5,
            uptimeNanos: 20
        )

        let report = runtimeDetectMemoryLeak(
            since: baseline,
            current: current,
            thresholdBytes: 2_048,
            thresholdObjectCount: 2
        )

        XCTAssertTrue(report.hasLeak)
        XCTAssertEqual(report.leakedBytes, 3_072)
        XCTAssertEqual(report.heapObjectDelta, 3)
    }
}
