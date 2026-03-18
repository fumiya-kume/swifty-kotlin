@testable import CompilerCore
import Foundation
import XCTest

// MARK: - Test Helpers

/// Bundles the common infrastructure every inline-lambda test needs so that
/// individual tests only specify what differs per case (function bodies,
/// declarations, assertions).
private struct InlineLambdaTestContext {
    let interner = StringInterner()
    let arena = KIRArena()
    let symbols = SymbolTable()
    let types = TypeSystem()
    let bindings = BindingTable()
    let diagnostics = DiagnosticEngine()

    let intType: TypeID
    let funcType: TypeID

    init() {
        intType = types.make(.primitive(.int, .nonNull))
        funcType = types.make(.functionType(FunctionType(
            params: [intType],
            returnType: intType
        )))
    }

    /// Register an inline function with a single value parameter and a
    /// block parameter of `(Int) -> Int` type, returning `Int`.
    func defineInlineFunction(
        name: String
    ) -> (symbol: SymbolID, valueParam: SymbolID, blockParam: SymbolID) {
        let symbol = symbols.define(
            kind: .function,
            name: interner.intern(name),
            fqName: [interner.intern("test"), interner.intern(name)],
            declSite: nil,
            visibility: .public,
            flags: [.inlineFunction]
        )
        let valueParam = symbols.define(
            kind: .valueParameter,
            name: interner.intern("x"),
            fqName: [interner.intern("test"), interner.intern(name), interner.intern("x")],
            declSite: nil,
            visibility: .private
        )
        let blockParam = symbols.define(
            kind: .valueParameter,
            name: interner.intern("block"),
            fqName: [interner.intern("test"), interner.intern(name), interner.intern("block")],
            declSite: nil,
            visibility: .private
        )
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [intType, funcType],
                returnType: intType,
                valueParameterSymbols: [valueParam, blockParam]
            ),
            for: symbol
        )
        return (symbol, valueParam, blockParam)
    }

    /// Register a lambda function with a single `Int` parameter.
    func defineLambda(
        name: String,
        paramName: String
    ) -> (symbol: SymbolID, paramSymbol: SymbolID) {
        let symbol = symbols.define(
            kind: .function,
            name: interner.intern(name),
            fqName: [interner.intern("test"), interner.intern(name)],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        let paramSymbol = symbols.define(
            kind: .valueParameter,
            name: interner.intern(paramName),
            fqName: [interner.intern("test"), interner.intern(name), interner.intern(paramName)],
            declSite: nil,
            visibility: .private
        )
        return (symbol, paramSymbol)
    }

    /// Register a plain function symbol (e.g. main, or an external function).
    func defineFunction(name: String, flags: SymbolFlags = []) -> SymbolID {
        symbols.define(
            kind: .function,
            name: interner.intern(name),
            fqName: [interner.intern("test"), interner.intern(name)],
            declSite: nil,
            visibility: .public,
            flags: flags
        )
    }

    /// Build a KIR module, run the lowering phase, and return the callees
    /// found in the lowered main function.
    func lowerAndExtractCallees(
        mainFunction: KIRFunction,
        otherDecls: [KIRFunction],
        moduleName: String
    ) throws -> (callees: [String], loweredMain: KIRFunction) {
        let mainDeclID = arena.appendDecl(.function(mainFunction))
        for decl in otherDecls {
            _ = arena.appendDecl(.function(decl))
        }
        let module = KIRModule(
            files: [KIRFile(fileID: FileID(rawValue: 0), decls: [mainDeclID])],
            arena: arena
        )
        let sema = SemaModule(
            symbols: symbols,
            types: types,
            bindings: bindings,
            diagnostics: diagnostics
        )
        let ctx = CompilationContext(
            options: CompilerOptions(
                moduleName: moduleName,
                inputs: [],
                outputPath: FileManager.default.temporaryDirectory
                    .appendingPathComponent(UUID().uuidString).path,
                emit: .kirDump,
                target: defaultTargetTriple()
            ),
            sourceManager: SourceManager(),
            diagnostics: diagnostics,
            interner: interner
        )
        ctx.kir = module
        ctx.sema = sema

        try LoweringPhase().run(ctx)

        guard case let .function(loweredMain)? = module.arena.decl(mainDeclID) else {
            throw NSError(domain: "Test", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "Expected lowered main function",
            ])
        }
        let callees = extractCallees(from: loweredMain.body, interner: interner)
        return (callees, loweredMain)
    }
}

// MARK: - Tests

extension LoweringPassRegressionTests {

    // MARK: - INLINE-002: Lambda argument inlining

