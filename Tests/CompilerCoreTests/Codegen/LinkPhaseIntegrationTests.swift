import Foundation
import XCTest
@testable import CompilerCore

final class LinkPhaseIntegrationTests: XCTestCase {

    func testLinkPhaseAutoLinksKotlinLibraryObjectForCrossModuleCall() throws {
        let librarySource = """
        package extdemo
        fun plus(v: Int) = v + 1
        """
        try withTemporaryFile(contents: librarySource) { libraryPath in
            let libraryBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let libraryCtx = makeCompilationContext(
                inputs: [libraryPath],
                moduleName: "ExtDemo",
                emit: .library,
                outputPath: libraryBase
            )
            try runToKIR(libraryCtx)
            try LoweringPhase().run(libraryCtx)
            try CodegenPhase().run(libraryCtx)

            let appSource = """
            import extdemo.plus
            fun main() = plus(41)
            """
            try withTemporaryFile(contents: appSource) { appPath in
                let outputPath = FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString)
                    .path
                let appCtx = makeCompilationContext(
                    inputs: [appPath],
                    moduleName: "CrossModuleApp",
                    emit: .executable,
                    outputPath: outputPath,
                    searchPaths: [libraryBase + ".kklib"]
                )
                try runToKIR(appCtx)
                try LoweringPhase().run(appCtx)
                try CodegenPhase().run(appCtx)
                try LinkPhase().run(appCtx)

                XCTAssertTrue(FileManager.default.fileExists(atPath: outputPath))
                do {
                    _ = try CommandRunner.run(executable: outputPath, arguments: [])
                    XCTFail("Expected non-zero exit")
                    return
                } catch CommandRunnerError.nonZeroExit(let failed) {
                    XCTAssertEqual(failed.exitCode, 42)
                } catch {
                    XCTFail("Unexpected error: \(error)")
                }
            }
        }
    }

    func testLinkPhaseReportsMissingMainAndCanLinkExecutable() throws {
        try withTemporaryFile(contents: "fun notMain() = 0") { path in
            let out = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = makeCompilationContext(inputs: [path], moduleName: "NoMain", emit: .executable, outputPath: out)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)

            XCTAssertThrowsError(try LinkPhase().run(ctx))
            XCTAssertTrue(ctx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-LINK-0002" })
        }

        try withTemporaryFile(contents: "fun main() = 0") { path in
            let out = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let options = CompilerOptions(
                moduleName: "HasMain",
                inputs: [path],
                outputPath: out,
                emit: .executable,
                target: defaultTargetTriple()
            )
            let ctx = CompilationContext(
                options: options,
                sourceManager: SourceManager(),
                diagnostics: DiagnosticEngine(),
                interner: StringInterner()
            )

            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            XCTAssertTrue(FileManager.default.fileExists(atPath: out))
        }
    }

    func testLinkPhaseWrapperReportsTopLevelThrownException() throws {
        let source = """
        fun main(): Any? {
            val arr = IntArray(1)
            return arr[2]
        }
        """
        try withTemporaryFile(contents: source) { path in
            let out = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = makeCompilationContext(inputs: [path], moduleName: "TopLevelThrow", emit: .executable, outputPath: out)
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            XCTAssertTrue(FileManager.default.fileExists(atPath: out))

            let result: CommandResult
            do {
                result = try CommandRunner.run(executable: out, arguments: [])
                XCTFail("Expected executable to fail on unhandled top-level exception.")
                return
            } catch CommandRunnerError.nonZeroExit(let failed) {
                result = failed
            } catch {
                XCTFail("Unexpected error: \(error)")
                return
            }

            XCTAssertEqual(result.exitCode, 1)
            XCTAssertTrue(result.stderr.contains("KSWIFTK-LINK-0003"))
            XCTAssertTrue(result.stderr.contains("KSwiftK panic"))
        }
    }

    func testLinkPhaseAutoLinksKklibManifestObjectsAndDeduplicates() throws {
        let fm = FileManager.default
        let workspaceDir = fm.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try fm.createDirectory(at: workspaceDir, withIntermediateDirectories: true)
        defer { try? fm.removeItem(at: workspaceDir) }

        let libraryDir = workspaceDir.appendingPathComponent("NativePlus.kklib")
        let objectsDir = libraryDir.appendingPathComponent("objects")
        try fm.createDirectory(at: objectsDir, withIntermediateDirectories: true)

        let cSource = """
        #include <stdint.h>
        intptr_t plus(intptr_t value, intptr_t* outThrown) {
            (void)outThrown;
            return value + 1;
        }
        """
        let cSourceURL = workspaceDir.appendingPathComponent("native_plus.c")
        try cSource.write(to: cSourceURL, atomically: true, encoding: .utf8)

        let objectURL = objectsDir.appendingPathComponent("native_plus.o")
        let clangPath = CommandRunner.resolveExecutable("clang", fallback: "/usr/bin/clang")
        _ = try CommandRunner.run(
            executable: clangPath,
            arguments: ["-c", cSourceURL.path, "-o", objectURL.path]
        )

        let manifest = """
        {
          "formatVersion": 1,
          "moduleName": "NativePlus",
          "kotlinLanguageVersion": "2.3.10",
          "compilerVersion": "0.1.0",
          "target": "arm64-apple-macosx",
          "objects": ["objects/native_plus.o", "objects/native_plus.o"],
          "metadata": "metadata.bin"
        }
        """
        try manifest.write(
            to: libraryDir.appendingPathComponent("manifest.json"),
            atomically: true,
            encoding: .utf8
        )
        try "symbols=0\n".write(
            to: libraryDir.appendingPathComponent("metadata.bin"),
            atomically: true,
            encoding: .utf8
        )

        let appSource = """
        fun main() = plus(41)
        """
        try withTemporaryFile(contents: appSource) { appPath in
            let outputPath = workspaceDir.appendingPathComponent("AppExecutable").path
            let appCtx = makeCompilationContext(
                inputs: [appPath],
                moduleName: "App",
                emit: .executable,
                outputPath: outputPath,
                searchPaths: [libraryDir.path, workspaceDir.path]
            )
            try runToKIR(appCtx)
            try LoweringPhase().run(appCtx)
            try CodegenPhase().run(appCtx)
            try LinkPhase().run(appCtx)

            XCTAssertTrue(fm.fileExists(atPath: outputPath))
            do {
                _ = try CommandRunner.run(executable: outputPath, arguments: [])
                XCTFail("Expected non-zero exit")
                return
            } catch CommandRunnerError.nonZeroExit(let failed) {
                XCTAssertEqual(failed.exitCode, 42)
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }

    func testLinkPhaseSkipsForObjectEmitMode() throws {
        let objectCtx = makeCompilationContext(inputs: [], moduleName: "SkipLink", emit: .object)
        XCTAssertNoThrow(try LinkPhase().run(objectCtx))
    }

    func testLinkPhaseFailsWhenObjectIsMissingForExecutable() throws {
        let missingObjectCtx = makeCompilationContext(inputs: [], moduleName: "MissingObj", emit: .executable)
        XCTAssertThrowsError(try LinkPhase().run(missingObjectCtx))
    }

    func testLinkPhaseFailsWhenKIRModuleIsMissing() throws {
        let tempObjectURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".o")
        try Data().write(to: tempObjectURL)

        let noKirCtx = makeCompilationContext(inputs: [], moduleName: "NoKir", emit: .executable)
        noKirCtx.generatedObjectPath = tempObjectURL.path
        XCTAssertThrowsError(try LinkPhase().run(noKirCtx))
    }

    func testLinkPhasePassesDebugFlagToClang() throws {
        let source = "fun main() = 0"
        try withTemporaryFile(contents: source) { path in
            let outputPath = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let options = CompilerOptions(
                moduleName: "DebugLink",
                inputs: [path],
                outputPath: outputPath,
                emit: .executable,
                target: defaultTargetTriple(),
                debugInfo: true
            )
            let ctx = CompilationContext(
                options: options,
                sourceManager: SourceManager(),
                diagnostics: DiagnosticEngine(),
                interner: StringInterner()
            )

            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            XCTAssertTrue(FileManager.default.fileExists(atPath: outputPath))
        }
    }

    func testLinkPhaseReportsDiagnosticForUnsupportedTargetArchitecture() throws {
        let tempObjectURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".o")
        try Data().write(to: tempObjectURL)

        let interner = StringInterner()
        let arena = KIRArena()
        let mainSym = SymbolID(rawValue: 99)
        let mainDecl = arena.appendDecl(.function(KIRFunction(
            symbol: mainSym,
            name: interner.intern("main"),
            params: [],
            returnType: TypeSystem().unitType,
            body: [.returnUnit],
            isSuspend: false,
            isInline: false
        )))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [mainDecl])], arena: arena)

        let badTargetOptions = CompilerOptions(
            moduleName: "BadTarget",
            inputs: [],
            outputPath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path,
            emit: .executable,
            target: TargetTriple(arch: "definitely-bad-arch", vendor: "apple", os: "macosx", osVersion: nil)
        )
        let badTargetCtx = CompilationContext(
            options: badTargetOptions,
            sourceManager: SourceManager(),
            diagnostics: DiagnosticEngine(),
            interner: interner
        )
        badTargetCtx.generatedObjectPath = tempObjectURL.path
        badTargetCtx.kir = module

        XCTAssertThrowsError(try LinkPhase().run(badTargetCtx))
        XCTAssertTrue(badTargetCtx.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-LINK-0001" })
    }
}
