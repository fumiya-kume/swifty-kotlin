@testable import Runtime
import XCTest

/// Tests for `kotlin.native.Platform` runtime APIs:
/// `kk_platform_osFamily`, `kk_platform_cpuArchitecture`,
/// `kk_platform_canAccessUnaligned`, `kk_platform_isLittleEndian`,
/// and `kk_platform_getAvailableProcessors`.
///
/// `memoryModel` and `isDebugBinary` have no runtime entry point yet
/// (gaps documented at the bottom of this file).
final class RuntimePlatformInfoTests: XCTestCase {

    // MARK: - OsFamily

    /// On macOS the host OS family ordinal must equal 1 (MACOSX).
    func testOsFamilyOnMacOSReturnsMACOSX() {
        let ordinal = kk_platform_osFamily(0)
        let unboxed = kk_unbox_int(ordinal)
        // OsFamily.macosx == 1
        XCTAssertEqual(unboxed, 1, "Expected OsFamily.MACOSX (1) on macOS, got \(unboxed)")
    }

    /// The ordinal must be within the known enum range [0, 8].
    func testOsFamilyOrdinalIsWithinKnownRange() {
        let ordinal = kk_unbox_int(kk_platform_osFamily(0))
        XCTAssertGreaterThanOrEqual(ordinal, 0)
        XCTAssertLessThanOrEqual(ordinal, 8, "OsFamily ordinal \(ordinal) is outside the defined range [0,8]")
    }

    /// Repeated calls must return the identical boxed value (singleton cache).
    func testOsFamilyIsStableAcrossRepeatedCalls() {
        let first  = kk_platform_osFamily(0)
        let second = kk_platform_osFamily(0)
        XCTAssertEqual(first, second, "kk_platform_osFamily should return a stable cached value")
    }

    /// The platform argument is ignored; passing different values still returns the same ordinal.
    func testOsFamilyIgnoresPlatformArgument() {
        let a = kk_unbox_int(kk_platform_osFamily(0))
        let b = kk_unbox_int(kk_platform_osFamily(42))
        let c = kk_unbox_int(kk_platform_osFamily(-1))
        XCTAssertEqual(a, b)
        XCTAssertEqual(b, c)
    }

    // MARK: - CpuArchitecture

    /// On Apple Silicon the architecture ordinal must equal 4 (ARM64);
    /// on Intel it must equal 2 (X64).
    func testCpuArchitectureIsARM64orX64() {
        let ordinal = kk_unbox_int(kk_platform_cpuArchitecture(0))
#if arch(arm64)
        XCTAssertEqual(ordinal, 4, "Expected CpuArchitecture.ARM64 (4) on Apple Silicon, got \(ordinal)")
#elseif arch(x86_64)
        XCTAssertEqual(ordinal, 2, "Expected CpuArchitecture.X64 (2) on Intel, got \(ordinal)")
#else
        XCTAssertGreaterThanOrEqual(ordinal, 0)
#endif
    }

    /// The ordinal must be within the known enum range [0, 7].
    func testCpuArchitectureOrdinalIsWithinKnownRange() {
        let ordinal = kk_unbox_int(kk_platform_cpuArchitecture(0))
        XCTAssertGreaterThanOrEqual(ordinal, 0)
        XCTAssertLessThanOrEqual(ordinal, 7, "CpuArchitecture ordinal \(ordinal) is outside the defined range [0,7]")
    }

    /// Repeated calls must return the identical boxed value (singleton cache).
    func testCpuArchitectureIsStableAcrossRepeatedCalls() {
        let first  = kk_platform_cpuArchitecture(0)
        let second = kk_platform_cpuArchitecture(0)
        XCTAssertEqual(first, second)
    }

    /// The platform argument is ignored.
    func testCpuArchitectureIgnoresPlatformArgument() {
        let a = kk_unbox_int(kk_platform_cpuArchitecture(0))
        let b = kk_unbox_int(kk_platform_cpuArchitecture(99))
        XCTAssertEqual(a, b)
    }

    // MARK: - isLittleEndian

    /// All Apple platforms (macOS arm64 and x86_64) are little-endian.
    func testIsLittleEndianIsTrueOnApplePlatforms() {
        let result = kk_platform_isLittleEndian(0)
        XCTAssertEqual(result, 1, "Expected isLittleEndian == true on Apple platforms, got \(result)")
    }

    /// The result must be a boolean-like integer: 0 or 1.
    func testIsLittleEndianReturnsBooleanInt() {
        let result = kk_platform_isLittleEndian(0)
        XCTAssertTrue(result == 0 || result == 1, "Expected 0 or 1, got \(result)")
    }

    /// Repeated calls must be consistent (idempotent).
    func testIsLittleEndianIsIdempotent() {
        let first  = kk_platform_isLittleEndian(0)
        let second = kk_platform_isLittleEndian(0)
        XCTAssertEqual(first, second)
    }

    /// The platform argument is ignored.
    func testIsLittleEndianIgnoresPlatformArgument() {
        let a = kk_platform_isLittleEndian(0)
        let b = kk_platform_isLittleEndian(999)
        XCTAssertEqual(a, b)
    }

