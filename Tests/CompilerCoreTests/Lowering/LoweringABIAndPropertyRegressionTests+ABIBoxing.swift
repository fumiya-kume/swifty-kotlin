@testable import CompilerCore
import Foundation
import XCTest

extension LoweringABIAndPropertyRegressionTests {
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
            options: CompilerOptions(
                moduleName: "ABIBoxInt",
                inputs: [],
                outputPath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path,
                emit: .kirDump,
                target: defaultTargetTriple()
            ),
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
            options: CompilerOptions(
                moduleName: "ABIBoxBool",
                inputs: [],
                outputPath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path,
                emit: .kirDump,
                target: defaultTargetTriple()
            ),
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
            options: CompilerOptions(
                moduleName: "ABIBoxNullableInt",
                inputs: [],
                outputPath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path,
                emit: .kirDump,
                target: defaultTargetTriple()
            ),
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
            // .returnUnit is intentional – this is a stub for testing caller-side
            // ABI instrumentation (box/unbox insertion); callee body is not under test.
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
            // .returnUnit is intentional – this is a stub for testing caller-side
            // ABI instrumentation (box/unbox insertion); callee body is not under test.
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

        let function = KIRFunction(
            symbol: fnSym,
            name: interner.intern("returnBoxed"),
            params: [],
            returnType: anyNullableType,
            body: [
                .returnValue(valueExpr),
            ],
            isSuspend: false,
            isInline: false
        )

        let fnID = arena.appendDecl(.function(function))
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

        let function = KIRFunction(
            symbol: fnSym,
            name: interner.intern("copyBoxed"),
            params: [],
            returnType: types.unitType,
            body: [
                .copy(from: fromExpr, to: toExpr),
                .returnUnit,
            ],
            isSuspend: false,
            isInline: false
        )

        let fnID = arena.appendDecl(.function(function))
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

        let function = KIRFunction(
            symbol: fnSym,
            name: interner.intern("copyUnboxed"),
            params: [],
            returnType: types.unitType,
            body: [
                .copy(from: fromExpr, to: toExpr),
                .returnUnit,
            ],
            isSuspend: false,
            isInline: false
        )

        let fnID = arena.appendDecl(.function(function))
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

        let function = KIRFunction(
            symbol: fnSym,
            name: interner.intern("copyNullableBox"),
            params: [],
            returnType: types.unitType,
            body: [
                .copy(from: fromExpr, to: toExpr),
                .returnUnit,
            ],
            isSuspend: false,
            isInline: false
        )

        let fnID = arena.appendDecl(.function(function))
        let module = KIRModule(files: [KIRFile(fileID: FileID(rawValue: 0), decls: [fnID])], arena: arena)

        let sema = SemaModule(symbols: SymbolTable(), types: types, bindings: BindingTable(), diagnostics: DiagnosticEngine())
        _ = try runLowering(module: module, interner: interner, moduleName: "ABICopyNullableBox", sema: sema)

        let lowered = try findKIRFunction(named: "copyNullableBox", in: module, interner: interner)
        let callees = extractCallees(from: lowered.body, interner: interner)
        XCTAssertTrue(callees.contains("kk_box_int"), "Expected kk_box_int for copy Int -> Int?, got: \(callees)")
    }
}
