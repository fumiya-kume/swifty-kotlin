import Foundation
import XCTest
@testable import CompilerCore



extension BuildKIRRegressionTests {
    func testBuildKIRObjectLiteralArgumentIsNotLoweredToUnitPlaceholder() throws {
        let source = """
        interface I
        fun consume(value: I): I = value
        fun main(): I {
            val instance = object : I {}
            return consume(instance)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let consumeCall = try XCTUnwrap(mainBody.first { instruction in
                guard case .call(_, let callee, _, _, _, _, _) = instruction else {
                    return false
                }
                return ctx.interner.resolve(callee) == "consume"
            })
            guard case .call(_, _, let arguments, _, _, _, _) = consumeCall else {
                XCTFail("Expected call instruction for consume(instance).")
                return
            }
            let objectArgument = try XCTUnwrap(arguments.first)
            let objectArgumentExpr = try XCTUnwrap(module.arena.expr(objectArgument))
            if case .unit = objectArgumentExpr {
                XCTFail("object literal must not be lowered to .unit placeholder at call sites.")
            }
        }
    }

    func testBuildKIRLowersLambdaLiteralToGeneratedCallableAndPrependsCapturesOnCall() throws {
        let source = """
        fun main(): Int {
            val base = 40
            val add = { x -> base + x }
            return add(2)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let lambdaCall = try XCTUnwrap(mainBody.first { instruction in
                guard case .call(_, let callee, _, _, _, _, _) = instruction else {
                    return false
                }
                return ctx.interner.resolve(callee).hasPrefix("kk_lambda_")
            })

            guard case .call(let callSymbol, let callee, let arguments, _, _, _, _) = lambdaCall else {
                XCTFail("Expected lowered lambda call in main.")
                return
            }
            XCTAssertNotNil(callSymbol)
            XCTAssertTrue(ctx.interner.resolve(callee).hasPrefix("kk_lambda_"))
            XCTAssertEqual(arguments.count, 2)
            guard case .intLiteral(40)? = module.arena.expr(arguments[0]) else {
                XCTFail("Expected first lambda call argument to be captured 'base'.")
                return
            }
            guard case .intLiteral(2)? = module.arena.expr(arguments[1]) else {
                XCTFail("Expected second lambda call argument to be the explicit call argument.")
                return
            }

            let generatedLambdaFunctions = module.arena.declarations.compactMap { decl -> KIRFunction? in
                guard case .function(let function) = decl,
                      ctx.interner.resolve(function.name).hasPrefix("kk_lambda_") else {
                    return nil
                }
                return function
            }
            XCTAssertFalse(generatedLambdaFunctions.isEmpty)
            if let generatedSymbol = callSymbol,
               let generatedFunction = generatedLambdaFunctions.first(where: { $0.symbol == generatedSymbol }) {
                XCTAssertEqual(generatedFunction.params.count, 2)
            }
        }
    }