    // MARK: - canAccessUnaligned

    /// On x86_64 and arm64, unaligned access is permitted (returns 1).
    func testCanAccessUnalignedIsTrueOnCommonArchitectures() {
        let result = kk_platform_canAccessUnaligned(0)
#if arch(x86_64) || arch(arm64) || arch(i386)
        XCTAssertEqual(result, 1, "Expected canAccessUnaligned == true on x86_64/arm64, got \(result)")
#else
        XCTAssertTrue(result == 0 || result == 1, "Expected 0 or 1, got \(result)")
#endif
    }

    /// The result must be a boolean-like integer: 0 or 1.
    func testCanAccessUnalignedReturnsBooleanInt() {
        let result = kk_platform_canAccessUnaligned(0)
        XCTAssertTrue(result == 0 || result == 1, "Expected 0 or 1, got \(result)")
    }

    /// Repeated calls must be consistent.
    func testCanAccessUnalignedIsIdempotent() {
        let first  = kk_platform_canAccessUnaligned(0)
        let second = kk_platform_canAccessUnaligned(0)
        XCTAssertEqual(first, second)
    }

    /// The platform argument is ignored.
    func testCanAccessUnalignedIgnoresPlatformArgument() {
        let a = kk_platform_canAccessUnaligned(0)
        let b = kk_platform_canAccessUnaligned(-42)
        XCTAssertEqual(a, b)
    }

    // MARK: - isLittleEndian / canAccessUnaligned consistency

    /// On architectures where canAccessUnaligned is true, isLittleEndian is also
    /// always true on all currently supported Apple targets.
    func testIsLittleEndianAndCanAccessUnalignedAreConsistentOnApplePlatforms() {
#if os(macOS) || os(iOS) || os(tvOS) || os(watchOS)
        let le  = kk_platform_isLittleEndian(0)
        let cau = kk_platform_canAccessUnaligned(0)
        XCTAssertEqual(le,  1, "Apple platforms are little-endian")
        XCTAssertEqual(cau, 1, "Apple arm64/x86_64 support unaligned access")
#endif
    }

    // MARK: - getAvailableProcessors

    /// Available processors must be at least 1.
    func testGetAvailableProcessorsReturnsAtLeastOne() {
        let count = kk_platform_getAvailableProcessors(0)
        XCTAssertGreaterThanOrEqual(count, 1)
    }

    /// Available processors must be a plausible upper bound (≤ 1024).
    func testGetAvailableProcessorsIsPlausible() {
        let count = kk_platform_getAvailableProcessors(0)
        XCTAssertLessThanOrEqual(count, 1024, "Unexpectedly large processor count: \(count)")
    }

    /// Repeated calls must agree (stable within a process).
    func testGetAvailableProcessorsIsStable() {
        let first  = kk_platform_getAvailableProcessors(0)
        let second = kk_platform_getAvailableProcessors(0)
        XCTAssertEqual(first, second)
    }

    // MARK: - Enum stability: OsFamily raw values

    /// OsFamily enum ordinals are part of the ABI and must not change.
    func testOsFamilyEnumOrdinalStability() {
        // Ordinals are checked by decoding the boxed value from the runtime.
        // We can only observe the host platform's value here, but we verify
        // that the returned ordinal is non-negative and within the declared range.
        let ordinal = kk_unbox_int(kk_platform_osFamily(0))
        XCTAssertGreaterThanOrEqual(ordinal, 0)
        // If the host is macOS the value must be 1 per the spec.
#if os(macOS)
        XCTAssertEqual(ordinal, 1, "OsFamily.MACOSX must be 1 (ABI stability)")
#endif
    }

    /// CpuArchitecture enum ordinals are part of the ABI and must not change.
    func testCpuArchitectureEnumOrdinalStability() {
        let ordinal = kk_unbox_int(kk_platform_cpuArchitecture(0))
        XCTAssertGreaterThanOrEqual(ordinal, 0)
#if arch(arm64)
        XCTAssertEqual(ordinal, 4, "CpuArchitecture.ARM64 must be 4 (ABI stability)")
#elseif arch(x86_64)
        XCTAssertEqual(ordinal, 2, "CpuArchitecture.X64 must be 2 (ABI stability)")
#endif
    }
}

// MARK: - Known gaps (not yet implemented in RuntimePlatform.swift)
//
// The following `kotlin.native.Platform` properties have NO runtime entry point
// and therefore cannot be tested yet:
//
//   • Platform.memoryModel  — should return EXPERIMENTAL or STRICT via a
//     `kk_platform_memoryModel` C entry returning a boxed MemoryModel ordinal.
//     MemoryModel.STRICT == 0, MemoryModel.EXPERIMENTAL == 1 (Kotlin/Native spec).
//
//   • Platform.isDebugBinary — should return 1 in debug builds and 0 in
//     release builds via a `kk_platform_isDebugBinary` C entry.
//     Could be implemented with a compile-time `#if DEBUG` Swift flag.
