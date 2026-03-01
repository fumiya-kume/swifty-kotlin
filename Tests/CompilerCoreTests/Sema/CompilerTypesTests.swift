import XCTest
@testable import CompilerCore

final class CompilerTypesTests: XCTestCase {
    func testCompilerVersionAndTargetTripleStoreValues() {
        let version = CompilerVersion(major: 1, minor: 2, patch: 3, gitHash: "abc123")
        XCTAssertEqual(version.major, 1)
        XCTAssertEqual(version.minor, 2)
        XCTAssertEqual(version.patch, 3)
        XCTAssertEqual(version.gitHash, "abc123")

        let triple = TargetTriple(arch: "arm64", vendor: "apple", os: "macosx", osVersion: "14.0")
        XCTAssertEqual(triple.arch, "arm64")
        XCTAssertEqual(triple.vendor, "apple")
        XCTAssertEqual(triple.os, "macosx")
        XCTAssertEqual(triple.osVersion, "14.0")
    }

    func testCompilerOptionsDefaultArguments() {
        let options = CompilerOptions(
            moduleName: "DefaultModule",
            inputs: ["input.kt"],
            outputPath: "out.o",
            emit: .object,
            target: TargetTriple(arch: "arm64", vendor: "apple", os: "macosx", osVersion: nil)
        )

        XCTAssertEqual(options.moduleName, "DefaultModule")
        XCTAssertEqual(options.inputs, ["input.kt"])
        XCTAssertEqual(options.outputPath, "out.o")
        XCTAssertEqual(options.emit, .object)
        XCTAssertEqual(options.searchPaths, [])
        XCTAssertEqual(options.libraryPaths, [])
        XCTAssertEqual(options.linkLibraries, [])
        XCTAssertEqual(options.optLevel, .O0)
        XCTAssertFalse(options.debugInfo)
        XCTAssertEqual(options.frontendFlags, [])
        XCTAssertEqual(options.irFlags, [])
        XCTAssertEqual(options.runtimeFlags, [])
    }

    func testCompilerOptionsDebugInfoPropertyAndInit() {
        let target = TargetTriple(arch: "arm64", vendor: "apple", os: "macosx", osVersion: nil)

        var options = CompilerOptions(
            moduleName: "M",
            inputs: ["a.kt"],
            outputPath: "out",
            emit: .executable,
            target: target,
            debugInfo: true
        )
        XCTAssertTrue(options.debugInfo)

        options.debugInfo = false
        XCTAssertFalse(options.debugInfo)
    }

    func testCompilerOptionsCustomArgumentsAndEnums() {
        let target = TargetTriple(arch: "x86_64", vendor: "pc", os: "linux", osVersion: "6")
        let options = CompilerOptions(
            moduleName: "CustomModule",
            inputs: ["a.kt", "b.kt"],
            outputPath: "bin/custom",
            emit: .library,
            searchPaths: ["/opt/include"],
            libraryPaths: ["/opt/lib"],
            linkLibraries: ["m", "pthread"],
            target: target,
            optLevel: .O3,
            debugInfo: true,
            frontendFlags: ["-XfrontendA"],
            irFlags: ["-XirA"],
            runtimeFlags: ["-XruntimeA"]
        )

        XCTAssertEqual(options.target, target)
        XCTAssertEqual(options.optLevel, .O3)
        XCTAssertTrue(options.debugInfo)
        XCTAssertEqual(options.searchPaths, ["/opt/include"])
        XCTAssertEqual(options.libraryPaths, ["/opt/lib"])
        XCTAssertEqual(options.linkLibraries, ["m", "pthread"])
        XCTAssertEqual(options.frontendFlags, ["-XfrontendA"])
        XCTAssertEqual(options.irFlags, ["-XirA"])
        XCTAssertEqual(options.runtimeFlags, ["-XruntimeA"])

    }

    func testCompilerVersionWithNilGitHash() {
        let version = CompilerVersion(major: 0, minor: 0, patch: 1, gitHash: nil)
        XCTAssertEqual(version.major, 0)
        XCTAssertEqual(version.minor, 0)
        XCTAssertEqual(version.patch, 1)
        XCTAssertNil(version.gitHash)
    }

    func testTargetTripleWithNilOsVersion() {
        let triple = TargetTriple(arch: "x86_64", vendor: "unknown", os: "linux", osVersion: nil)
        XCTAssertEqual(triple.arch, "x86_64")
        XCTAssertEqual(triple.vendor, "unknown")
        XCTAssertEqual(triple.os, "linux")
        XCTAssertNil(triple.osVersion)
    }

