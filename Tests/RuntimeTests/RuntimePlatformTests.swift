@testable import Runtime
import XCTest

final class RuntimePlatformTests: XCTestCase {

    // MARK: - kk_platform_memoryModel

    func testMemoryModelRuntimeEntryPointIsAvailable() {
        // STDLIB-NATIVE-PLATFORM-ABI-001: kk_platform_memoryModel is now implemented.
        XCTAssertNotNil(kk_platform_memoryModel(0) as Int?)
    }

    func testMemoryModelReturnsBoxedInt() {
        let result = kk_platform_memoryModel(0)
        // A valid boxed Int is non-zero (the boxing scheme never returns 0 for a tagged pointer).
        XCTAssertNotEqual(result, 0)
    }

    func testMemoryModelOrdinalIsValidRange() {
        let result = kk_platform_memoryModel(0)
        let unboxed = kk_unbox_int(result)
        // MemoryModel ordinals: STRICT=0, RELAXED=1, EXPERIMENTAL=2
        XCTAssertGreaterThanOrEqual(unboxed, 0)
        XCTAssertLessThanOrEqual(unboxed, 2)
    }

    func testMemoryModelDefaultIsExperimental() {
        // Without KSWIFTK_MEMORY_MODEL_STRICT / _RELAXED build flags the default is EXPERIMENTAL (2).
        let result = kk_platform_memoryModel(0)
        let unboxed = kk_unbox_int(result)
        XCTAssertEqual(unboxed, 2, "Default memory model should be EXPERIMENTAL (ordinal 2)")
    }

    func testMemoryModelIsStableAcrossCalls() {
        XCTAssertEqual(kk_platform_memoryModel(0), kk_platform_memoryModel(0))
    }

    func testMemoryModelIgnoresPlatformRawArgument() {
        XCTAssertEqual(kk_platform_memoryModel(0), kk_platform_memoryModel(42))
    }

    // MARK: - kk_platform_isDebugBinary

    func testIsDebugBinaryReturnsZeroOrOne() {
        let result = kk_platform_isDebugBinary(0)
        XCTAssertTrue(result == 0 || result == 1)
    }

    func testIsDebugBinaryIsTrueInDebugBuilds() {
        // Tests run under the debug configuration; _isDebugAssertConfiguration() should be true.
        let result = kk_platform_isDebugBinary(0)
        XCTAssertEqual(result, 1, "kk_platform_isDebugBinary should return 1 when compiled with debug assertions")
    }

    func testIsDebugBinaryIsStableAcrossCalls() {
        XCTAssertEqual(kk_platform_isDebugBinary(0), kk_platform_isDebugBinary(0))
    }

    func testIsDebugBinaryIgnoresPlatformRawArgument() {
        XCTAssertEqual(kk_platform_isDebugBinary(0), kk_platform_isDebugBinary(99))
    }
}
