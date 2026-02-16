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
}