    func testCompilerOptionsDebugInfoPropertyGetAndSet() {
        let target = TargetTriple(arch: "arm64", vendor: "apple", os: "macosx", osVersion: nil)
        var options = CompilerOptions(
            moduleName: "M",
            inputs: ["a.kt"],
            outputPath: "out",
            emit: .object,
            target: target,
            debugInfo: false
        )
        XCTAssertFalse(options.debugInfo)
        options.debugInfo = true
        XCTAssertTrue(options.debugInfo)
    }

    func testInitWithDebugInfo() {
        let target = TargetTriple(arch: "arm64", vendor: "apple", os: "macosx", osVersion: nil)
        let options = CompilerOptions(
            moduleName: "ModuleWithDebug",
            inputs: ["b.kt"],
            outputPath: "out2",
            emit: .executable,
            searchPaths: ["/sp"],
            libraryPaths: ["/lp"],
            linkLibraries: ["z"],
            target: target,
            optLevel: .O2,
            debugInfo: true,
            frontendFlags: ["-Xf"],
            irFlags: ["-Xi"],
            runtimeFlags: ["-Xr"]
        )
        XCTAssertEqual(options.moduleName, "ModuleWithDebug")
        XCTAssertEqual(options.inputs, ["b.kt"])
        XCTAssertEqual(options.outputPath, "out2")
        XCTAssertEqual(options.emit, .executable)
        XCTAssertEqual(options.searchPaths, ["/sp"])
        XCTAssertEqual(options.libraryPaths, ["/lp"])
        XCTAssertEqual(options.linkLibraries, ["z"])
        XCTAssertEqual(options.target, target)
        XCTAssertEqual(options.optLevel, .O2)
        XCTAssertTrue(options.debugInfo)
        XCTAssertEqual(options.frontendFlags, ["-Xf"])
        XCTAssertEqual(options.irFlags, ["-Xi"])
        XCTAssertEqual(options.runtimeFlags, ["-Xr"])
    }

    func testInitWithDebugInfoDefaultArguments() {
        let options = CompilerOptions(
            moduleName: "M2",
            inputs: ["b.kt"],
            outputPath: "out2",
            emit: .llvmIR,
            target: TargetTriple(arch: "x86_64", vendor: "pc", os: "linux", osVersion: nil),
            debugInfo: false
        )
        XCTAssertEqual(options.moduleName, "M2")
        XCTAssertEqual(options.emit, .llvmIR)
        XCTAssertFalse(options.debugInfo)
        XCTAssertEqual(options.searchPaths, [])
        XCTAssertEqual(options.libraryPaths, [])
        XCTAssertEqual(options.linkLibraries, [])
        XCTAssertEqual(options.optLevel, .O0)
        XCTAssertEqual(options.frontendFlags, [])
        XCTAssertEqual(options.irFlags, [])
        XCTAssertEqual(options.runtimeFlags, [])
    }

    func testOptimizationLevelEquality() {
        XCTAssertNotEqual(OptimizationLevel.O0, OptimizationLevel.O3)
    }

    func testCompilerVersionEquality() {
        let v1 = CompilerVersion(major: 1, minor: 2, patch: 3, gitHash: "abc")
        let v2 = CompilerVersion(major: 1, minor: 2, patch: 3, gitHash: "abc")
        let v3 = CompilerVersion(major: 1, minor: 2, patch: 4, gitHash: "abc")
        XCTAssertEqual(v1, v2)
        XCTAssertNotEqual(v1, v3)
    }

    func testTargetTripleEquality() {
        let t1 = TargetTriple(arch: "arm64", vendor: "apple", os: "macosx", osVersion: "14.0")
        let t2 = TargetTriple(arch: "arm64", vendor: "apple", os: "macosx", osVersion: "14.0")
        let t3 = TargetTriple(arch: "x86_64", vendor: "apple", os: "macosx", osVersion: "14.0")
        XCTAssertEqual(t1, t2)
        XCTAssertNotEqual(t1, t3)
    }

    func testOptimizationLevelRawValues() {
        XCTAssertEqual(OptimizationLevel.O0.rawValue, 0)
        XCTAssertEqual(OptimizationLevel.O1.rawValue, 1)
        XCTAssertEqual(OptimizationLevel.O2.rawValue, 2)
        XCTAssertEqual(OptimizationLevel.O3.rawValue, 3)
    }

    func testEmitModeRawValues() {
        XCTAssertEqual(EmitMode.executable.rawValue, "executable")
        XCTAssertEqual(EmitMode.object.rawValue, "object")
        XCTAssertEqual(EmitMode.llvmIR.rawValue, "llvmIR")
        XCTAssertEqual(EmitMode.kirDump.rawValue, "kirDump")
        XCTAssertEqual(EmitMode.library.rawValue, "library")
    }

