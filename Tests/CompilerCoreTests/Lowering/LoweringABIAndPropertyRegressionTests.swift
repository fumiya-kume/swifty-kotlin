import Foundation
import XCTest
@testable import CompilerCore

final class LoweringABIAndPropertyRegressionTests: XCTestCase {
    // MARK: - ABI Boxing/Unboxing Tests

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
                .returnUnit
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
                .returnUnit
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
                .returnUnit
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
                .returnUnit
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
        _ = try runLowering(module: module, interner: interner, moduleName: "ABIUnboxAny", sema: sema)

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
                .returnUnit
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
        _ = try runLowering(module: module, interner: interner, moduleName: "ABIUnboxNullableInt", sema: sema)

        let lowered = try findKIRFunction(named: "main", in: module, interner: interner)
        let callees = extractCallees(from: lowered.body, interner: interner)
        XCTAssertTrue(callees.contains("kk_unbox_int"), "Expected kk_unbox_int call for Int? -> Int unboxing, got: \(callees)")
    }

    func testABILoweringBoxesReturnValueWhenFunctionReturnsAny() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()

        let intType = types.make(.primitive(.int, .nonNull))
        let anyNullableType = types.make(.any(.nullable))

        let fnSym = SymbolID(rawValue: 3500)
        let valueExpr = arena.appendExpr(.intLiteral(42), type: intType)

        let fn = KIRFunction(
            symbol: fnSym,
            name: interner.intern("returnBoxed"),
            params: [],
            returnType: anyNullableType,
            body: [
                .returnValue(valueExpr)
            ],
            isSuspend: false,
            isInline: false
        )

        let fnID = arena.appendDecl(.function(fn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [fnID])], arena: arena)

        let sema = SemaModule(symbols: SymbolTable(), types: types, bindings: BindingTable(), diagnostics: DiagnosticEngine())
        _ = try runLowering(module: module, interner: interner, moduleName: "ABIBoxReturn", sema: sema)

        let lowered = try findKIRFunction(named: "returnBoxed", in: module, interner: interner)
        let callees = extractCallees(from: lowered.body, interner: interner)
        XCTAssertTrue(callees.contains("kk_box_int"), "Expected kk_box_int before returnValue for Any? return type, got: \(callees)")
    }

    func testABILoweringBoxesCopyFromIntToAnySlot() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()

        let intType = types.make(.primitive(.int, .nonNull))
        let anyNullableType = types.make(.any(.nullable))

        let fnSym = SymbolID(rawValue: 3600)
        let fromExpr = arena.appendExpr(.intLiteral(10), type: intType)
        let toExpr = arena.appendExpr(.temporary(1), type: anyNullableType)

        let fn = KIRFunction(
            symbol: fnSym,
            name: interner.intern("copyBoxed"),
            params: [],
            returnType: types.unitType,
            body: [
                .copy(from: fromExpr, to: toExpr),
                .returnUnit
            ],
            isSuspend: false,
            isInline: false
        )

        let fnID = arena.appendDecl(.function(fn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [fnID])], arena: arena)

        let sema = SemaModule(symbols: SymbolTable(), types: types, bindings: BindingTable(), diagnostics: DiagnosticEngine())
        _ = try runLowering(module: module, interner: interner, moduleName: "ABICopyBox", sema: sema)

        let lowered = try findKIRFunction(named: "copyBoxed", in: module, interner: interner)
        let callees = extractCallees(from: lowered.body, interner: interner)
        XCTAssertTrue(callees.contains("kk_box_int"), "Expected kk_box_int for copy Int -> Any?, got: \(callees)")
        // Verify that the copy instruction was replaced (no copy should remain)
        let hasCopy = lowered.body.contains { instruction in
            if case .copy = instruction { return true }
            return false
        }
        XCTAssertFalse(hasCopy, "Expected copy to be replaced with boxing call")
    }

    func testABILoweringUnboxesCopyFromAnyToIntSlot() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()

        let intType = types.make(.primitive(.int, .nonNull))
        let anyNullableType = types.make(.any(.nullable))

        let fnSym = SymbolID(rawValue: 3700)
        let fromExpr = arena.appendExpr(.temporary(0), type: anyNullableType)
        let toExpr = arena.appendExpr(.temporary(1), type: intType)

        let fn = KIRFunction(
            symbol: fnSym,
            name: interner.intern("copyUnboxed"),
            params: [],
            returnType: types.unitType,
            body: [
                .copy(from: fromExpr, to: toExpr),
                .returnUnit
            ],
            isSuspend: false,
            isInline: false
        )

        let fnID = arena.appendDecl(.function(fn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [fnID])], arena: arena)

        let sema = SemaModule(symbols: SymbolTable(), types: types, bindings: BindingTable(), diagnostics: DiagnosticEngine())
        _ = try runLowering(module: module, interner: interner, moduleName: "ABICopyUnbox", sema: sema)

        let lowered = try findKIRFunction(named: "copyUnboxed", in: module, interner: interner)
        let callees = extractCallees(from: lowered.body, interner: interner)
        XCTAssertTrue(callees.contains("kk_unbox_int"), "Expected kk_unbox_int for copy Any? -> Int, got: \(callees)")
        // Verify that the copy instruction was replaced
        let hasCopy = lowered.body.contains { instruction in
            if case .copy = instruction { return true }
            return false
        }
        XCTAssertFalse(hasCopy, "Expected copy to be replaced with unboxing call")
    }

    func testABILoweringBoxesAllPrimitiveTypesForAnyParameter() throws {
        let interner = StringInterner()
        let types = TypeSystem()
        let symbols = SymbolTable()

        let anyNullableType = types.make(.any(.nullable))

        // Define primitives and their expected boxing callees
        let primitives: [(TypeKind, KIRExprKind, String)] = [
            (.primitive(.int, .nonNull), .intLiteral(1), "kk_box_int"),
            (.primitive(.boolean, .nonNull), .boolLiteral(true), "kk_box_bool"),
            (.primitive(.long, .nonNull), .longLiteral(1), "kk_box_long"),
            (.primitive(.float, .nonNull), .floatLiteral(1), "kk_box_float"),
            (.primitive(.double, .nonNull), .doubleLiteral(1), "kk_box_double"),
            (.primitive(.char, .nonNull), .charLiteral(65), "kk_box_char"),
        ]

        for (index, (kind, exprKind, expectedCallee)) in primitives.enumerated() {
            let testArena = KIRArena()
            let primType = types.make(kind)

            let callerSym = SymbolID(rawValue: Int32(4000 + index * 10))
            let targetSym = SymbolID(rawValue: Int32(4001 + index * 10))
            let targetParamSym = SymbolID(rawValue: Int32(4002 + index * 10))
            let targetName = interner.intern("accept_\(expectedCallee)")

            symbols.setFunctionSignature(
                FunctionSignature(parameterTypes: [anyNullableType], returnType: types.unitType, valueParameterSymbols: [targetParamSym]),
                for: targetSym
            )

            let argExpr = testArena.appendExpr(exprKind, type: primType)
            let resultExpr = testArena.appendExpr(.temporary(1), type: types.unitType)

            let callerFn = KIRFunction(
                symbol: callerSym,
                name: interner.intern("main"),
                params: [],
                returnType: types.unitType,
                body: [
                    .call(symbol: targetSym, callee: targetName, arguments: [argExpr], result: resultExpr, canThrow: false, thrownResult: nil),
                    .returnUnit
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

            let callerID = testArena.appendDecl(.function(callerFn))
            _ = testArena.appendDecl(.function(targetFn))
            let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [callerID])], arena: testArena)

            let sema = SemaModule(symbols: symbols, types: types, bindings: BindingTable(), diagnostics: DiagnosticEngine())
            _ = try runLowering(module: module, interner: interner, moduleName: "ABIBoxAll_\(index)", sema: sema)

            let lowered = try findKIRFunction(named: "main", in: module, interner: interner)
            let callees = extractCallees(from: lowered.body, interner: interner)
            XCTAssertTrue(callees.contains(expectedCallee), "Expected \(expectedCallee) for \(kind) -> Any? boxing, got: \(callees)")
        }
    }

    func testABILoweringBoxesCopyFromNonNullIntToNullableIntSlot() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()

        let intType = types.make(.primitive(.int, .nonNull))
        let nullableIntType = types.make(.primitive(.int, .nullable))

        let fnSym = SymbolID(rawValue: 3800)
        let fromExpr = arena.appendExpr(.intLiteral(5), type: intType)
        let toExpr = arena.appendExpr(.temporary(1), type: nullableIntType)

        let fn = KIRFunction(
            symbol: fnSym,
            name: interner.intern("copyNullableBox"),
            params: [],
            returnType: types.unitType,
            body: [
                .copy(from: fromExpr, to: toExpr),
                .returnUnit
            ],
            isSuspend: false,
            isInline: false
        )

        let fnID = arena.appendDecl(.function(fn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [fnID])], arena: arena)

        let sema = SemaModule(symbols: SymbolTable(), types: types, bindings: BindingTable(), diagnostics: DiagnosticEngine())
        _ = try runLowering(module: module, interner: interner, moduleName: "ABICopyNullableBox", sema: sema)

        let lowered = try findKIRFunction(named: "copyNullableBox", in: module, interner: interner)
        let callees = extractCallees(from: lowered.body, interner: interner)
        XCTAssertTrue(callees.contains("kk_box_int"), "Expected kk_box_int for copy Int -> Int?, got: \(callees)")
    }

    // MARK: - Property Lowering Tests

    /// Verify that a get call with a property symbol is rewritten to a direct
    /// accessor call using the synthetic getter symbol (-12_000 - propertySymbol).
    func testPropertyLoweringRewritesGetterCallToDirectAccessorSymbol() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()

        let propertySym = SymbolID(rawValue: 50)
        let callerSym = SymbolID(rawValue: 51)

        let receiver = arena.appendExpr(.temporary(0), type: types.anyType)
        let result = arena.appendExpr(.temporary(1), type: types.anyType)

        let callerFn = KIRFunction(
            symbol: callerSym,
            name: interner.intern("caller"),
            params: [],
            returnType: types.unitType,
            body: [
                .call(
                    symbol: propertySym,
                    callee: interner.intern("get"),
                    arguments: [receiver],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ),
                .returnUnit
            ],
            isSuspend: false,
            isInline: false
        )

        let fnID = arena.appendDecl(.function(callerFn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [fnID])], arena: arena)

        _ = try runLowering(module: module, interner: interner, moduleName: "PropGetter")

        guard case .function(let lowered)? = module.arena.decl(fnID) else {
            XCTFail("expected function")
            return
        }

        // The getter call should use the synthetic accessor symbol.
        let expectedGetterSymbol = SymbolID(rawValue: -12_000 - propertySym.rawValue)
        let callSymbols = lowered.body.compactMap { instruction -> SymbolID? in
            guard case .call(let sym, _, _, _, _, _, _) = instruction else { return nil }
            return sym
        }
        XCTAssertTrue(callSymbols.contains(expectedGetterSymbol),
                       "Expected synthetic getter symbol \(expectedGetterSymbol), got: \(callSymbols)")

        // kk_property_access must NOT appear.
        let callees = extractCallees(from: lowered.body, interner: interner)
        XCTAssertFalse(callees.contains("kk_property_access"))
    }

    /// Verify that a set call with a property symbol is rewritten to a direct
    /// accessor call using the synthetic setter symbol (-13_000 - propertySymbol).
    func testPropertyLoweringRewritesSetterCallToDirectAccessorSymbol() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()

        let propertySym = SymbolID(rawValue: 60)
        let callerSym = SymbolID(rawValue: 61)

        let receiver = arena.appendExpr(.temporary(0), type: types.anyType)
        let value = arena.appendExpr(.temporary(1), type: types.anyType)
        let result = arena.appendExpr(.temporary(2), type: types.unitType)

        let callerFn = KIRFunction(
            symbol: callerSym,
            name: interner.intern("setter_caller"),
            params: [],
            returnType: types.unitType,
            body: [
                .call(
                    symbol: propertySym,
                    callee: interner.intern("set"),
                    arguments: [receiver, value],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ),
                .returnUnit
            ],
            isSuspend: false,
            isInline: false
        )

        let fnID = arena.appendDecl(.function(callerFn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [fnID])], arena: arena)

        _ = try runLowering(module: module, interner: interner, moduleName: "PropSetter")

        guard case .function(let lowered)? = module.arena.decl(fnID) else {
            XCTFail("expected function")
            return
        }

        let expectedSetterSymbol = SymbolID(rawValue: -13_000 - propertySym.rawValue)
        let callSymbols = lowered.body.compactMap { instruction -> SymbolID? in
            guard case .call(let sym, _, _, _, _, _, _) = instruction else { return nil }
            return sym
        }
        XCTAssertTrue(callSymbols.contains(expectedSetterSymbol),
                       "Expected synthetic setter symbol \(expectedSetterSymbol), got: \(callSymbols)")

        let callees = extractCallees(from: lowered.body, interner: interner)
        XCTAssertFalse(callees.contains("kk_property_access"))
    }

    /// Verify that get/set calls without a property symbol are left unchanged.
    func testPropertyLoweringPreservesGetSetCallsWithoutSymbol() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()

        let callerSym = SymbolID(rawValue: 70)
        let receiver = arena.appendExpr(.temporary(0), type: types.anyType)
        let result = arena.appendExpr(.temporary(1), type: types.anyType)

        let callerFn = KIRFunction(
            symbol: callerSym,
            name: interner.intern("no_sym_caller"),
            params: [],
            returnType: types.unitType,
            body: [
                .call(
                    symbol: nil,
                    callee: interner.intern("get"),
                    arguments: [receiver],
                    result: result,
                    canThrow: false,
                    thrownResult: nil
                ),
                .returnUnit
            ],
            isSuspend: false,
            isInline: false
        )

        let fnID = arena.appendDecl(.function(callerFn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [fnID])], arena: arena)

        _ = try runLowering(module: module, interner: interner, moduleName: "PropNoSym")

        guard case .function(let lowered)? = module.arena.decl(fnID) else {
            XCTFail("expected function")
            return
        }

        // The call should remain unchanged (no symbol to derive accessor from).
        let callees = extractCallees(from: lowered.body, interner: interner)
        XCTAssertTrue(callees.contains("get"))
        XCTAssertFalse(callees.contains("kk_property_access"))
    }

    /// Verify that backing field copy is rewritten to a direct setter call.
    func testPropertyLoweringRewritesBackingFieldCopyToDirectSetterCall() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()
        let symbols = SymbolTable()

        // Create a property symbol and its backing field symbol.
        let propertySym = symbols.define(
            kind: .property,
            name: interner.intern("myProp"),
            fqName: [interner.intern("Foo"), interner.intern("myProp")],
            declSite: nil,
            visibility: .public,
            flags: []
        )
        let backingFieldSym = symbols.define(
            kind: .backingField,
            name: interner.intern("$backing_myProp"),
            fqName: [interner.intern("Foo"), interner.intern("$backing_myProp")],
            declSite: nil,
            visibility: .private,
            flags: []
        )
        symbols.setBackingFieldSymbol(backingFieldSym, for: propertySym)

        let callerSym = SymbolID(rawValue: 100)
        let fromExpr = arena.appendExpr(.intLiteral(42), type: types.anyType)
        let toExpr = arena.appendExpr(.symbolRef(backingFieldSym), type: types.anyType)

        let callerFn = KIRFunction(
            symbol: callerSym,
            name: interner.intern("bf_setter"),
            params: [],
            returnType: types.unitType,
            body: [
                .copy(from: fromExpr, to: toExpr),
                .returnUnit
            ],
            isSuspend: false,
            isInline: false
        )

        let fnID = arena.appendDecl(.function(callerFn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [fnID])], arena: arena)

        let sema = SemaModule(symbols: symbols, types: types, bindings: BindingTable(), diagnostics: DiagnosticEngine())
        _ = try runLowering(module: module, interner: interner, moduleName: "BFSetter", sema: sema)

        guard case .function(let lowered)? = module.arena.decl(fnID) else {
            XCTFail("expected function")
            return
        }

        // The copy should be rewritten to a set call with the synthetic setter
        // symbol derived from the property (not the backing field).
        let expectedSetterSymbol = SymbolID(rawValue: -13_000 - propertySym.rawValue)
        let callSymbols = lowered.body.compactMap { instruction -> SymbolID? in
            guard case .call(let sym, _, _, _, _, _, _) = instruction else { return nil }
            return sym
        }
        XCTAssertTrue(callSymbols.contains(expectedSetterSymbol),
                       "Expected setter symbol \(expectedSetterSymbol) for backing field copy, got: \(callSymbols)")

        let callees = extractCallees(from: lowered.body, interner: interner)
        XCTAssertTrue(callees.contains("set"))
        XCTAssertFalse(callees.contains("kk_property_access"))

        // Verify no copy instruction remains for the backing field.
        let hasCopy = lowered.body.contains { instruction in
            if case .copy = instruction { return true }
            return false
        }
        XCTAssertFalse(hasCopy, "Backing field copy should have been rewritten to a setter call")
    }

    /// Verify that a constValue(.symbolRef(propSym)) for a getter-only computed
    /// property (no backing field) is rewritten to a getter call by PropertyLoweringPass.
    func testPropertyLoweringRewritesComputedPropertySymbolRefToGetterCall() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()
        let symbols = SymbolTable()

        // Define a property symbol with NO backing field (getter-only computed).
        let propertySym = symbols.define(
            kind: .property,
            name: interner.intern("computed"),
            fqName: [interner.intern("Foo"), interner.intern("computed")],
            declSite: nil,
            visibility: .public,
            flags: []
        )
        // Deliberately do NOT set a backing field symbol for this property.

        // Emit a getter accessor function so PropertyLoweringPass recognises
        // this property as a computed property (it checks that the getter
        // function actually exists in the KIR module).
        let getterSymbol = SymbolID(rawValue: -12_000 - propertySym.rawValue)
        let getterRetExpr = arena.appendExpr(.stringLiteral(interner.intern("hello")), type: types.anyType)
        let getterFn = KIRFunction(
            symbol: getterSymbol,
            name: interner.intern("get"),
            params: [],
            returnType: types.anyType,
            body: [
                .constValue(result: getterRetExpr, value: .stringLiteral(interner.intern("hello"))),
                .returnValue(getterRetExpr)
            ],
            isSuspend: false,
            isInline: false
        )
        let _ = arena.appendDecl(.function(getterFn))

        let callerSym = SymbolID(rawValue: 200)
        let propRef = arena.appendExpr(.symbolRef(propertySym), type: types.anyType)

        let callerFn = KIRFunction(
            symbol: callerSym,
            name: interner.intern("caller"),
            params: [],
            returnType: types.unitType,
            body: [
                .constValue(result: propRef, value: .symbolRef(propertySym)),
                .returnUnit
            ],
            isSuspend: false,
            isInline: false
        )

        let fnID = arena.appendDecl(.function(callerFn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [fnID])], arena: arena)

        let sema = SemaModule(symbols: symbols, types: types, bindings: BindingTable(), diagnostics: DiagnosticEngine())
        _ = try runLowering(module: module, interner: interner, moduleName: "ComputedProp", sema: sema)

        guard case .function(let lowered)? = module.arena.decl(fnID) else {
            XCTFail("expected function")
            return
        }

        // The constValue(.symbolRef) should be rewritten to a getter call
        // using the synthetic getter symbol (-12_000 - propSym).
        let expectedGetterSymbol = SymbolID(rawValue: -12_000 - propertySym.rawValue)
        let callSymbols = lowered.body.compactMap { instruction -> SymbolID? in
            guard case .call(let sym, _, _, _, _, _, _) = instruction else { return nil }
            return sym
        }
        XCTAssertTrue(callSymbols.contains(expectedGetterSymbol),
                       "Expected getter call for computed property, got: \(callSymbols)")

        // No constValue(.symbolRef) should remain for the computed property.
        let hasSymbolRef = lowered.body.contains { instruction in
            if case .constValue(_, let value) = instruction,
               case .symbolRef(let sym) = value,
               sym == propertySym {
                return true
            }
            return false
        }
        XCTAssertFalse(hasSymbolRef,
                        "constValue(.symbolRef) for computed property should have been rewritten to a getter call")
    }

    /// Verify that a `var` property with a backing field is NOT rewritten
    /// (its constValue(.symbolRef) is preserved because it has storage).
    func testPropertyLoweringPreservesBackedPropertySymbolRef() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()
        let symbols = SymbolTable()

        // Define a property with a backing field (var with custom getter/setter).
        let propertySym = symbols.define(
            kind: .property,
            name: interner.intern("backed"),
            fqName: [interner.intern("Foo"), interner.intern("backed")],
            declSite: nil,
            visibility: .public,
            flags: [.mutable]
        )
        let backingFieldSym = symbols.define(
            kind: .backingField,
            name: interner.intern("$backing_backed"),
            fqName: [interner.intern("Foo"), interner.intern("$backing_backed")],
            declSite: nil,
            visibility: .private,
            flags: []
        )
        symbols.setBackingFieldSymbol(backingFieldSym, for: propertySym)

        let callerSym = SymbolID(rawValue: 300)
        let propRef = arena.appendExpr(.symbolRef(propertySym), type: types.anyType)

        let callerFn = KIRFunction(
            symbol: callerSym,
            name: interner.intern("caller"),
            params: [],
            returnType: types.unitType,
            body: [
                .constValue(result: propRef, value: .symbolRef(propertySym)),
                .returnUnit
            ],
            isSuspend: false,
            isInline: false
        )

        let fnID = arena.appendDecl(.function(callerFn))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [fnID])], arena: arena)

        let sema = SemaModule(symbols: symbols, types: types, bindings: BindingTable(), diagnostics: DiagnosticEngine())
        _ = try runLowering(module: module, interner: interner, moduleName: "BackedProp", sema: sema)

        guard case .function(let lowered)? = module.arena.decl(fnID) else {
            XCTFail("expected function")
            return
        }

        // The constValue(.symbolRef) for a backed property should be preserved.
        let hasSymbolRef = lowered.body.contains { instruction in
            if case .constValue(_, let value) = instruction,
               case .symbolRef(let sym) = value,
               sym == propertySym {
                return true
            }
            return false
        }
        XCTAssertTrue(hasSymbolRef,
                       "constValue(.symbolRef) for backed property should NOT be rewritten")
    }

    /// Integration test: compile `val computed: String get() = "hello"` through
    /// the full pipeline and verify no KIRGlobal is emitted for the computed property.
    func testGetterOnlyComputedPropertyEmitsNoGlobal() throws {
        let source = """
        package test

        class Widget {
            val computed: String get() = "hello"

            var backed: Int = 0
                get() = field
                set(value) { field = value }
        }
        """
        let ctx = try makeContextFromSource(source)
        try runToLowering(ctx)

        guard let module = ctx.kir else {
            XCTFail("KIR module not available")
            return
        }

        let interner = ctx.interner

        // Collect all global symbols.
        var globalSymbols: [SymbolID] = []
        for decl in module.arena.declarations {
            if case .global(let global) = decl {
                globalSymbols.append(global.symbol)
            }
        }

        // The "computed" property should NOT have a KIRGlobal.
        let computedName = interner.intern("computed")
        let computedSymbols = globalSymbols.filter { sym in
            ctx.sema?.symbols.symbol(sym)?.name == computedName
        }
        XCTAssertTrue(computedSymbols.isEmpty,
                       "Getter-only computed property should NOT have a KIRGlobal, found: \(computedSymbols)")

        // The "backed" property SHOULD have a KIRGlobal (it has storage).
        let backedName = interner.intern("backed")
        let backedSymbols = globalSymbols.filter { sym in
            ctx.sema?.symbols.symbol(sym)?.name == backedName
        }
        XCTAssertFalse(backedSymbols.isEmpty,
                        "Var property with backing field should have a KIRGlobal")

        let sema = try XCTUnwrap(ctx.sema, "Sema module not available")
        let computedPropertySymbol = try XCTUnwrap(
            sema.symbols.allSymbols().first(where: { symbol in
                symbol.kind == .property && symbol.name == computedName
            }),
            "computed property symbol not found in sema"
        )

        let expectedGetterSymbol = SymbolID(rawValue: -12_000 - computedPropertySymbol.id.rawValue)
        let getterSymbols = module.arena.declarations.compactMap { decl -> SymbolID? in
            guard case .function(let fn) = decl,
                  interner.resolve(fn.name) == "get" else {
                return nil
            }
            return fn.symbol
        }
        XCTAssertTrue(getterSymbols.contains(expectedGetterSymbol),
                       "Getter accessor symbol for computed property should be emitted. expected=\(expectedGetterSymbol), actual=\(getterSymbols)")
    }


    private func makeContext(
        interner: StringInterner,
        moduleName: String,
        emit: EmitMode = .kirDump,
        diagnostics: DiagnosticEngine = DiagnosticEngine()
    ) -> CompilationContext {
        let options = CompilerOptions(
            moduleName: moduleName,
            inputs: [],
            outputPath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path,
            emit: emit,
            target: defaultTargetTriple()
        )
        return CompilationContext(
            options: options,
            sourceManager: SourceManager(),
            diagnostics: diagnostics,
            interner: interner
        )
    }

    @discardableResult
    private func runLowering(
        module: KIRModule,
        interner: StringInterner,
        moduleName: String,
        emit: EmitMode = .kirDump,
        sema: SemaModule? = nil,
        diagnostics: DiagnosticEngine = DiagnosticEngine()
    ) throws -> CompilationContext {
        let ctx = makeContext(interner: interner, moduleName: moduleName, emit: emit, diagnostics: diagnostics)
        ctx.kir = module
        ctx.sema = sema
        try LoweringPhase().run(ctx)
        return ctx
    }
}
