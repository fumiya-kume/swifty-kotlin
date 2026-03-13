@testable import CompilerCore
import Foundation
import XCTest

extension LoweringABIAndPropertyRegressionTests {
    // MARK: - Delegate Lowering Precondition Violation Tests

    /// Verify that a `lazy(...)` call WITHOUT a subsequent `copy to $delegate_`
    /// field does not crash and is left unchanged by the delegate lowering pass.
    func testLazyCallWithoutDelegateFieldDoesNotCrash() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()
        let symbols = SymbolTable()

        let fnSym = SymbolID(rawValue: 5000)
        let lazyName = interner.intern("lazy")
        let lambdaExpr = arena.appendExpr(.temporary(0), type: nil)
        let resultExpr = arena.appendExpr(.temporary(1), type: nil)

        let function = KIRFunction(
            symbol: fnSym,
            name: interner.intern("main"),
            params: [],
            returnType: types.unitType,
            body: [
                // Call lazy() but no subsequent copy to $delegate_ field.
                .call(
                    symbol: nil,
                    callee: lazyName,
                    arguments: [lambdaExpr],
                    result: resultExpr,
                    canThrow: false,
                    thrownResult: nil
                ),
                .returnUnit,
            ],
            isSuspend: false,
            isInline: false
        )

        let fnID = arena.appendDecl(.function(function))
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [fnID])],
            arena: arena
        )

        let sema = SemaModule(
            symbols: symbols,
            types: types,
            bindings: BindingTable(),
            diagnostics: DiagnosticEngine()
        )

        // Must not crash.
        XCTAssertNoThrow(try runLowering(
            module: module,
            interner: interner,
            moduleName: "DelegateNoCrash",
            sema: sema
        ))

        // The lazy call should remain unchanged (not rewritten to kk_lazy_create)
        // because there is no $delegate_ field copy.
        let lowered = try findKIRFunction(named: "main", in: module, interner: interner)
        let callees = extractCallees(from: lowered.body, interner: interner)
        XCTAssertTrue(
            callees.contains("lazy"),
            "Without delegate field, lazy call should remain unchanged, got: \(callees)"
        )
        XCTAssertFalse(
            callees.contains("kk_lazy_create"),
            "Should not rewrite to kk_lazy_create without delegate field"
        )
    }

    /// Verify that an observable-like call with a copy to $delegate_ but with
    /// zero arguments (missing initial value and callback) does not crash.
    func testObservableDelegateWithMissingArgsPassesThrough() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()
        let symbols = SymbolTable()

        let fnSym = SymbolID(rawValue: 5100)
        let observableName = interner.intern("observable")
        let resultExpr = arena.appendExpr(.temporary(0), type: nil)

        // Create a $delegate_ field symbol so the delegate scanner finds it.
        let delegateFieldSym = symbols.define(
            kind: .field,
            name: interner.intern("$delegate_prop"),
            fqName: [interner.intern("$delegate_prop")],
            declSite: nil,
            visibility: .private
        )
        let delegateFieldRef = arena.appendExpr(.symbolRef(delegateFieldSym), type: nil)

        let function = KIRFunction(
            symbol: fnSym,
            name: interner.intern("main"),
            params: [],
            returnType: types.unitType,
            body: [
                // Call observable with zero args — precondition violation.
                .call(
                    symbol: nil,
                    callee: observableName,
                    arguments: [],
                    result: resultExpr,
                    canThrow: false,
                    thrownResult: nil
                ),
                .copy(from: resultExpr, to: delegateFieldRef),
                .returnUnit,
            ],
            isSuspend: false,
            isInline: false
        )

        let fnID = arena.appendDecl(.function(function))
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [fnID])],
            arena: arena
        )
        let sema = SemaModule(
            symbols: symbols,
            types: types,
            bindings: BindingTable(),
            diagnostics: DiagnosticEngine()
        )

        // Must not crash even with zero args.
        XCTAssertNoThrow(try runLowering(
            module: module,
            interner: interner,
            moduleName: "DelegateObservableBadArgs",
            sema: sema
        ))
    }

    /// Verify that an unknown delegate callee name (not lazy/observable/vetoable)
    /// with a $delegate_ copy preserves the original instructions unchanged.
    func testUnknownDelegateKindPreservesOriginalInstructions() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()
        let symbols = SymbolTable()

        let fnSym = SymbolID(rawValue: 5200)
        let unknownName = interner.intern("unknownDelegateFactory")
        let argExpr = arena.appendExpr(.intLiteral(42), type: types.intType)
        let resultExpr = arena.appendExpr(.temporary(0), type: nil)

        let delegateFieldSym = symbols.define(
            kind: .field,
            name: interner.intern("$delegate_myProp"),
            fqName: [interner.intern("$delegate_myProp")],
            declSite: nil,
            visibility: .private
        )
        let delegateFieldRef = arena.appendExpr(.symbolRef(delegateFieldSym), type: nil)

        let function = KIRFunction(
            symbol: fnSym,
            name: interner.intern("main"),
            params: [],
            returnType: types.unitType,
            body: [
                .call(
                    symbol: nil,
                    callee: unknownName,
                    arguments: [argExpr],
                    result: resultExpr,
                    canThrow: false,
                    thrownResult: nil
                ),
                .copy(from: resultExpr, to: delegateFieldRef),
                .returnUnit,
            ],
            isSuspend: false,
            isInline: false
        )

        let fnID = arena.appendDecl(.function(function))
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [fnID])],
            arena: arena
        )
        let sema = SemaModule(
            symbols: symbols,
            types: types,
            bindings: BindingTable(),
            diagnostics: DiagnosticEngine()
        )

        try runLowering(
            module: module,
            interner: interner,
            moduleName: "DelegateUnknown",
            sema: sema
        )

        let lowered = try findKIRFunction(named: "main", in: module, interner: interner)
        let callees = extractCallees(from: lowered.body, interner: interner)
        // Unknown callee must be preserved as-is.
        XCTAssertTrue(
            callees.contains("unknownDelegateFactory"),
            "Unknown delegate factory call should remain unchanged, got: \(callees)"
        )
        // Must NOT rewrite to any kk_*_create runtime call.
        XCTAssertFalse(callees.contains("kk_lazy_create"))
        XCTAssertFalse(callees.contains("kk_observable_create"))
        XCTAssertFalse(callees.contains("kk_vetoable_create"))
    }

    /// Verify that ABI boxing is correctly applied when delegate getter return
    /// type differs from the property declaration type.
    func testDelegateGetterReturnTypeMismatchInsertsBoxing() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()
        let symbols = SymbolTable()

        let intType = types.make(.primitive(.int, .nonNull))
        let anyNullableType = types.make(.any(.nullable))

        // Create a function that calls a delegate getter returning Int,
        // but assigns the result to a variable typed as Any?.
        let getterSym = SymbolID(rawValue: 5300)
        let getterName = interner.intern("getDelegateValue")
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [],
                returnType: intType,
                valueParameterSymbols: []
            ),
            for: getterSym
        )

        let callerSym = SymbolID(rawValue: 5301)
        let resultExpr = arena.appendExpr(.temporary(0), type: intType)
        let anyResultExpr = arena.appendExpr(.temporary(1), type: anyNullableType)

        let callerFn = KIRFunction(
            symbol: callerSym,
            name: interner.intern("main"),
            params: [],
            returnType: types.unitType,
            body: [
                .call(
                    symbol: getterSym,
                    callee: getterName,
                    arguments: [],
                    result: resultExpr,
                    canThrow: false,
                    thrownResult: nil
                ),
                .copy(from: resultExpr, to: anyResultExpr),
                .returnUnit,
            ],
            isSuspend: false,
            isInline: false
        )

        let getterFn = KIRFunction(
            symbol: getterSym,
            name: getterName,
            params: [],
            returnType: intType,
            body: [
                .returnValue(arena.appendExpr(.intLiteral(42), type: intType)),
            ],
            isSuspend: false,
            isInline: false
        )

        let callerID = arena.appendDecl(.function(callerFn))
        _ = arena.appendDecl(.function(getterFn))
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [callerID])],
            arena: arena
        )

        let sema = SemaModule(
            symbols: symbols,
            types: types,
            bindings: BindingTable(),
            diagnostics: DiagnosticEngine()
        )

        try runLowering(
            module: module,
            interner: interner,
            moduleName: "DelegateABIMismatch",
            sema: sema
        )

        let lowered = try findKIRFunction(named: "main", in: module, interner: interner)
        let callees = extractCallees(from: lowered.body, interner: interner)
        // When Int is stored into Any?, ABI lowering should insert kk_box_int.
        XCTAssertTrue(
            callees.contains("kk_box_int"),
            "Expected kk_box_int for Int -> Any? boxing in delegate getter, got: \(callees)"
        )
    }
}