    func testKotlinLanguageVersionEquality() {
        let v1 = KotlinLanguageVersion.v2_3_10
        let v2 = KotlinLanguageVersion.v2_3_10
        XCTAssertEqual(v1, v2)
    }

    func testCompilerOptionsEquality() {
        let target = TargetTriple(arch: "arm64", vendor: "apple", os: "macosx", osVersion: nil)
        let o1 = CompilerOptions(
            moduleName: "M", inputs: ["a.kt"], outputPath: "out",
            emit: .object, target: target
        )
        let o2 = CompilerOptions(
            moduleName: "M", inputs: ["a.kt"], outputPath: "out",
            emit: .object, target: target
        )
        let o3 = CompilerOptions(
            moduleName: "N", inputs: ["a.kt"], outputPath: "out",
            emit: .object, target: target
        )
        XCTAssertEqual(o1, o2)
        XCTAssertNotEqual(o1, o3)
    }

    // MARK: - LazyDelegateThreadSafetyMode & lazyThreadSafetyMode (P5-80)

    func testLazyDelegateThreadSafetyModeRawValues() {
        XCTAssertEqual(LazyDelegateThreadSafetyMode.synchronized.rawValue, 1)
        XCTAssertEqual(LazyDelegateThreadSafetyMode.none.rawValue, 0)
    }

    func testLazyDelegateThreadSafetyModeEquality() {
        XCTAssertEqual(LazyDelegateThreadSafetyMode.synchronized, .synchronized)
        XCTAssertEqual(LazyDelegateThreadSafetyMode.none, .none)
        XCTAssertNotEqual(LazyDelegateThreadSafetyMode.synchronized, .none)
    }

    func testLazyThreadSafetyModeDefaultIsSynchronized() {
        let target = TargetTriple(arch: "arm64", vendor: "apple", os: "macosx", osVersion: nil)
        let options = CompilerOptions(
            moduleName: "M", inputs: ["a.kt"], outputPath: "out",
            emit: .object, target: target
        )
        XCTAssertEqual(options.lazyThreadSafetyMode, .synchronized)
    }

    func testLazyThreadSafetyModeNone() {
        let target = TargetTriple(arch: "arm64", vendor: "apple", os: "macosx", osVersion: nil)
        let options = CompilerOptions(
            moduleName: "M", inputs: ["a.kt"], outputPath: "out",
            emit: .object, target: target,
            frontendFlags: ["lazy-thread-safety=NONE"]
        )
        XCTAssertEqual(options.lazyThreadSafetyMode, .none)
    }

    func testLazyThreadSafetyModeSynchronizedExplicit() {
        let target = TargetTriple(arch: "arm64", vendor: "apple", os: "macosx", osVersion: nil)
        let options = CompilerOptions(
            moduleName: "M", inputs: ["a.kt"], outputPath: "out",
            emit: .object, target: target,
            frontendFlags: ["lazy-thread-safety=SYNCHRONIZED"]
        )
        XCTAssertEqual(options.lazyThreadSafetyMode, .synchronized)
    }

    func testLazyThreadSafetyModeUnknownValueDefaultsToSynchronized() {
        let target = TargetTriple(arch: "arm64", vendor: "apple", os: "macosx", osVersion: nil)
        let options = CompilerOptions(
            moduleName: "M", inputs: ["a.kt"], outputPath: "out",
            emit: .object, target: target,
            frontendFlags: ["lazy-thread-safety=BOGUS"]
        )
        XCTAssertEqual(options.lazyThreadSafetyMode, .synchronized)
    }

    func testLazyThreadSafetyModeCaseInsensitive() {
        let target = TargetTriple(arch: "arm64", vendor: "apple", os: "macosx", osVersion: nil)
        let options = CompilerOptions(
            moduleName: "M", inputs: ["a.kt"], outputPath: "out",
            emit: .object, target: target,
            frontendFlags: ["lazy-thread-safety=none"]
        )
        XCTAssertEqual(options.lazyThreadSafetyMode, .none)
    }

    func testHostDefaultTargetTripleMatchesCompileArchitecture() {
        let host = TargetTriple.hostDefault()
        #if arch(arm64)
        XCTAssertEqual(host.arch, "arm64")
        #elseif arch(x86_64)
        XCTAssertEqual(host.arch, "x86_64")
        #endif
        #if os(Linux)
        XCTAssertEqual(host.vendor, "unknown")
        XCTAssertEqual(host.os, "linux-gnu")
        #else
        XCTAssertEqual(host.vendor, "apple")
        XCTAssertEqual(host.os, "macosx")
        #endif
        XCTAssertNil(host.osVersion)
    }
}
