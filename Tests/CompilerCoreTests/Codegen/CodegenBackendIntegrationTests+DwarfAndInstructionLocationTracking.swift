@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testLlvmCapiBackendDebugObjectContainsDwarfSections() throws {
        let diagnostics = DiagnosticEngine()
        let interner = StringInterner()
        let types = TypeSystem()
        let arena = KIRArena()

        let mainSym = SymbolID(rawValue: 4200)
        let expr0 = arena.appendExpr(.intLiteral(0))
        let function = KIRFunction(
            symbol: mainSym, name: interner.intern("main"), params: [],
            returnType: types.unitType,
            body: [.constValue(result: expr0, value: .intLiteral(0)), .returnValue(expr0)],
            isSuspend: false, isInline: false
        )
        let functionID = arena.appendDecl(.function(function))
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [functionID])], arena: arena
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
            module: module, runtime: runtime,
            outputObjectPath: debugObjPath, interner: interner
        )
        try backendNoDebug.emitObject(
            module: module, runtime: runtime,
            outputObjectPath: noDebugObjPath, interner: interner
        )

        let debugData = try Data(contentsOf: URL(fileURLWithPath: debugObjPath))
        let noDebugData = try Data(contentsOf: URL(fileURLWithPath: noDebugObjPath))

        XCTAssertGreaterThan(debugData.count, 0)
        XCTAssertGreaterThan(noDebugData.count, 0)
        XCTAssertGreaterThan(
            debugData.count, noDebugData.count,
            "Debug object should be larger due to DWARF sections"
        )
    }

    func testInstructionLocationsPreservedThroughTransformFunctions() {
        let interner = StringInterner()
        let types = TypeSystem()
        let arena = KIRArena()

        let sym = SymbolID(rawValue: 4300)
        let expr0 = arena.appendExpr(.intLiteral(1))
        _ = arena.appendExpr(.intLiteral(2))

        let sourceRange = SourceRange(
            start: SourceLocation(file: FileID(rawValue: 0), offset: 10),
            end: SourceLocation(file: FileID(rawValue: 0), offset: 20)
        )

        let function = KIRFunction(
            symbol: sym, name: interner.intern("test"), params: [],
            returnType: types.unitType,
            body: [.constValue(result: expr0, value: .intLiteral(1)), .returnValue(expr0)],
            isSuspend: false, isInline: false,
            instructionLocations: [sourceRange, sourceRange]
        )
        _ = arena.appendDecl(.function(function))

        arena.transformFunctions { func0 in
            var updated = func0
            updated.instructionLocations = [nil, nil]
            return updated
        }

        if case let .function(transformed)? = arena.decl(KIRDeclID(rawValue: 0)) {
            XCTAssertEqual(transformed.instructionLocations.count, 2)
            XCTAssertNil(transformed.instructionLocations[0])
            XCTAssertNil(transformed.instructionLocations[1])
        } else {
            XCTFail("Expected function declaration")
        }
    }
}
