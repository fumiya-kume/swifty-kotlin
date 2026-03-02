@testable import CompilerCore
import Foundation
import XCTest

extension LoweringPassRegressionTests {
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
        let ctx = CompilationContext(
            options: CompilerOptions(moduleName: "ABIBoxReturn", inputs: [], outputPath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path, emit: .kirDump, target: defaultTargetTriple()),
            sourceManager: SourceManager(),
            diagnostics: DiagnosticEngine(),
            interner: interner
        )
        ctx.kir = module
        ctx.sema = sema

        try LoweringPhase().run(ctx)

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
        let ctx = CompilationContext(
            options: CompilerOptions(moduleName: "ABICopyBox", inputs: [], outputPath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path, emit: .kirDump, target: defaultTargetTriple()),
            sourceManager: SourceManager(),
            diagnostics: DiagnosticEngine(),
            interner: interner
        )
        ctx.kir = module
        ctx.sema = sema

        try LoweringPhase().run(ctx)

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
        let ctx = CompilationContext(
            options: CompilerOptions(moduleName: "ABICopyUnbox", inputs: [], outputPath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path, emit: .kirDump, target: defaultTargetTriple()),
            sourceManager: SourceManager(),
            diagnostics: DiagnosticEngine(),
            interner: interner
        )
        ctx.kir = module
        ctx.sema = sema

        try LoweringPhase().run(ctx)

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
            (.primitive(.char, .nonNull), .charLiteral(65), "kk_box_char")
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
            let ctx = CompilationContext(
                options: CompilerOptions(moduleName: "ABIBoxAll_\(index)", inputs: [], outputPath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path, emit: .kirDump, target: defaultTargetTriple()),
                sourceManager: SourceManager(),
                diagnostics: DiagnosticEngine(),
                interner: interner
            )
            ctx.kir = module
            ctx.sema = sema

            try LoweringPhase().run(ctx)

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
        let ctx = CompilationContext(
            options: CompilerOptions(moduleName: "ABICopyNullableBox", inputs: [], outputPath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path, emit: .kirDump, target: defaultTargetTriple()),
            sourceManager: SourceManager(),
            diagnostics: DiagnosticEngine(),
            interner: interner
        )
        ctx.kir = module
        ctx.sema = sema

        try LoweringPhase().run(ctx)

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

        let ctx = CompilationContext(
            options: CompilerOptions(moduleName: "PropGetter", inputs: [], outputPath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path, emit: .kirDump, target: defaultTargetTriple()),
            sourceManager: SourceManager(),
            diagnostics: DiagnosticEngine(),
            interner: interner
        )
        ctx.kir = module
        try LoweringPhase().run(ctx)

        guard case let .function(lowered)? = module.arena.decl(fnID) else {
            XCTFail("expected function")
            return
        }

        // The getter call should use the synthetic accessor symbol.
        let expectedGetterSymbol = SymbolID(rawValue: -12000 - propertySym.rawValue)
        let callSymbols = lowered.body.compactMap { instruction -> SymbolID? in
            guard case let .call(sym, _, _, _, _, _, _) = instruction else { return nil }
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

        let ctx = CompilationContext(
            options: CompilerOptions(moduleName: "PropSetter", inputs: [], outputPath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path, emit: .kirDump, target: defaultTargetTriple()),
            sourceManager: SourceManager(),
            diagnostics: DiagnosticEngine(),
            interner: interner
        )
        ctx.kir = module
        try LoweringPhase().run(ctx)

        guard case let .function(lowered)? = module.arena.decl(fnID) else {
            XCTFail("expected function")
            return
        }

        let expectedSetterSymbol = SymbolID(rawValue: -13000 - propertySym.rawValue)
        let callSymbols = lowered.body.compactMap { instruction -> SymbolID? in
            guard case let .call(sym, _, _, _, _, _, _) = instruction else { return nil }
            return sym
        }
        XCTAssertTrue(callSymbols.contains(expectedSetterSymbol),
                      "Expected synthetic setter symbol \(expectedSetterSymbol), got: \(callSymbols)")

        let callees = extractCallees(from: lowered.body, interner: interner)
        XCTAssertFalse(callees.contains("kk_property_access"))
    }

    // Verify that get/set calls without a property symbol are left unchanged.
}
