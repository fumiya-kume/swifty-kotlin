@testable import CompilerCore
import XCTest

final class CompilerOptionsTests: XCTestCase {
    // MARK: - CompilerVersion

    func testCompilerVersionInit() {
        let v = CompilerVersion(major: 1, minor: 2, patch: 3, gitHash: "abc123")
        XCTAssertEqual(v.major, 1)
        XCTAssertEqual(v.minor, 2)
        XCTAssertEqual(v.patch, 3)
        XCTAssertEqual(v.gitHash, "abc123")
    }

    func testCompilerVersionEquatable() {
        let v1 = CompilerVersion(major: 1, minor: 0, patch: 0, gitHash: nil)
        let v2 = CompilerVersion(major: 1, minor: 0, patch: 0, gitHash: nil)
        let v3 = CompilerVersion(major: 2, minor: 0, patch: 0, gitHash: nil)
        XCTAssertEqual(v1, v2)
        XCTAssertNotEqual(v1, v3)
    }

    func testCompilerVersionWithNilGitHash() {
        let v = CompilerVersion(major: 0, minor: 1, patch: 0, gitHash: nil)
        XCTAssertNil(v.gitHash)
    }

    // MARK: - TargetTriple

    func testTargetTripleInit() {
        let triple = TargetTriple(arch: "arm64", vendor: "apple", os: "macosx", osVersion: "14.0")
        XCTAssertEqual(triple.arch, "arm64")
        XCTAssertEqual(triple.vendor, "apple")
        XCTAssertEqual(triple.os, "macosx")
        XCTAssertEqual(triple.osVersion, "14.0")
    }

    func testTargetTripleEquatable() {
        let t1 = TargetTriple(arch: "arm64", vendor: "apple", os: "macosx", osVersion: nil)
        let t2 = TargetTriple(arch: "arm64", vendor: "apple", os: "macosx", osVersion: nil)
        let t3 = TargetTriple(arch: "x86_64", vendor: "apple", os: "macosx", osVersion: nil)
        XCTAssertEqual(t1, t2)
        XCTAssertNotEqual(t1, t3)
    }

    func testTargetTripleHostDefault() {
        let triple = TargetTriple.hostDefault()
        XCTAssertFalse(triple.arch.isEmpty)
        XCTAssertFalse(triple.vendor.isEmpty)
        XCTAssertFalse(triple.os.isEmpty)
    }

    func testTargetTripleWithNilOsVersion() {
        let triple = TargetTriple(arch: "arm64", vendor: "unknown", os: "linux-gnu", osVersion: nil)
        XCTAssertNil(triple.osVersion)
    }

    // MARK: - CompilerOptions init

    func testCompilerOptionsDefaultValues() {
        let opts = CompilerOptions(
            moduleName: "Test",
            inputs: ["/a.kt"],
            outputPath: "/out",
            emit: .executable,
            target: defaultTargetTriple()
        )
        XCTAssertEqual(opts.moduleName, "Test")
        XCTAssertEqual(opts.inputs, ["/a.kt"])
        XCTAssertEqual(opts.outputPath, "/out")
        XCTAssertEqual(opts.emit, .executable)
        XCTAssertTrue(opts.searchPaths.isEmpty)
        XCTAssertTrue(opts.libraryPaths.isEmpty)
        XCTAssertTrue(opts.linkLibraries.isEmpty)
        XCTAssertEqual(opts.optLevel, .O0)
        XCTAssertFalse(opts.debugInfo)
        XCTAssertTrue(opts.frontendFlags.isEmpty)
        XCTAssertTrue(opts.irFlags.isEmpty)
        XCTAssertTrue(opts.runtimeFlags.isEmpty)
        XCTAssertNil(opts.incrementalCachePath)
    }

