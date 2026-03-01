@testable import CompilerCore
import Foundation
import XCTest

extension LoweringPassRegressionTests {
    func testABILoweringBoxesIntArgumentForAnyParameter() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()
        let symbols = SymbolTable()

        let intType = types.make(.primitive(.int, .nonNull))
        let anyNullableType = types.make(.any(.nullable))

        let callerSym = SymbolID(rawValue: 3000)
        let targetSym = SymbolID(rawValue: 3001)
        let targetParamSym = SymbolID(rawValue: 3002)

        let targetName = interner.intern("acceptAny")

        symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [anyNullableType], returnType: types.unitType, valueParameterSymbols: [targetParamSym]),
            for: targetSym
        )

        let argExpr = arena.appendExpr(.intLiteral(42), type: intType)
        let resultExpr = arena.appendExpr(.temporary(1), type: types.unitType)

        let callerFn = KIRFunction(
            symbol: callerSym,
            name: interner.intern("main"),
            params: [],
            returnType: types.unitType,
            body: [
                .call(symbol: targetSym, callee: targetName, arguments: [argExpr], result: resultExpr, canThrow: false, thrownResult: nil),
                .returnUnit,
            ],
            isSuspend: false,
            isInline: false
        )
        let targetFn = KIRFunction(
            symbol: targetSym,
            name: targetName,
            params: [KIRParameter(symbol: targetParamSym, type: anyNullableType)],
            returnType: types.unitType,
            body: [.returnUnit],
            isSuspend: false,
            isInline: false
        )

        let callerID = arena.appendDecl(.function(callerFn))
        _ = arena.appendDecl(.function(targetFn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [callerID])], arena: arena)

        let sema = SemaModule(symbols: symbols, types: types, bindings: BindingTable(), diagnostics: DiagnosticEngine())
        let ctx = CompilationContext(
            options: CompilerOptions(moduleName: "ABIBoxInt", inputs: [], outputPath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path, emit: .kirDump, target: defaultTargetTriple()),
            sourceManager: SourceManager(),
            diagnostics: DiagnosticEngine(),
            interner: interner
        )
        ctx.kir = module
        ctx.sema = sema

        try LoweringPhase().run(ctx)

        let lowered = try findKIRFunction(named: "main", in: module, interner: interner)
        let callees = extractCallees(from: lowered.body, interner: interner)
        XCTAssertTrue(callees.contains("kk_box_int"), "Expected kk_box_int call for Int -> Any? boxing, got: \(callees)")
    }

    func testABILoweringBoxesBoolArgumentForAnyParameter() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()
        let symbols = SymbolTable()

        let boolType = types.make(.primitive(.boolean, .nonNull))
        let anyNullableType = types.make(.any(.nullable))

        let callerSym = SymbolID(rawValue: 3100)
        let targetSym = SymbolID(rawValue: 3101)
        let targetParamSym = SymbolID(rawValue: 3102)

        let targetName = interner.intern("acceptAny")

        symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [anyNullableType], returnType: types.unitType, valueParameterSymbols: [targetParamSym]),
            for: targetSym
        )

        let argExpr = arena.appendExpr(.boolLiteral(true), type: boolType)
        let resultExpr = arena.appendExpr(.temporary(1), type: types.unitType)

        let callerFn = KIRFunction(
            symbol: callerSym,
            name: interner.intern("main"),
            params: [],
            returnType: types.unitType,
            body: [
                .call(symbol: targetSym, callee: targetName, arguments: [argExpr], result: resultExpr, canThrow: false, thrownResult: nil),
                .returnUnit,
            ],
            isSuspend: false,
            isInline: false
        )
        let targetFn = KIRFunction(
            symbol: targetSym,
            name: targetName,
            params: [KIRParameter(symbol: targetParamSym, type: anyNullableType)],
            returnType: types.unitType,
            body: [.returnUnit],
            isSuspend: false,
            isInline: false
        )

        let callerID = arena.appendDecl(.function(callerFn))
        _ = arena.appendDecl(.function(targetFn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [callerID])], arena: arena)

        let sema = SemaModule(symbols: symbols, types: types, bindings: BindingTable(), diagnostics: DiagnosticEngine())
        let ctx = CompilationContext(
            options: CompilerOptions(moduleName: "ABIBoxBool", inputs: [], outputPath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path, emit: .kirDump, target: defaultTargetTriple()),
            sourceManager: SourceManager(),
            diagnostics: DiagnosticEngine(),
            interner: interner
        )
        ctx.kir = module
        ctx.sema = sema

        try LoweringPhase().run(ctx)

        let lowered = try findKIRFunction(named: "main", in: module, interner: interner)
        let callees = extractCallees(from: lowered.body, interner: interner)
        XCTAssertTrue(callees.contains("kk_box_bool"), "Expected kk_box_bool call for Bool -> Any? boxing, got: \(callees)")
    }

    func testABILoweringBoxesIntToNullableIntParameter() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()
        let symbols = SymbolTable()

        let intType = types.make(.primitive(.int, .nonNull))
        let nullableIntType = types.make(.primitive(.int, .nullable))

        let callerSym = SymbolID(rawValue: 3200)
        let targetSym = SymbolID(rawValue: 3201)
        let targetParamSym = SymbolID(rawValue: 3202)

        let targetName = interner.intern("acceptNullableInt")

        symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [nullableIntType], returnType: types.unitType, valueParameterSymbols: [targetParamSym]),
            for: targetSym
        )

        let argExpr = arena.appendExpr(.intLiteral(7), type: intType)
        let resultExpr = arena.appendExpr(.temporary(1), type: types.unitType)

        let callerFn = KIRFunction(
            symbol: callerSym,
            name: interner.intern("main"),
            params: [],
            returnType: types.unitType,
            body: [
                .call(symbol: targetSym, callee: targetName, arguments: [argExpr], result: resultExpr, canThrow: false, thrownResult: nil),
                .returnUnit,
            ],
            isSuspend: false,
            isInline: false
        )
        let targetFn = KIRFunction(
            symbol: targetSym,
            name: targetName,
            params: [KIRParameter(symbol: targetParamSym, type: nullableIntType)],
            returnType: types.unitType,
            body: [.returnUnit],
            isSuspend: false,
            isInline: false
        )

        let callerID = arena.appendDecl(.function(callerFn))
        _ = arena.appendDecl(.function(targetFn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [callerID])], arena: arena)

        let sema = SemaModule(symbols: symbols, types: types, bindings: BindingTable(), diagnostics: DiagnosticEngine())
        let ctx = CompilationContext(
            options: CompilerOptions(moduleName: "ABIBoxNullableInt", inputs: [], outputPath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path, emit: .kirDump, target: defaultTargetTriple()),
            sourceManager: SourceManager(),
            diagnostics: DiagnosticEngine(),
            interner: interner
        )
        ctx.kir = module
        ctx.sema = sema

        try LoweringPhase().run(ctx)

        let lowered = try findKIRFunction(named: "main", in: module, interner: interner)
        let callees = extractCallees(from: lowered.body, interner: interner)
        XCTAssertTrue(callees.contains("kk_box_int"), "Expected kk_box_int call for Int -> Int? boxing, got: \(callees)")
    }

    func testABILoweringUnboxesAnyReturnToIntResult() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()
        let symbols = SymbolTable()

        let intType = types.make(.primitive(.int, .nonNull))
        let anyNullableType = types.make(.any(.nullable))

        let callerSym = SymbolID(rawValue: 3300)
        let targetSym = SymbolID(rawValue: 3301)

        let targetName = interner.intern("getAny")

        symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [], returnType: anyNullableType),
            for: targetSym
        )

        let resultExpr = arena.appendExpr(.temporary(0), type: intType)

        let callerFn = KIRFunction(
            symbol: callerSym,
            name: interner.intern("main"),
            params: [],
            returnType: types.unitType,
            body: [
                .call(symbol: targetSym, callee: targetName, arguments: [], result: resultExpr, canThrow: false, thrownResult: nil),
                .returnUnit,
            ],
            isSuspend: false,
            isInline: false
        )
        let targetFn = KIRFunction(
            symbol: targetSym,
            name: targetName,
            params: [],
            returnType: anyNullableType,
            body: [.returnUnit],
            isSuspend: false,
            isInline: false
        )

        let callerID = arena.appendDecl(.function(callerFn))
        _ = arena.appendDecl(.function(targetFn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [callerID])], arena: arena)

        let sema = SemaModule(symbols: symbols, types: types, bindings: BindingTable(), diagnostics: DiagnosticEngine())
        let ctx = CompilationContext(
            options: CompilerOptions(moduleName: "ABIUnboxAny", inputs: [], outputPath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path, emit: .kirDump, target: defaultTargetTriple()),
            sourceManager: SourceManager(),
            diagnostics: DiagnosticEngine(),
            interner: interner
        )
        ctx.kir = module
        ctx.sema = sema

        try LoweringPhase().run(ctx)

        let lowered = try findKIRFunction(named: "main", in: module, interner: interner)
        let callees = extractCallees(from: lowered.body, interner: interner)
        XCTAssertTrue(callees.contains("kk_unbox_int"), "Expected kk_unbox_int call for Any? -> Int unboxing, got: \(callees)")
    }

    func testABILoweringUnboxesNullableIntReturnToNonNullInt() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()
        let symbols = SymbolTable()

        let intType = types.make(.primitive(.int, .nonNull))
        let nullableIntType = types.make(.primitive(.int, .nullable))

        let callerSym = SymbolID(rawValue: 3400)
        let targetSym = SymbolID(rawValue: 3401)

        let targetName = interner.intern("getNullableInt")

        symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [], returnType: nullableIntType),
            for: targetSym
        )

        let resultExpr = arena.appendExpr(.temporary(0), type: intType)

        let callerFn = KIRFunction(
            symbol: callerSym,
            name: interner.intern("main"),
            params: [],
            returnType: types.unitType,
            body: [
                .call(symbol: targetSym, callee: targetName, arguments: [], result: resultExpr, canThrow: false, thrownResult: nil),
                .returnUnit,
            ],
            isSuspend: false,
            isInline: false
        )
        let targetFn = KIRFunction(
            symbol: targetSym,
            name: targetName,
            params: [],
            returnType: nullableIntType,
            body: [.returnUnit],
            isSuspend: false,
            isInline: false
        )

        let callerID = arena.appendDecl(.function(callerFn))
        _ = arena.appendDecl(.function(targetFn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [callerID])], arena: arena)

        let sema = SemaModule(symbols: symbols, types: types, bindings: BindingTable(), diagnostics: DiagnosticEngine())
        let ctx = CompilationContext(
            options: CompilerOptions(moduleName: "ABIUnboxNullableInt", inputs: [], outputPath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path, emit: .kirDump, target: defaultTargetTriple()),
            sourceManager: SourceManager(),
            diagnostics: DiagnosticEngine(),
            interner: interner
        )
        ctx.kir = module
        ctx.sema = sema

        try LoweringPhase().run(ctx)

        let lowered = try findKIRFunction(named: "main", in: module, interner: interner)
        let callees = extractCallees(from: lowered.body, interner: interner)
        XCTAssertTrue(callees.contains("kk_unbox_int"), "Expected kk_unbox_int call for Int? -> Int unboxing, got: \(callees)")
    }
}