    /// Verify that a lambda passed to an inline function is expanded in place,
    /// eliminating the indirect call to the lambda function.
    func testInlineLoweringInlinesLambdaArgumentBody() throws {
        let tc = InlineLambdaTestContext()

        let mainSymbol = tc.defineFunction(name: "main")
        let (inlineSymbol, inlineValueParam, inlineBlockParam) =
            tc.defineInlineFunction(name: "applyBlock")
        let (lambdaSymbol, lambdaParamSymbol) =
            tc.defineLambda(name: "$lambda_0", paramName: "it")

        // Lambda function: { it -> it + 10 }
        let lambdaArgExpr = tc.arena.appendExpr(.symbolRef(lambdaParamSymbol), type: tc.intType)
        let lambdaTenExpr = tc.arena.appendExpr(.intLiteral(10), type: tc.intType)
        let lambdaSumExpr = tc.arena.appendExpr(.temporary(100), type: tc.intType)

        let lambdaFunction = KIRFunction(
            symbol: lambdaSymbol,
            name: tc.interner.intern("$lambda_0"),
            params: [KIRParameter(symbol: lambdaParamSymbol, type: tc.intType)],
            returnType: tc.intType,
            body: [
                .beginBlock,
                .constValue(result: lambdaArgExpr, value: .symbolRef(lambdaParamSymbol)),
                .constValue(result: lambdaTenExpr, value: .intLiteral(10)),
                .call(
                    symbol: nil,
                    callee: tc.interner.intern("kk_op_add"),
                    arguments: [lambdaArgExpr, lambdaTenExpr],
                    result: lambdaSumExpr,
                    canThrow: false,
                    thrownResult: nil
                ),
                .returnValue(lambdaSumExpr),
                .endBlock,
            ],
            isSuspend: false,
            isInline: false
        )

        // Inline function: inline fun applyBlock(x: Int, block: (Int) -> Int): Int = block(x)
        let inlineXExpr = tc.arena.appendExpr(.symbolRef(inlineValueParam), type: tc.intType)
        let inlineBlockExpr = tc.arena.appendExpr(.symbolRef(inlineBlockParam), type: tc.funcType)
        let inlineCallResult = tc.arena.appendExpr(.temporary(200), type: tc.intType)

        let inlineFunction = KIRFunction(
            symbol: inlineSymbol,
            name: tc.interner.intern("applyBlock"),
            params: [
                KIRParameter(symbol: inlineValueParam, type: tc.intType),
                KIRParameter(symbol: inlineBlockParam, type: tc.funcType),
            ],
            returnType: tc.intType,
            body: [
                .constValue(result: inlineXExpr, value: .symbolRef(inlineValueParam)),
                .constValue(result: inlineBlockExpr, value: .symbolRef(inlineBlockParam)),
                .call(
                    symbol: inlineBlockParam,
                    callee: tc.interner.intern("$lambda_0"),
                    arguments: [inlineXExpr],
                    result: inlineCallResult,
                    canThrow: false,
                    thrownResult: nil
                ),
                .returnValue(inlineCallResult),
            ],
            isSuspend: false,
            isInline: true
        )

        // Caller: fun main(): Int = applyBlock(5) { it + 10 }
        let callerFiveExpr = tc.arena.appendExpr(.intLiteral(5), type: tc.intType)
        let callerLambdaRef = tc.arena.appendExpr(.symbolRef(lambdaSymbol), type: tc.funcType)
        let callerResult = tc.arena.appendExpr(.temporary(300), type: tc.intType)

        let mainFunction = KIRFunction(
            symbol: mainSymbol,
            name: tc.interner.intern("main"),
            params: [],
            returnType: tc.intType,
            body: [
                .constValue(result: callerFiveExpr, value: .intLiteral(5)),
                .constValue(result: callerLambdaRef, value: .symbolRef(lambdaSymbol)),
                .call(
                    symbol: inlineSymbol,
                    callee: tc.interner.intern("applyBlock"),
                    arguments: [callerFiveExpr, callerLambdaRef],
                    result: callerResult,
                    canThrow: false,
                    thrownResult: nil
                ),
                .returnValue(callerResult),
            ],
            isSuspend: false,
            isInline: false
        )

        let (callees, _) = try tc.lowerAndExtractCallees(
            mainFunction: mainFunction,
            otherDecls: [inlineFunction, lambdaFunction],
            moduleName: "InlineLambda"
        )

        // The inline function call should be eliminated.
        XCTAssertFalse(
            callees.contains("applyBlock"),
            "applyBlock should have been inlined, got callees: \(callees)"
        )

        // The lambda indirect call should also be eliminated; instead the
        // lambda body (kk_op_add) should appear directly.
        XCTAssertFalse(
            callees.contains("$lambda_0"),
            "Lambda should have been inlined, got callees: \(callees)"
        )
        XCTAssertFalse(
            callees.contains("kk_lambda_invoke"),
            "Should not have indirect lambda invoke, got callees: \(callees)"
        )
        XCTAssertTrue(
            callees.contains("kk_op_add"),
            "Lambda body should be inlined with kk_op_add, got callees: \(callees)"
        )
    }

