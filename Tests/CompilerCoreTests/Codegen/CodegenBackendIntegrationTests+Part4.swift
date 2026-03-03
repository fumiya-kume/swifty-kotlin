@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testSyntheticCBackendObjectContainsDebugSectionWhenDebugInfoEnabled() throws {
        let source = "fun main() = 0"
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let options = CompilerOptions(
                moduleName: "DebugObj",
                inputs: [path],
                outputPath: outputBase,
                emit: .object,
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

            let objectPath = try XCTUnwrap(ctx.generatedObjectPath)
            let objectData = try Data(contentsOf: URL(fileURLWithPath: objectPath))
            XCTAssertGreaterThan(objectData.count, 0)

            let noDebugBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let noDebugOptions = CompilerOptions(
                moduleName: "NoDebugObj",
                inputs: [path],
                outputPath: noDebugBase,
                emit: .object,
                target: defaultTargetTriple(),
                debugInfo: false
            )
            let noDebugCtx = CompilationContext(
                options: noDebugOptions,
                sourceManager: SourceManager(),
                diagnostics: DiagnosticEngine(),
                interner: StringInterner()
            )
            try runToKIR(noDebugCtx)
            try LoweringPhase().run(noDebugCtx)
            try CodegenPhase().run(noDebugCtx)

            let noDebugObjectPath = try XCTUnwrap(noDebugCtx.generatedObjectPath)
            let noDebugData = try Data(contentsOf: URL(fileURLWithPath: noDebugObjectPath))
            XCTAssertGreaterThan(noDebugData.count, 0)
            XCTAssertGreaterThan(objectData.count, noDebugData.count)
        }
    }

    func testSyntheticCBackendLLVMIRContainsDebugFlagWhenDebugInfoEnabled() throws {
        let source = "fun main() = 0"
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let options = CompilerOptions(
                moduleName: "DebugIR",
                inputs: [path],
                outputPath: outputBase,
                emit: .llvmIR,
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

            let irPath = try XCTUnwrap(ctx.generatedLLVMIRPath)
            let irContent = try String(contentsOfFile: irPath, encoding: .utf8)
            XCTAssertTrue(
                irContent.contains("!llvm.dbg") || irContent.contains("debug") || irContent.contains("DW_TAG"),
                "LLVM IR should contain debug metadata when -g is enabled"
            )
        }
    }

    func testLlvmCapiBackendPassesDebugInfoToNativeEmitter() throws {
        let diagnostics = DiagnosticEngine()
        let interner = StringInterner()
        let types = TypeSystem()
        let arena = KIRArena()
        let function = KIRFunction(
            symbol: SymbolID(rawValue: 3000),
            name: interner.intern("main"),
            params: [],
            returnType: types.unitType,
            body: [.returnUnit],
            isSuspend: false,
            isInline: false
        )
        let functionID = arena.appendDecl(.function(function))
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [functionID])],
            arena: arena
        )

        let backendWithDebug = LLVMCAPIBackend(
            target: defaultTargetTriple(),
            optLevel: .O0,
            debugInfo: true,
            diagnostics: diagnostics,
            isStrictMode: false
        )
        let backendNoDebug = LLVMCAPIBackend(
            target: defaultTargetTriple(),
            optLevel: .O0,
            debugInfo: false,
            diagnostics: diagnostics,
            isStrictMode: false
        )

        let runtime = RuntimeLinkInfo(libraryPaths: [], libraries: [], extraObjects: [])

        if llvmCapiBindingsAvailable() {
            let debugIRPath = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + "_debug.ll").path
            let noDebugIRPath = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + "_nodebug.ll").path
            defer {
                try? FileManager.default.removeItem(atPath: debugIRPath)
                try? FileManager.default.removeItem(atPath: noDebugIRPath)
            }

            try backendWithDebug.emitLLVMIR(
                module: module,
                runtime: runtime,
                outputIRPath: debugIRPath,
                interner: interner
            )
            try backendNoDebug.emitLLVMIR(
                module: module,
                runtime: runtime,
                outputIRPath: noDebugIRPath,
                interner: interner
            )

            let debugIR = try String(contentsOfFile: debugIRPath, encoding: .utf8)
            let noDebugIR = try String(contentsOfFile: noDebugIRPath, encoding: .utf8)

            if LLVMCAPIBindings.load()?.debugInfoAvailable == true {
                XCTAssertTrue(debugIR.contains("!llvm.dbg") || debugIR.count > noDebugIR.count)
            }
            XCTAssertFalse(noDebugIR.contains("!llvm.dbg"))
        }
    }

    func testLlvmCapiBindingsReportsDebugInfoAvailability() {
        guard let bindings = LLVMCAPIBindings.load() else {
            return
        }
        _ = bindings.debugInfoAvailable
    }

    func testLlvmCapiBindingsReportsDebugLocationAvailability() {
        guard let bindings = LLVMCAPIBindings.load() else {
            return
        }
        _ = bindings.debugLocationAvailable
    }

    func testLlvmCapiBackendDebugIRContainsDebugLocationMetadata() throws {
        let diagnostics = DiagnosticEngine()
        let interner = StringInterner()
        let types = TypeSystem()
        let arena = KIRArena()

        let mainSym = SymbolID(rawValue: 4000)
        let e0 = arena.appendExpr(.intLiteral(42))
        let function = KIRFunction(
            symbol: mainSym,
            name: interner.intern("main"),
            params: [],
            returnType: types.unitType,
            body: [
                .constValue(result: e0, value: .intLiteral(42)),
                .returnValue(e0),
            ],
            isSuspend: false,
            isInline: false
        )
        let functionID = arena.appendDecl(.function(function))
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [functionID])],
            arena: arena
        )

        let backend = LLVMCAPIBackend(
            target: defaultTargetTriple(),
            optLevel: .O0,
            debugInfo: true,
            diagnostics: diagnostics,
            isStrictMode: false
        )

        let runtime = RuntimeLinkInfo(libraryPaths: [], libraries: [], extraObjects: [])

        guard llvmCapiBindingsAvailable() else { return }
        guard LLVMCAPIBindings.load()?.debugInfoAvailable == true else { return }
        guard LLVMCAPIBindings.load()?.debugLocationAvailable == true else { return }

        let irPath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "_dbgloc.ll").path
        defer { try? FileManager.default.removeItem(atPath: irPath) }

        try backend.emitLLVMIR(
            module: module,
            runtime: runtime,
            outputIRPath: irPath,
            interner: interner
        )

        let ir = try String(contentsOfFile: irPath, encoding: .utf8)
        // When debug locations are set, instructions carry !dbg metadata
        // references and DISubprogram / DILocation entries appear in the IR.
        XCTAssertTrue(ir.contains("!dbg"), "Expected !dbg metadata references in IR when debugInfo is enabled")
        XCTAssertTrue(ir.contains("DISubprogram"), "Expected DISubprogram metadata in IR")
    }

    func testLlvmCapiBackendDebugIRContainsLocalVariableMetadata() throws {
        let diagnostics = DiagnosticEngine()
        let interner = StringInterner()
        let types = TypeSystem()
        let arena = KIRArena()

        let mainSym = SymbolID(rawValue: 4100)
        let localSym = SymbolID(rawValue: 4101)
        let e0 = arena.appendExpr(.intLiteral(42))
        let e1 = arena.appendExpr(.symbolRef(localSym))
        let function = KIRFunction(
            symbol: mainSym,
            name: interner.intern("main"),
            params: [],
            returnType: types.unitType,
            body: [
                .constValue(result: e0, value: .intLiteral(42)),
                .constValue(result: e1, value: .symbolRef(localSym)),
                .returnValue(e0),
            ],
            isSuspend: false,
            isInline: false
        )
        let functionID = arena.appendDecl(.function(function))
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [functionID])],
            arena: arena
        )

        let backend = LLVMCAPIBackend(
            target: defaultTargetTriple(),
            optLevel: .O0,
            debugInfo: true,
            diagnostics: diagnostics,
            isStrictMode: false
        )

        let runtime = RuntimeLinkInfo(libraryPaths: [], libraries: [], extraObjects: [])

        guard llvmCapiBindingsAvailable() else { return }
        guard LLVMCAPIBindings.load()?.debugInfoAvailable == true else { return }
        guard LLVMCAPIBindings.load()?.localVariableAvailable == true else { return }

        let irPath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "_localvar.ll").path
        defer { try? FileManager.default.removeItem(atPath: irPath) }

        try backend.emitLLVMIR(
            module: module,
            runtime: runtime,
            outputIRPath: irPath,
            interner: interner
        )

        let ir = try String(contentsOfFile: irPath, encoding: .utf8)
        // When local variable debug info is emitted, the IR should contain
        // DILocalVariable entries and llvm.dbg.declare intrinsic calls.
        XCTAssertTrue(
            ir.contains("DILocalVariable") || ir.contains("dbg.declare"),
            "Expected DILocalVariable or dbg.declare in IR for local variable debug info"
        )
    }

    func testLlvmCapiBackendDebugObjectContainsDwarfSections() throws {
        let diagnostics = DiagnosticEngine()
        let interner = StringInterner()
        let types = TypeSystem()
        let arena = KIRArena()

        let mainSym = SymbolID(rawValue: 4200)
        let e0 = arena.appendExpr(.intLiteral(0))
        let function = KIRFunction(
            symbol: mainSym,
            name: interner.intern("main"),
            params: [],
            returnType: types.unitType,
            body: [
                .constValue(result: e0, value: .intLiteral(0)),
                .returnValue(e0),
            ],
            isSuspend: false,
            isInline: false
        )
        let functionID = arena.appendDecl(.function(function))
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [functionID])],
            arena: arena
        )

        let backendDebug = LLVMCAPIBackend(
            target: defaultTargetTriple(),
            optLevel: .O0,
            debugInfo: true,
            diagnostics: diagnostics,
            isStrictMode: false
        )
        let backendNoDebug = LLVMCAPIBackend(
            target: defaultTargetTriple(),
            optLevel: .O0,
            debugInfo: false,
            diagnostics: diagnostics,
            isStrictMode: false
        )

        let runtime = RuntimeLinkInfo(libraryPaths: [], libraries: [], extraObjects: [])

        guard llvmCapiBindingsAvailable() else { return }
        guard LLVMCAPIBindings.load()?.debugInfoAvailable == true else { return }

        let debugObjPath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "_debug.o").path
        let noDebugObjPath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + "_nodebug.o").path
        defer {
            try? FileManager.default.removeItem(atPath: debugObjPath)
            try? FileManager.default.removeItem(atPath: noDebugObjPath)
        }

        try backendDebug.emitObject(
            module: module,
            runtime: runtime,
            outputObjectPath: debugObjPath,
            interner: interner
        )
        try backendNoDebug.emitObject(
            module: module,
            runtime: runtime,
            outputObjectPath: noDebugObjPath,
            interner: interner
        )

        let debugData = try Data(contentsOf: URL(fileURLWithPath: debugObjPath))
        let noDebugData = try Data(contentsOf: URL(fileURLWithPath: noDebugObjPath))

        XCTAssertGreaterThan(debugData.count, 0, "Debug object file should not be empty")
        XCTAssertGreaterThan(noDebugData.count, 0, "Non-debug object file should not be empty")
        // The debug-enabled object file must be strictly larger than the
        // non-debug object file because it contains DWARF .debug_info,
        // .debug_line, and .debug_abbrev sections.
        XCTAssertGreaterThan(
            debugData.count, noDebugData.count,
            "Debug object file should be larger than non-debug due to DWARF sections"
        )
    }

    func testInstructionLocationsPreservedThroughTransformFunctions() {
        let interner = StringInterner()
        let types = TypeSystem()
        let arena = KIRArena()

        let sym = SymbolID(rawValue: 4300)
        let e0 = arena.appendExpr(.intLiteral(1))
        let e1 = arena.appendExpr(.intLiteral(2))

        let sourceRange = SourceRange(
            start: SourceLocation(file: FileID(rawValue: 0), offset: 10),
            end: SourceLocation(file: FileID(rawValue: 0), offset: 20)
        )

        let function = KIRFunction(
            symbol: sym,
            name: interner.intern("test"),
            params: [],
            returnType: types.unitType,
            body: [
                .constValue(result: e0, value: .intLiteral(1)),
                .returnValue(e0),
            ],
            instructionLocations: [sourceRange, sourceRange],
            isSuspend: false,
            isInline: false
        )
        _ = arena.appendDecl(.function(function))

        // When transformFunctions is called with a transform that changes
        // instructionLocations but not body, the change should still be recorded.
        arena.transformFunctions { fn in
            var updated = fn
            updated.instructionLocations = [nil, nil]
            return updated
        }

        // Verify the transformation was applied
        if case let .function(transformed) = arena.decl(KIRDeclID(rawValue: 0)) {
            XCTAssertEqual(transformed.instructionLocations.count, 2)
            XCTAssertNil(transformed.instructionLocations[0])
            XCTAssertNil(transformed.instructionLocations[1])
        } else {
            XCTFail("Expected function declaration")
        }
    }
}
