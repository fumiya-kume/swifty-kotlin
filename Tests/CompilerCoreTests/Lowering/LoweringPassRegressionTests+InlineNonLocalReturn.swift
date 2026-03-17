@testable import CompilerCore
import Foundation
import XCTest

extension LoweringPassRegressionTests {

    // MARK: - Non-local return: basic conversion

    /// When an inline function body contains a `nonLocalReturn`, the inline
    /// lowering pass should convert it into a real `returnValue` / `returnUnit`
    /// in the caller's body.
    func testInlineLoweringConvertsNonLocalReturnValueToCallerReturn() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()

        let callerSym = SymbolID(rawValue: 400)
        let inlineSym = SymbolID(rawValue: 401)
        let inlineParamSym = SymbolID(rawValue: 402)

        // Inline function body: load the parameter, then non-local return it.
        let inlineArgExpr = arena.appendExpr(.temporary(0))
        let callerArg = arena.appendExpr(.temporary(1))
        let callerResult = arena.appendExpr(.temporary(2))

        let inlineFn = KIRFunction(
            symbol: inlineSym,
            name: interner.intern("runAndReturn"),
            params: [KIRParameter(symbol: inlineParamSym, type: types.make(.primitive(.int, .nonNull)))],
            returnType: types.make(.primitive(.int, .nonNull)),
            body: [
                .constValue(result: inlineArgExpr, value: .symbolRef(inlineParamSym)),
                // This non-local return should become a real return in the caller.
                .nonLocalReturn(inlineArgExpr),
            ],
            isSuspend: false,
            isInline: true
        )

        let callerFn = KIRFunction(
            symbol: callerSym,
            name: interner.intern("main"),
            params: [],
            returnType: types.make(.primitive(.int, .nonNull)),
            body: [
                .constValue(result: callerArg, value: .intLiteral(99)),
                .call(
                    symbol: inlineSym,
                    callee: interner.intern("runAndReturn"),
                    arguments: [callerArg],
                    result: callerResult,
                    canThrow: false,
                    thrownResult: nil
                ),
                // This returnValue should still be present after inlining.
                .returnValue(callerResult),
            ],
            isSuspend: false,
            isInline: false
        )