    func testCompilerOptionsWithAllFields() {
        let opts = CompilerOptions(
            moduleName: "MyMod",
            inputs: ["/a.kt", "/b.kt"],
            outputPath: "/out/bin",
            emit: .object,
            searchPaths: ["/lib"],
            libraryPaths: ["/ext"],
            linkLibraries: ["runtime"],
            target: TargetTriple(arch: "x86_64", vendor: "unknown", os: "linux-gnu", osVersion: nil),
            optLevel: .O2,
            debugInfo: true,
            frontendFlags: ["jobs=4"],
            irFlags: ["opt-passes"],
            runtimeFlags: ["gc=conservative"],
            incrementalCachePath: "/cache"
        )
        XCTAssertEqual(opts.moduleName, "MyMod")
        XCTAssertEqual(opts.inputs.count, 2)
        XCTAssertEqual(opts.emit, .object)
        XCTAssertEqual(opts.searchPaths, ["/lib"])
        XCTAssertEqual(opts.libraryPaths, ["/ext"])
        XCTAssertEqual(opts.linkLibraries, ["runtime"])
        XCTAssertEqual(opts.optLevel, .O2)
        XCTAssertTrue(opts.debugInfo)
        XCTAssertEqual(opts.frontendFlags, ["jobs=4"])
        XCTAssertEqual(opts.irFlags, ["opt-passes"])
        XCTAssertEqual(opts.runtimeFlags, ["gc=conservative"])
        XCTAssertEqual(opts.incrementalCachePath, "/cache")
    }

    func testCompilerOptionsEquatable() {
        let opts1 = CompilerOptions(
            moduleName: "A",
            inputs: ["/a.kt"],
            outputPath: "/out",
            emit: .kirDump,
            target: defaultTargetTriple()
        )
        let opts2 = CompilerOptions(
            moduleName: "A",
            inputs: ["/a.kt"],
            outputPath: "/out",
            emit: .kirDump,
            target: defaultTargetTriple()
        )
        let opts3 = CompilerOptions(
            moduleName: "B",
            inputs: ["/a.kt"],
            outputPath: "/out",
            emit: .kirDump,
            target: defaultTargetTriple()
        )
        XCTAssertEqual(opts1, opts2)
        XCTAssertNotEqual(opts1, opts3)
    }

    // MARK: - frontendJobs

    func testFrontendJobsDefaultIsOne() {
        let opts = CompilerOptions(
            moduleName: "Test",
            inputs: [],
            outputPath: "/out",
            emit: .kirDump,
            target: defaultTargetTriple()
        )
        XCTAssertEqual(opts.frontendJobs, 1)
    }

    func testFrontendJobsParsesFromFlag() {
        let opts = CompilerOptions(
            moduleName: "Test",
            inputs: [],
            outputPath: "/out",
            emit: .kirDump,
            target: defaultTargetTriple(),
            frontendFlags: ["jobs=8"]
        )
        XCTAssertEqual(opts.frontendJobs, 8)
    }

    func testFrontendJobsIgnoresInvalidValues() {
        let opts = CompilerOptions(
            moduleName: "Test",
            inputs: [],
            outputPath: "/out",
            emit: .kirDump,
            target: defaultTargetTriple(),
            frontendFlags: ["jobs=0"]
        )
        // jobs=0 is < 1, so should return default of 1
        XCTAssertEqual(opts.frontendJobs, 1)
    }

    func testFrontendJobsIgnoresNonNumeric() {
        let opts = CompilerOptions(
            moduleName: "Test",
            inputs: [],
            outputPath: "/out",
            emit: .kirDump,
            target: defaultTargetTriple(),
            frontendFlags: ["jobs=abc"]
        )
        XCTAssertEqual(opts.frontendJobs, 1)
    }

    func testFrontendJobsIgnoresUnrelatedFlags() {
        let opts = CompilerOptions(
            moduleName: "Test",
            inputs: [],
            outputPath: "/out",
            emit: .kirDump,
            target: defaultTargetTriple(),
            frontendFlags: ["sema-cache", "debug-mode"]
        )
        XCTAssertEqual(opts.frontendJobs, 1)
    }