    /// Verify that non-lambda arguments (e.g. function references that are not
    /// resolved to a KIR function) still produce a regular call instruction.
    func testInlineLoweringFallsBackWhenLambdaNotResolvable() throws {
        let tc = InlineLambdaTestContext()

        let mainSymbol = tc.defineFunction(name: "main")
        let (inlineSymbol, inlineValueParam, inlineBlockParam) =
            tc.defineInlineFunction(name: "applyBlock")
        // Use a symbol that does NOT exist as a KIR function declaration.
        let unknownFuncSymbol = tc.defineFunction(name: "externalFunc")

        // Inline function body: block(x)
        let inlineXExpr = tc.arena.appendExpr(.symbolRef(inlineValueParam), type: tc.intType)
        let inlineBlockExpr = tc.arena.appendExpr(.symbolRef(inlineBlockParam), type: tc.funcType)
        let inlineCallResult = tc.arena.appendExpr(.temporary(0), type: tc.intType)

        let inlineFunction = KIRFunction(
            symbol: inlineSymbol,
            name: tc.interner.intern("applyBlock"),
            params: [
                KIRParameter(symbol: inlineValueParam, type: tc.intType),
                KIRParameter(symbol: inlineBlockParam, type: tc.funcType),
            ],
            returnType: tc.intType,
            body: [
                .constValue(result: inlineXExpr, value: .symbolRef(inlineValueParam)),
                .constValue(result: inlineBlockExpr, value: .symbolRef(inlineBlockParam)),
                .call(
                    symbol: inlineBlockParam,
                    callee: tc.interner.intern("externalFunc"),
                    arguments: [inlineXExpr],
                    result: inlineCallResult,
                    canThrow: false,
                    thrownResult: nil
                ),
                .returnValue(inlineCallResult),
            ],
            isSuspend: false,
            isInline: true
        )

        // Caller passes a non-lambda symbolRef (not in module declarations).
        let callerArg = tc.arena.appendExpr(.intLiteral(42), type: tc.intType)
        let callerFuncRef = tc.arena.appendExpr(.symbolRef(unknownFuncSymbol), type: tc.funcType)
        let callerResult = tc.arena.appendExpr(.temporary(1), type: tc.intType)

        let mainFunction = KIRFunction(
            symbol: mainSymbol,
            name: tc.interner.intern("main"),
            params: [],
            returnType: tc.intType,
            body: [
                .constValue(result: callerArg, value: .intLiteral(42)),
                .constValue(result: callerFuncRef, value: .symbolRef(unknownFuncSymbol)),
                .call(
                    symbol: inlineSymbol,
                    callee: tc.interner.intern("applyBlock"),
                    arguments: [callerArg, callerFuncRef],
                    result: callerResult,
                    canThrow: false,
                    thrownResult: nil
                ),
                .returnValue(callerResult),
            ],
            isSuspend: false,
            isInline: false
        )

        let (callees, _) = try tc.lowerAndExtractCallees(
            mainFunction: mainFunction,
            otherDecls: [inlineFunction],
            moduleName: "InlineLambdaFallback"
        )

        // applyBlock should still be inlined (function body expansion).
        XCTAssertFalse(
            callees.contains("applyBlock"),
            "Inline function body should still be expanded"
        )

        // But the lambda call should remain as is since we cannot resolve
        // the function reference to a KIR declaration.
        XCTAssertTrue(
            callees.contains("externalFunc"),
            "Unresolvable callable should remain as indirect call, got callees: \(callees)"
        )
    }