        let callerID = arena.appendDecl(.function(callerFn))
        _ = arena.appendDecl(.function(inlineFn))
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [callerID])],
            arena: arena
        )

        let ctx = CompilationContext(
            options: CompilerOptions(
                moduleName: "InlineNonLocalReturn",
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
        try LoweringPhase().run(ctx)

        guard case let .function(loweredCaller)? = module.arena.decl(callerID) else {
            XCTFail("expected lowered caller function")
            return
        }

        // The non-local return should have been converted to a real returnValue.
        let returnValues = loweredCaller.body.compactMap { instruction -> KIRExprID? in
            guard case let .returnValue(expr) = instruction else { return nil }
            return expr
        }
        XCTAssertGreaterThanOrEqual(returnValues.count, 1, "Expected at least one returnValue from non-local return conversion")

        // The inlined call should be removed (no call to 'runAndReturn').
        let calleeNames = extractCallees(from: loweredCaller.body, interner: interner)
        XCTAssertFalse(calleeNames.contains("runAndReturn"), "Inline call should be expanded")

        // No residual nonLocalReturn instructions should remain.
        let hasNonLocalReturn = loweredCaller.body.contains { instruction in
            if case .nonLocalReturn = instruction { return true }
            return false
        }
        XCTAssertFalse(hasNonLocalReturn, "nonLocalReturn should have been converted to returnValue")
    }

    // MARK: - Non-local return Unit

    /// A non-local return with nil value (Unit return) should become returnUnit
    /// in the caller.
    func testInlineLoweringConvertsNonLocalReturnUnitToCallerReturnUnit() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()

        let callerSym = SymbolID(rawValue: 500)
        let inlineSym = SymbolID(rawValue: 501)

        let callerResult = arena.appendExpr(.temporary(0))

        let inlineFn = KIRFunction(
            symbol: inlineSym,
            name: interner.intern("earlyExit"),
            params: [],
            returnType: types.unitType,
            body: [
                .nonLocalReturn(nil),
            ],
            isSuspend: false,
            isInline: true
        )

        let callerFn = KIRFunction(
            symbol: callerSym,
            name: interner.intern("main"),
            params: [],
            returnType: types.unitType,
            body: [
                .call(
                    symbol: inlineSym,
                    callee: interner.intern("earlyExit"),
                    arguments: [],
                    result: callerResult,
                    canThrow: false,
                    thrownResult: nil
                ),
                .returnUnit,
            ],
            isSuspend: false,
            isInline: false
        )

        let callerID = arena.appendDecl(.function(callerFn))
        _ = arena.appendDecl(.function(inlineFn))
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [callerID])],
            arena: arena
        )

        let ctx = CompilationContext(
            options: CompilerOptions(
                moduleName: "InlineNonLocalReturnUnit",
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
        try LoweringPhase().run(ctx)

        guard case let .function(loweredCaller)? = module.arena.decl(callerID) else {
            XCTFail("expected lowered caller function")
            return
        }

        // Should have returnUnit from the non-local return conversion.
        let hasReturnUnit = loweredCaller.body.contains { instruction in
            if case .returnUnit = instruction { return true }
            return false
        }
        XCTAssertTrue(hasReturnUnit, "Non-local return nil should become returnUnit")

        // No residual nonLocalReturn.
        let hasNonLocalReturn = loweredCaller.body.contains { instruction in
            if case .nonLocalReturn = instruction { return true }
            return false
        }
        XCTAssertFalse(hasNonLocalReturn, "nonLocalReturn should have been lowered away")
    }

    // MARK: - Non-local return with mixed body (normal path + non-local path)

    /// When an inline function contains both a normal code path and a
    /// non-local return path, both should be present in the lowered output.
    func testInlineLoweringPreservesMixedNormalAndNonLocalReturnPaths() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()

        let callerSym = SymbolID(rawValue: 600)
        let inlineSym = SymbolID(rawValue: 601)
        let inlineParamSym = SymbolID(rawValue: 602)

        let inlineArgExpr = arena.appendExpr(.temporary(0))
        let falseExpr = arena.appendExpr(.boolLiteral(false))
        let callerArg = arena.appendExpr(.temporary(2))
        let callerResult = arena.appendExpr(.temporary(3))
        let oneExpr = arena.appendExpr(.intLiteral(1))

        // Inline function: if param == false, non-local return param; else normal return 1
        let inlineFn = KIRFunction(
            symbol: inlineSym,
            name: interner.intern("conditionalReturn"),
            params: [KIRParameter(symbol: inlineParamSym, type: types.make(.primitive(.int, .nonNull)))],
            returnType: types.make(.primitive(.int, .nonNull)),
            body: [
                .constValue(result: inlineArgExpr, value: .symbolRef(inlineParamSym)),
                .constValue(result: falseExpr, value: .boolLiteral(false)),
                .jumpIfEqual(lhs: inlineArgExpr, rhs: falseExpr, target: 10),
                // Non-local return path
                .nonLocalReturn(inlineArgExpr),
                .label(10),
                // Normal return path
                .constValue(result: oneExpr, value: .intLiteral(1)),
                .returnValue(oneExpr),
            ],
            isSuspend: false,
            isInline: true
        )

        let callerFn = KIRFunction(
            symbol: callerSym,
            name: interner.intern("main"),
            params: [],
            returnType: types.make(.primitive(.int, .nonNull)),
            body: [
                .constValue(result: callerArg, value: .intLiteral(42)),
                .call(
                    symbol: inlineSym,
                    callee: interner.intern("conditionalReturn"),
                    arguments: [callerArg],
                    result: callerResult,
                    canThrow: false,
                    thrownResult: nil
                ),
                .returnValue(callerResult),
            ],
            isSuspend: false,
            isInline: false
        )

        let callerID = arena.appendDecl(.function(callerFn))
        _ = arena.appendDecl(.function(inlineFn))
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [callerID])],
            arena: arena
        )

        let ctx = CompilationContext(
            options: CompilerOptions(
                moduleName: "InlineMixedReturn",
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
        try LoweringPhase().run(ctx)

        guard case let .function(loweredCaller)? = module.arena.decl(callerID) else {
            XCTFail("expected lowered caller function")
            return
        }

        // Should have returnValue instructions from both the non-local
        // return path and the caller's own return.
        let returnValues = loweredCaller.body.compactMap { instruction -> KIRExprID? in
            guard case let .returnValue(expr) = instruction else { return nil }
            return expr
        }
        XCTAssertGreaterThanOrEqual(
            returnValues.count, 2,
            "Expected returns from both non-local path and caller's own return"
        )

        // An exit label should be emitted (nonLocalReturnLabelBase range).
        let labels = loweredCaller.body.compactMap { instruction -> Int32? in
            guard case let .label(id) = instruction else { return nil }
            return id
        }
        let hasExitLabel = labels.contains { $0 >= nonLocalReturnLabelBase }
        XCTAssertTrue(hasExitLabel, "Expected a non-local return exit label")

        // No residual nonLocalReturn.
        let hasNonLocalReturn = loweredCaller.body.contains { instruction in
            if case .nonLocalReturn = instruction { return true }
            return false
        }
        XCTAssertFalse(hasNonLocalReturn, "nonLocalReturn should have been lowered away")

        // The inlined call should be removed.
        let calleeNames = extractCallees(from: loweredCaller.body, interner: interner)
        XCTAssertFalse(calleeNames.contains("conditionalReturn"))
    }

    // MARK: - Existing inline tests still pass (no regression)

    /// Inline expansion without nonLocalReturn should work exactly as before.
    func testInlineLoweringWithoutNonLocalReturnIsUnchanged() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()

        let callerSym = SymbolID(rawValue: 700)
        let inlineSym = SymbolID(rawValue: 701)
        let inlineParamSym = SymbolID(rawValue: 702)

        let inlineArg = arena.appendExpr(.temporary(0))
        let inlineOne = arena.appendExpr(.temporary(1))
        let inlineSum = arena.appendExpr(.temporary(2))
        let callerArg = arena.appendExpr(.temporary(3))
        let callerResult = arena.appendExpr(.temporary(4))

        let inlineFn = KIRFunction(
            symbol: inlineSym,
            name: interner.intern("addOne"),
            params: [KIRParameter(symbol: inlineParamSym, type: types.make(.primitive(.int, .nonNull)))],
            returnType: types.make(.primitive(.int, .nonNull)),
            body: [
                .constValue(result: inlineArg, value: .symbolRef(inlineParamSym)),
                .constValue(result: inlineOne, value: .intLiteral(1)),
                .call(symbol: nil, callee: interner.intern("kk_op_add"), arguments: [inlineArg, inlineOne], result: inlineSum, canThrow: false, thrownResult: nil),
                .returnValue(inlineSum),
            ],
            isSuspend: false,
            isInline: true
        )
        let callerFn = KIRFunction(
            symbol: callerSym,
            name: interner.intern("main"),
            params: [],
            returnType: types.make(.primitive(.int, .nonNull)),
            body: [
                .constValue(result: callerArg, value: .intLiteral(10)),
                .call(symbol: inlineSym, callee: interner.intern("addOne"), arguments: [callerArg], result: callerResult, canThrow: false, thrownResult: nil),
                .returnValue(callerResult),
            ],
            isSuspend: false,
            isInline: false
        )

        let callerID = arena.appendDecl(.function(callerFn))
        _ = arena.appendDecl(.function(inlineFn))
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [callerID])],
            arena: arena
        )

        let ctx = CompilationContext(
            options: CompilerOptions(
                moduleName: "InlineNoNonLocal",
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
        try LoweringPhase().run(ctx)

        guard case let .function(loweredCaller)? = module.arena.decl(callerID) else {
            XCTFail("expected lowered caller function")
            return
        }

        // Inline call should be expanded -- no call to addOne remains.
        let calleeNames = extractCallees(from: loweredCaller.body, interner: interner)
        XCTAssertFalse(calleeNames.contains("addOne"))
        XCTAssertTrue(calleeNames.contains("kk_op_add"))

        // No nonLocalReturn instructions.
        let hasNonLocalReturn = loweredCaller.body.contains { instruction in
            if case .nonLocalReturn = instruction { return true }
            return false
        }
        XCTAssertFalse(hasNonLocalReturn)

        // No exit labels from non-local return handling (labels >= nonLocalReturnLabelBase).
        let labels = loweredCaller.body.compactMap { instruction -> Int32? in
            guard case let .label(id) = instruction else { return nil }
            return id
        }
        let hasExitLabel = labels.contains { $0 >= nonLocalReturnLabelBase }
        XCTAssertFalse(hasExitLabel, "No non-local return labels expected for normal inline expansion")
    }
}