    func testFrontendJobsUsesFirstMatch() {
        let opts = CompilerOptions(
            moduleName: "Test",
            inputs: [],
            outputPath: "/out",
            emit: .kirDump,
            target: defaultTargetTriple(),
            frontendFlags: ["jobs=4", "jobs=8"]
        )
        XCTAssertEqual(opts.frontendJobs, 4)
    }

    // MARK: - lazyThreadSafetyMode

    func testLazyThreadSafetyModeDefaultIsSynchronized() {
        let opts = CompilerOptions(
            moduleName: "Test",
            inputs: [],
            outputPath: "/out",
            emit: .kirDump,
            target: defaultTargetTriple()
        )
        XCTAssertEqual(opts.lazyThreadSafetyMode, .synchronized)
    }

    func testLazyThreadSafetyModeNone() {
        let opts = CompilerOptions(
            moduleName: "Test",
            inputs: [],
            outputPath: "/out",
            emit: .kirDump,
            target: defaultTargetTriple(),
            frontendFlags: ["lazy-thread-safety=NONE"]
        )
        XCTAssertEqual(opts.lazyThreadSafetyMode, .none)
    }

    func testLazyThreadSafetyModeSynchronized() {
        let opts = CompilerOptions(
            moduleName: "Test",
            inputs: [],
            outputPath: "/out",
            emit: .kirDump,
            target: defaultTargetTriple(),
            frontendFlags: ["lazy-thread-safety=SYNCHRONIZED"]
        )
        XCTAssertEqual(opts.lazyThreadSafetyMode, .synchronized)
    }

    func testLazyThreadSafetyModeIsCaseInsensitive() {
        let opts = CompilerOptions(
            moduleName: "Test",
            inputs: [],
            outputPath: "/out",
            emit: .kirDump,
            target: defaultTargetTriple(),
            frontendFlags: ["lazy-thread-safety=none"]
        )
        XCTAssertEqual(opts.lazyThreadSafetyMode, .none)
    }

    func testLazyThreadSafetyModeUnknownValueDefaultsSynchronized() {
        let opts = CompilerOptions(
            moduleName: "Test",
            inputs: [],
            outputPath: "/out",
            emit: .kirDump,
            target: defaultTargetTriple(),
            frontendFlags: ["lazy-thread-safety=UNKNOWN"]
        )
        XCTAssertEqual(opts.lazyThreadSafetyMode, .synchronized)
    }

    // MARK: - EmitMode

    func testEmitModeRawValues() {
        XCTAssertEqual(EmitMode.executable.rawValue, "executable")
        XCTAssertEqual(EmitMode.object.rawValue, "object")
        XCTAssertEqual(EmitMode.llvmIR.rawValue, "llvmIR")
        XCTAssertEqual(EmitMode.kirDump.rawValue, "kirDump")
        XCTAssertEqual(EmitMode.library.rawValue, "library")
    }

    // MARK: - OptimizationLevel

    func testOptimizationLevelRawValues() {
        XCTAssertEqual(OptimizationLevel.O0.rawValue, 0)
        XCTAssertEqual(OptimizationLevel.O1.rawValue, 1)
        XCTAssertEqual(OptimizationLevel.O2.rawValue, 2)
        XCTAssertEqual(OptimizationLevel.O3.rawValue, 3)
    }

    // MARK: - LazyDelegateThreadSafetyMode

    func testLazyDelegateThreadSafetyModeRawValues() {
        XCTAssertEqual(LazyDelegateThreadSafetyMode.synchronized.rawValue, 1)
        XCTAssertEqual(LazyDelegateThreadSafetyMode.none.rawValue, 0)
    }

    // MARK: - KotlinLanguageVersion

    func testKotlinLanguageVersionEquatable() {
        let v1 = KotlinLanguageVersion.v2_3_10
        let v2 = KotlinLanguageVersion.v2_3_10
        XCTAssertEqual(v1, v2)
    }
}