    /// Verify that a multi-instruction lambda body is fully inlined (not just
    /// single-expression lambdas).
    func testInlineLoweringInlinesMultiStatementLambdaBody() throws {
        let tc = InlineLambdaTestContext()

        let mainSymbol = tc.defineFunction(name: "main")
        let (inlineSymbol, inlineValueParam, inlineBlockParam) =
            tc.defineInlineFunction(name: "transform")
        let (lambdaSymbol, lambdaParamSymbol) =
            tc.defineLambda(name: "$lambda_1", paramName: "n")

        // Lambda: { n -> val doubled = n * 2; doubled + 1 }
        let lambdaArgExpr = tc.arena.appendExpr(.symbolRef(lambdaParamSymbol), type: tc.intType)
        let lambdaTwoExpr = tc.arena.appendExpr(.intLiteral(2), type: tc.intType)
        let lambdaDoubledExpr = tc.arena.appendExpr(.temporary(50), type: tc.intType)
        let lambdaOneExpr = tc.arena.appendExpr(.intLiteral(1), type: tc.intType)
        let lambdaResultExpr = tc.arena.appendExpr(.temporary(51), type: tc.intType)

        let lambdaFunction = KIRFunction(
            symbol: lambdaSymbol,
            name: tc.interner.intern("$lambda_1"),
            params: [KIRParameter(symbol: lambdaParamSymbol, type: tc.intType)],
            returnType: tc.intType,
            body: [
                .beginBlock,
                .constValue(result: lambdaArgExpr, value: .symbolRef(lambdaParamSymbol)),
                .constValue(result: lambdaTwoExpr, value: .intLiteral(2)),
                .call(
                    symbol: nil,
                    callee: tc.interner.intern("kk_op_mul"),
                    arguments: [lambdaArgExpr, lambdaTwoExpr],
                    result: lambdaDoubledExpr,
                    canThrow: false,
                    thrownResult: nil
                ),
                .constValue(result: lambdaOneExpr, value: .intLiteral(1)),
                .call(
                    symbol: nil,
                    callee: tc.interner.intern("kk_op_add"),
                    arguments: [lambdaDoubledExpr, lambdaOneExpr],
                    result: lambdaResultExpr,
                    canThrow: false,
                    thrownResult: nil
                ),
                .returnValue(lambdaResultExpr),
                .endBlock,
            ],
            isSuspend: false,
            isInline: false
        )

        // Inline: inline fun transform(x: Int, block: (Int) -> Int): Int = block(x)
        let inlineXExpr = tc.arena.appendExpr(.symbolRef(inlineValueParam), type: tc.intType)
        let inlineBlockExpr = tc.arena.appendExpr(.symbolRef(inlineBlockParam), type: tc.funcType)
        let inlineCallResult = tc.arena.appendExpr(.temporary(60), type: tc.intType)

        let inlineFunction = KIRFunction(
            symbol: inlineSymbol,
            name: tc.interner.intern("transform"),
            params: [
                KIRParameter(symbol: inlineValueParam, type: tc.intType),
                KIRParameter(symbol: inlineBlockParam, type: tc.funcType),
            ],
            returnType: tc.intType,
            body: [
                .constValue(result: inlineXExpr, value: .symbolRef(inlineValueParam)),
                .constValue(result: inlineBlockExpr, value: .symbolRef(inlineBlockParam)),
                .call(
                    symbol: inlineBlockParam,
                    callee: tc.interner.intern("$lambda_1"),
                    arguments: [inlineXExpr],
                    result: inlineCallResult,
                    canThrow: false,
                    thrownResult: nil
                ),
                .returnValue(inlineCallResult),
            ],
            isSuspend: false,
            isInline: true
        )

        // Caller
        let callerArgExpr = tc.arena.appendExpr(.intLiteral(7), type: tc.intType)
        let callerLambdaRef = tc.arena.appendExpr(.symbolRef(lambdaSymbol), type: tc.funcType)
        let callerResult = tc.arena.appendExpr(.temporary(70), type: tc.intType)

        let mainFunction = KIRFunction(
            symbol: mainSymbol,
            name: tc.interner.intern("main"),
            params: [],
            returnType: tc.intType,
            body: [
                .constValue(result: callerArgExpr, value: .intLiteral(7)),
                .constValue(result: callerLambdaRef, value: .symbolRef(lambdaSymbol)),
                .call(
                    symbol: inlineSymbol,
                    callee: tc.interner.intern("transform"),
                    arguments: [callerArgExpr, callerLambdaRef],
                    result: callerResult,
                    canThrow: false,
                    thrownResult: nil
                ),
                .returnValue(callerResult),
            ],
            isSuspend: false,
            isInline: false
        )

        let (callees, _) = try tc.lowerAndExtractCallees(
            mainFunction: mainFunction,
            otherDecls: [inlineFunction, lambdaFunction],
            moduleName: "InlineMultiLambda"
        )

        // Both the inline function and the lambda should be inlined.
        XCTAssertFalse(callees.contains("transform"))
        XCTAssertFalse(callees.contains("$lambda_1"))
        // Both operations from the lambda body should appear.
        XCTAssertTrue(
            callees.contains("kk_op_mul"),
            "Lambda mul operation should be inlined, got: \(callees)"
        )
        XCTAssertTrue(
            callees.contains("kk_op_add"),
            "Lambda add operation should be inlined, got: \(callees)"
        )
    }
}