    func testBuildKIRCallableValueCallRespectsParameterMappingBeforePrependingCaptures() throws {
        let source = """
        fun main(): Int {
            val base = 100
            val add = { a, b -> base + a + b }
            return add(1, 2)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let addCallExprID = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case .call(let calleeExprID, _, _, _) = expr,
                      let calleeExpr = ast.arena.expr(calleeExprID),
                      case .nameRef(let calleeName, _) = calleeExpr else {
                    return false
                }
                return ctx.interner.resolve(calleeName) == "add"
            })
            let existingBinding = try XCTUnwrap(sema.bindings.callableValueCalls[addCallExprID])
            sema.bindings.bindCallableValueCall(
                addCallExprID,
                binding: CallableValueCallBinding(
                    target: existingBinding.target,
                    functionType: existingBinding.functionType,
                    parameterMapping: [0: 1, 1: 0]
                )
            )

            try BuildKIRPhase().run(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let lambdaCall = try XCTUnwrap(mainBody.first { instruction in
                guard case .call(_, let callee, _, _, _, _, _) = instruction else {
                    return false
                }
                return ctx.interner.resolve(callee).hasPrefix("kk_lambda_")
            })

            guard case .call(_, _, let arguments, _, _, _, _) = lambdaCall else {
                XCTFail("Expected callable-value call to lowered lambda target.")
                return
            }
            XCTAssertEqual(arguments.count, 3)
            guard case .intLiteral(100)? = module.arena.expr(arguments[0]) else {
                XCTFail("Expected capture argument to stay prepended at index 0.")
                return
            }
            guard case .intLiteral(2)? = module.arena.expr(arguments[1]) else {
                XCTFail("Expected parameter mapping to reorder explicit args before call emission.")
                return
            }
            guard case .intLiteral(1)? = module.arena.expr(arguments[2]) else {
                XCTFail("Expected reordered second parameter argument.")
                return
            }
        }
    }

    func testSyntheticLambdaSymbolGenerationNeverUsesZeroOrInvalidSentinel() {
        let loweringCtx = KIRLoweringContext()
        let zeroExprSymbol = loweringCtx.syntheticLambdaSymbol(for: ExprID(rawValue: 0))
        let maxExprSymbol = loweringCtx.syntheticLambdaSymbol(for: ExprID(rawValue: Int32.max))

        XCTAssertEqual(zeroExprSymbol, loweringCtx.syntheticLambdaSymbol(for: ExprID(rawValue: 0)))
        XCTAssertGreaterThan(zeroExprSymbol.rawValue, 0)
        XCTAssertNotEqual(zeroExprSymbol.rawValue, 0)
        XCTAssertNotEqual(zeroExprSymbol, .invalid)

        XCTAssertGreaterThan(maxExprSymbol.rawValue, 0)
        XCTAssertNotEqual(maxExprSymbol.rawValue, 0)
        XCTAssertNotEqual(maxExprSymbol, .invalid)
        XCTAssertNotEqual(maxExprSymbol, zeroExprSymbol)
    }

    func testBuildKIRLowersCallableRefToCallableSymbolValue() throws {
        let source = """
        fun inc(x: Int): Int = x + 1
        fun main(): Int {
            val f = ::inc
            return f(2)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let module = try XCTUnwrap(ctx.kir)
            let incSymbol = try XCTUnwrap(sema.symbols.allSymbols().first(where: { symbol in
                symbol.kind == .function && ctx.interner.resolve(symbol.name) == "inc"
            })?.id)

            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let incCall = try XCTUnwrap(mainBody.first { instruction in
                guard case .call(let symbol, _, _, _, _, _, _) = instruction else {
                    return false
                }
                return symbol == incSymbol
            })

            guard case .call(let callSymbol, let callee, let arguments, _, _, _, _) = incCall else {
                XCTFail("Expected callable reference call to inc.")
                return
            }
            XCTAssertEqual(callSymbol, incSymbol)
            XCTAssertEqual(ctx.interner.resolve(callee), "inc")
            XCTAssertEqual(arguments.count, 1)
            guard case .intLiteral(2)? = module.arena.expr(arguments[0]) else {
                XCTFail("Expected callable reference call to forward the explicit argument.")
                return
            }
        }
    }

    func testBuildKIRPrependsBoundCallableRefReceiverAsCaptureArgument() throws {
        let source = """
        class Box {
            fun plus(x: Int): Int = x
        }
        fun main(box: Box): Int {
            val f = box::plus
            return f(7)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let module = try XCTUnwrap(ctx.kir)
            let plusSymbol = try XCTUnwrap(sema.symbols.allSymbols().first(where: { symbol in
                symbol.kind == .function && ctx.interner.resolve(symbol.name) == "plus"
            })?.id)

            let mainBody = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let plusCall = try XCTUnwrap(mainBody.first { instruction in
                guard case .call(let symbol, _, _, _, _, _, _) = instruction else {
                    return false
                }
                return symbol == plusSymbol
            })

            guard case .call(_, let callee, let arguments, _, _, _, _) = plusCall else {
                XCTFail("Expected bound callable reference to lower to plus call.")
                return
            }
            XCTAssertEqual(ctx.interner.resolve(callee), "plus")
            XCTAssertEqual(arguments.count, 2)
            guard case .symbolRef(let receiverSymbol)? = module.arena.expr(arguments[0]),
                  let receiver = sema.symbols.symbol(receiverSymbol) else {
                XCTFail("Expected first argument to be captured receiver symbol.")
                return
            }
            XCTAssertEqual(ctx.interner.resolve(receiver.name), "box")
            guard case .intLiteral(7)? = module.arena.expr(arguments[1]) else {
                XCTFail("Expected second argument to be call-site argument.")
                return
            }
        }
    }

    // MARK: - P5-39: vararg call lowering / ABI regression tests

}
