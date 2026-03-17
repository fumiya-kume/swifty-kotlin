@testable import CompilerCore
import Foundation
import XCTest

extension LoweringPassRegressionTests {

    // MARK: - CLSR-001: LambdaClosureConversionPass tests

    /// Verifies that `<lambda>` marker calls are still rewritten to
    /// `kk_lambda_invoke` for backward compatibility.
    func testClosureConversionRewritesLambdaMarkerToKkLambdaInvoke() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()

        let mainSym = SymbolID(rawValue: 1)
        let v0 = arena.appendExpr(.temporary(0))
        let v1 = arena.appendExpr(.temporary(1))

        let mainFn = KIRFunction(
            symbol: mainSym,
            name: interner.intern("main"),
            params: [],
            returnType: types.unitType,
            body: [
                .call(
                    symbol: nil,
                    callee: interner.intern("<lambda>"),
                    arguments: [v0],
                    result: v1,
                    canThrow: false,
                    thrownResult: nil
                ),
                .returnUnit,
            ],
            isSuspend: false,
            isInline: false
        )

        let mainID = arena.appendDecl(.function(mainFn))
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [mainID])],
            arena: arena
        )

        let pass = LambdaClosureConversionPass()
        let ctx = KIRContext(
            diagnostics: DiagnosticEngine(),
            options: CompilerOptions(
                moduleName: "ClosureTest",
                inputs: [],
                outputPath: FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString).path,
                emit: .kirDump,
                target: defaultTargetTriple()
            ),
            interner: interner
        )

        XCTAssertTrue(pass.shouldRun(module: module, ctx: ctx))
        try pass.run(module: module, ctx: ctx)

        guard case let .function(loweredMain)? = module.arena.decl(mainID) else {
            XCTFail("Expected lowered main function.")
            return
        }

        let callees = extractCallees(from: loweredMain.body, interner: interner)
        XCTAssertTrue(callees.contains("kk_lambda_invoke"),
            "Expected <lambda> to be rewritten to kk_lambda_invoke")
        XCTAssertFalse(callees.contains("<lambda>"),
            "Expected <lambda> marker to be removed")
    }

    /// Verifies that a lambda with capture parameters gets rewritten to use
    /// a closure object: kk_object_new + kk_array_set for captures, then
    /// kk_closure_invoke_* for the invocation.
    func testClosureConversionSynthesizesClosureObjectForLambdaWithCaptures() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()
        let intType = types.make(.primitive(.int, .nonNull))

        let mainSym = SymbolID(rawValue: 1)
        let lambdaSym = SymbolID(rawValue: 2)
        let lambdaName = interner.intern("kk_lambda_42")

        // Capture param: uses the negative range that LambdaLowerer assigns.
        let captureParamSym = SymbolID(rawValue: -2_000_042)
        // Value param: also negative but in the -1_000_000 range.
        let valueParamSym = SymbolID(rawValue: -1_000_042)

        let captureExpr = arena.appendExpr(.symbolRef(captureParamSym), type: intType)
        let valueExpr = arena.appendExpr(.symbolRef(valueParamSym), type: intType)
        let bodyResult = arena.appendExpr(.temporary(10), type: intType)

        // Lambda function: captures one value, takes one value param.
        let lambdaFn = KIRFunction(
            symbol: lambdaSym,
            name: lambdaName,
            params: [
                KIRParameter(symbol: captureParamSym, type: intType), // capture
                KIRParameter(symbol: valueParamSym, type: intType),   // value param
            ],
            returnType: intType,
            body: [
                .beginBlock,
                .constValue(result: captureExpr, value: .symbolRef(captureParamSym)),
                .constValue(result: valueExpr, value: .symbolRef(valueParamSym)),
                .binary(op: .add, lhs: captureExpr, rhs: valueExpr, result: bodyResult),
                .returnValue(bodyResult),
                .endBlock,
            ],
            isSuspend: false,
            isInline: false
        )

        // Main function: calls the lambda with capture arg + value arg.
        let capturedValue = arena.appendExpr(.intLiteral(100), type: intType)
        let callArg = arena.appendExpr(.intLiteral(7), type: intType)
        let callResult = arena.appendExpr(.temporary(20), type: intType)

        let mainFn = KIRFunction(
            symbol: mainSym,
            name: interner.intern("main"),
            params: [],
            returnType: intType,
            body: [
                .constValue(result: capturedValue, value: .intLiteral(100)),
                .constValue(result: callArg, value: .intLiteral(7)),
                .call(
                    symbol: lambdaSym,
                    callee: lambdaName,
                    arguments: [capturedValue, callArg], // capture + value
                    result: callResult,
                    canThrow: false,
                    thrownResult: nil
                ),
                .returnValue(callResult),
            ],
            isSuspend: false,
            isInline: false
        )

        let mainID = arena.appendDecl(.function(mainFn))
        _ = arena.appendDecl(.function(lambdaFn))
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [mainID])],
            arena: arena
        )

        let pass = LambdaClosureConversionPass()
        let ctx = KIRContext(
            diagnostics: DiagnosticEngine(),
            options: CompilerOptions(
                moduleName: "ClosureObjTest",
                inputs: [],
                outputPath: FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString).path,
                emit: .kirDump,
                target: defaultTargetTriple()
            ),
            interner: interner
        )

        XCTAssertTrue(pass.shouldRun(module: module, ctx: ctx))
        try pass.run(module: module, ctx: ctx)

        guard case let .function(loweredMain)? = module.arena.decl(mainID) else {
            XCTFail("Expected lowered main function.")
            return
        }

        let callees = extractCallees(from: loweredMain.body, interner: interner)

        // Verify closure object allocation.
        XCTAssertTrue(callees.contains("kk_object_new"),
            "Expected closure object allocation via kk_object_new")

        // Verify capture storage.
        XCTAssertTrue(callees.contains("kk_array_set"),
            "Expected capture storage via kk_array_set")

        // Verify the invoke wrapper is called instead of the raw lambda.
        let invokeWrapperName = "kk_closure_invoke_\(lambdaSym.rawValue)"
        XCTAssertTrue(callees.contains(invokeWrapperName),
            "Expected invoke wrapper \(invokeWrapperName) to be called")

        // The original lambda name should no longer appear as a direct call in main.
        XCTAssertFalse(callees.contains("kk_lambda_42"),
            "Expected direct lambda call to be replaced by closure invoke")

        // Verify synthesized declarations were added.
        let allFunctionNames = module.arena.declarations.compactMap { decl -> String? in
            guard case let .function(function) = decl else { return nil }
            return interner.resolve(function.name)
        }
        XCTAssertTrue(allFunctionNames.contains(invokeWrapperName),
            "Expected invoke wrapper function to be synthesized")

        let hasNominalType = module.arena.declarations.contains { decl in
            guard case .nominalType = decl else { return false }
            return true
        }
        XCTAssertTrue(hasNominalType,
            "Expected closure object nominal type to be synthesized")
    }

    /// Verifies that lambda functions without captures are NOT rewritten
    /// (no closure object synthesis needed for zero-capture lambdas).
    func testClosureConversionSkipsLambdaWithoutCaptures() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()
        let intType = types.make(.primitive(.int, .nonNull))

        let mainSym = SymbolID(rawValue: 1)
        let lambdaSym = SymbolID(rawValue: 2)
        let lambdaName = interner.intern("kk_lambda_50")

        // Value param only -- no captures.
        let valueParamSym = SymbolID(rawValue: -1_000_050)
        let valueExpr = arena.appendExpr(.symbolRef(valueParamSym), type: intType)

        let lambdaFn = KIRFunction(
            symbol: lambdaSym,
            name: lambdaName,
            params: [
                KIRParameter(symbol: valueParamSym, type: intType),
            ],
            returnType: intType,
            body: [
                .beginBlock,
                .constValue(result: valueExpr, value: .symbolRef(valueParamSym)),
                .returnValue(valueExpr),
                .endBlock,
            ],
            isSuspend: false,
            isInline: false
        )

        let callArg = arena.appendExpr(.intLiteral(7), type: intType)
        let callResult = arena.appendExpr(.temporary(20), type: intType)

        let mainFn = KIRFunction(
            symbol: mainSym,
            name: interner.intern("main"),
            params: [],
            returnType: intType,
            body: [
                .constValue(result: callArg, value: .intLiteral(7)),
                .call(
                    symbol: lambdaSym,
                    callee: lambdaName,
                    arguments: [callArg],
                    result: callResult,
                    canThrow: false,
                    thrownResult: nil
                ),
                .returnValue(callResult),
            ],
            isSuspend: false,
            isInline: false
        )

        let mainID = arena.appendDecl(.function(mainFn))
        _ = arena.appendDecl(.function(lambdaFn))
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [mainID])],
            arena: arena
        )

        let pass = LambdaClosureConversionPass()
        let ctx = KIRContext(
            diagnostics: DiagnosticEngine(),
            options: CompilerOptions(
                moduleName: "NoCaptureTest",
                inputs: [],
                outputPath: FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString).path,
                emit: .kirDump,
                target: defaultTargetTriple()
            ),
            interner: interner
        )

        try pass.run(module: module, ctx: ctx)

        guard case let .function(loweredMain)? = module.arena.decl(mainID) else {
            XCTFail("Expected lowered main function.")
            return
        }

        let callees = extractCallees(from: loweredMain.body, interner: interner)

        // No closure object should be allocated.
        XCTAssertFalse(callees.contains("kk_object_new"),
            "Expected no closure object for zero-capture lambda")

        // Direct call to the lambda should remain.
        XCTAssertTrue(callees.contains("kk_lambda_50"),
            "Expected direct lambda call to remain for zero-capture lambda")
    }

    /// Verifies that the invoke wrapper function correctly loads captures
    /// via kk_array_get_inbounds and forwards to the original lambda.
    func testClosureConversionInvokeWrapperLoadsCaptures() throws {
        let interner = StringInterner()
        let arena = KIRArena()
        let types = TypeSystem()
        let intType = types.make(.primitive(.int, .nonNull))

        let mainSym = SymbolID(rawValue: 1)
        let lambdaSym = SymbolID(rawValue: 3)
        let lambdaName = interner.intern("kk_lambda_99")

        let captureParamSym = SymbolID(rawValue: -2_000_099)
        let valueParamSym = SymbolID(rawValue: -1_000_099)

        let captureExpr = arena.appendExpr(.symbolRef(captureParamSym), type: intType)
        let valueExpr = arena.appendExpr(.symbolRef(valueParamSym), type: intType)

        let lambdaFn = KIRFunction(
            symbol: lambdaSym,
            name: lambdaName,
            params: [
                KIRParameter(symbol: captureParamSym, type: intType),
                KIRParameter(symbol: valueParamSym, type: intType),
            ],
            returnType: intType,
            body: [
                .beginBlock,
                .constValue(result: captureExpr, value: .symbolRef(captureParamSym)),
                .constValue(result: valueExpr, value: .symbolRef(valueParamSym)),
                .returnValue(captureExpr),
                .endBlock,
            ],
            isSuspend: false,
            isInline: false
        )

        let capturedValue = arena.appendExpr(.intLiteral(42), type: intType)
        let callArg = arena.appendExpr(.intLiteral(1), type: intType)
        let callResult = arena.appendExpr(.temporary(30), type: intType)

        let mainFn = KIRFunction(
            symbol: mainSym,
            name: interner.intern("main"),
            params: [],
            returnType: intType,
            body: [
                .constValue(result: capturedValue, value: .intLiteral(42)),
                .constValue(result: callArg, value: .intLiteral(1)),
                .call(
                    symbol: lambdaSym,
                    callee: lambdaName,
                    arguments: [capturedValue, callArg],
                    result: callResult,
                    canThrow: false,
                    thrownResult: nil
                ),
                .returnValue(callResult),
            ],
            isSuspend: false,
            isInline: false
        )

        let mainID = arena.appendDecl(.function(mainFn))
        _ = arena.appendDecl(.function(lambdaFn))
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [mainID])],
            arena: arena
        )

        let pass = LambdaClosureConversionPass()
        let ctx = KIRContext(
            diagnostics: DiagnosticEngine(),
            options: CompilerOptions(
                moduleName: "InvokeWrapperTest",
                inputs: [],
                outputPath: FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString).path,
                emit: .kirDump,
                target: defaultTargetTriple()
            ),
            interner: interner
        )

        try pass.run(module: module, ctx: ctx)

        // Find the synthesized invoke wrapper.
        let invokeWrapperName = "kk_closure_invoke_\(lambdaSym.rawValue)"
        let invokeWrapper = module.arena.declarations.compactMap { decl -> KIRFunction? in
            guard case let .function(function) = decl else { return nil }
            return interner.resolve(function.name) == invokeWrapperName ? function : nil
        }.first

        let wrapper = try XCTUnwrap(invokeWrapper, "Expected invoke wrapper to be synthesized")

        // Wrapper should have params: (closureObj, valueParam).
        XCTAssertEqual(wrapper.params.count, 2,
            "Expected invoke wrapper to have 2 params (closureObj + 1 value param)")

        // Wrapper body should contain kk_array_get_inbounds to load capture.
        let wrapperCallees = extractCallees(from: wrapper.body, interner: interner)
        XCTAssertTrue(wrapperCallees.contains("kk_array_get_inbounds"),
            "Expected invoke wrapper to load captures via kk_array_get_inbounds")

        // Wrapper body should call the original lambda.
        XCTAssertTrue(wrapperCallees.contains("kk_lambda_99"),
            "Expected invoke wrapper to forward to original lambda")
    }
}
