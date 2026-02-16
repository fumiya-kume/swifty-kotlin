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

        XCTAssertEqual(KotlinLanguageVersion.v2_3_10, .v2_3_10)
        XCTAssertEqual(OptimizationLevel.O0.rawValue, 0)
        XCTAssertEqual(OptimizationLevel.O1.rawValue, 1)
        XCTAssertEqual(OptimizationLevel.O2.rawValue, 2)
        XCTAssertEqual(OptimizationLevel.O3.rawValue, 3)
        XCTAssertEqual(EmitMode.executable.rawValue, "executable")
        XCTAssertEqual(EmitMode.object.rawValue, "object")
        XCTAssertEqual(EmitMode.llvmIR.rawValue, "llvmIR")
        XCTAssertEqual(EmitMode.kirDump.rawValue, "kirDump")
        XCTAssertEqual(EmitMode.library.rawValue, "library")
    }

    func testCompilerVersionWithNilGitHash() {
        let version = CompilerVersion(major: 0, minor: 0, patch: 1, gitHash: nil)
        XCTAssertEqual(version.major, 0)
        XCTAssertEqual(version.minor, 0)
        XCTAssertEqual(version.patch, 1)
        XCTAssertNil(version.gitHash)
    }

    func testTargetTripleWithNilOSVersion() {
        let triple = TargetTriple(arch: "x86_64", vendor: "pc", os: "linux", osVersion: nil)
        XCTAssertEqual(triple.arch, "x86_64")
        XCTAssertEqual(triple.vendor, "pc")
        XCTAssertEqual(triple.os, "linux")
        XCTAssertNil(triple.osVersion)
    }

    func testDeprecatedEmitsDebugInfoGetterAndSetter() {
        var options = CompilerOptions(
            moduleName: "M",
            inputs: ["a.kt"],
            outputPath: "out",
            emit: .object,
            target: TargetTriple(arch: "arm64", vendor: "apple", os: "macosx", osVersion: nil),
            debugInfo: false
        )
        XCTAssertFalse(options.emitsDebugInfo)
        options.emitsDebugInfo = true
        XCTAssertTrue(options.emitsDebugInfo)
        XCTAssertTrue(options.debugInfo)
    }

    func testDeprecatedInitWithEmitsDebugInfo() {
        let options = CompilerOptions(
            moduleName: "DeprecatedModule",
            inputs: ["x.kt"],
            outputPath: "out.o",
            emit: .executable,
            searchPaths: ["/sp"],
            libraryPaths: ["/lp"],
            linkLibraries: ["z"],
            target: TargetTriple(arch: "arm64", vendor: "apple", os: "macosx", osVersion: "14.0"),
            optLevel: .O2,
            emitsDebugInfo: true,
            frontendFlags: ["-f1"],
            irFlags: ["-i1"],
            runtimeFlags: ["-r1"]
        )
        XCTAssertEqual(options.moduleName, "DeprecatedModule")
        XCTAssertEqual(options.inputs, ["x.kt"])
        XCTAssertEqual(options.outputPath, "out.o")
        XCTAssertEqual(options.emit, .executable)
        XCTAssertEqual(options.searchPaths, ["/sp"])
        XCTAssertEqual(options.libraryPaths, ["/lp"])
        XCTAssertEqual(options.linkLibraries, ["z"])
        XCTAssertEqual(options.optLevel, .O2)
        XCTAssertTrue(options.debugInfo)
        XCTAssertTrue(options.emitsDebugInfo)
        XCTAssertEqual(options.frontendFlags, ["-f1"])
        XCTAssertEqual(options.irFlags, ["-i1"])
        XCTAssertEqual(options.runtimeFlags, ["-r1"])
    }

    func testDeprecatedInitWithEmitsDebugInfoDefaultArguments() {
        let options = CompilerOptions(
            moduleName: "M2",
            inputs: ["b.kt"],
            outputPath: "out2",
            emit: .llvmIR,
            target: TargetTriple(arch: "x86_64", vendor: "pc", os: "linux", osVersion: nil),
            emitsDebugInfo: false
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

    func testEmitModeKirDump() {
        XCTAssertEqual(EmitMode.kirDump.rawValue, "kirDump")
    }

    func testOptimizationLevelEquality() {
        XCTAssertEqual(OptimizationLevel.O1, OptimizationLevel.O1)
        XCTAssertNotEqual(OptimizationLevel.O0, OptimizationLevel.O3)
    }

    func testTargetTripleEquality() {
        let a = TargetTriple(arch: "arm64", vendor: "apple", os: "macosx", osVersion: "14.0")
        let b = TargetTriple(arch: "arm64", vendor: "apple", os: "macosx", osVersion: "14.0")
        let c = TargetTriple(arch: "x86_64", vendor: "pc", os: "linux", osVersion: nil)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testCompilerVersionEquality() {
        let a = CompilerVersion(major: 1, minor: 0, patch: 0, gitHash: "abc")
        let b = CompilerVersion(major: 1, minor: 0, patch: 0, gitHash: "abc")
        let c = CompilerVersion(major: 2, minor: 0, patch: 0, gitHash: nil)
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}
