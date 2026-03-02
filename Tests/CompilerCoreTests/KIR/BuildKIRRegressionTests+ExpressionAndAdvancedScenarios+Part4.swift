@testable import CompilerCore
import Foundation
import XCTest

extension BuildKIRRegressionTests {
    func testBuildKIRAddsHiddenTypeTokenForInlineReifiedCalls() throws {
        let (ctx, pickSymbol, mainSymbol, typeParameterSymbol, intType) = makeReifiedCallFixture()

        try BuildKIRPhase().run(ctx)

        let kir = try XCTUnwrap(ctx.kir)
        let pickFunction = try XCTUnwrap(kir.arena.declarations.compactMap { decl -> KIRFunction? in
            guard case let .function(function) = decl else {
                return nil
            }
            return function.symbol == pickSymbol ? function : nil
        }.first)
        let mainFunction = try XCTUnwrap(kir.arena.declarations.compactMap { decl -> KIRFunction? in
            guard case let .function(function) = decl else {
                return nil
            }
            return function.symbol == mainSymbol ? function : nil
        }.first)

        // Type token symbols use a negative offset to avoid collision with real symbol IDs
        let expectedTokenSymbol = SymbolID(rawValue: Int32(typeTokenSymbolOffset) - typeParameterSymbol.rawValue)
        XCTAssertEqual(pickFunction.params.count, 2)
        XCTAssertEqual(pickFunction.params.last?.symbol, expectedTokenSymbol)

        guard let callInstruction = mainFunction.body.first(where: { instruction in
            guard case let .call(symbol, _, _, _, _, _, _) = instruction else {
                return false
            }
            return symbol == pickSymbol
        }),
            case let .call(_, _, arguments, _, _, _, _) = callInstruction
        else {
            XCTFail("Expected main to call inline reified function.")
            return
        }
        XCTAssertEqual(arguments.count, 2)
        let tokenArgument = arguments[1]
        guard case let .intLiteral(tokenLiteral)? = kir.arena.expr(tokenArgument) else {
            XCTFail("Expected hidden type token argument to be lowered as int literal.")
            return
        }
        let sema = try XCTUnwrap(ctx.sema)
        XCTAssertEqual(tokenLiteral, RuntimeTypeCheckToken.encode(type: intType, sema: sema))
    }

    func testVarargMultiplePositionalArgsPackedToArrayInKIR() throws {
        let source = """
        fun sum(vararg items: Int): Int = 0
        fun main() = sum(1, 2, 3)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let mainFunction = module.arena.declarations.compactMap { decl -> KIRFunction? in
                guard case let .function(function) = decl else { return nil }
                return ctx.interner.resolve(function.name) == "main" ? function : nil
            }.first
            let body = try XCTUnwrap(mainFunction?.body)
            let callNames = body.compactMap { instruction -> String? in
                guard case let .call(_, callee, _, _, _, _, _) = instruction else { return nil }
                return ctx.interner.resolve(callee)
            }
            XCTAssertTrue(callNames.contains("kk_array_new"), "Expected kk_array_new for vararg packing, got: \(callNames)")
            XCTAssertTrue(callNames.contains("kk_array_set"), "Expected kk_array_set for vararg packing, got: \(callNames)")
        }
    }

    func testVarargWithDefaultParamPacksCorrectly() throws {
        let source = """
        fun greet(prefix: String = "Hi", vararg names: Int): Int = 0
        fun main() = greet("Hello", 1, 2)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let mainFunction = module.arena.declarations.compactMap { decl -> KIRFunction? in
                guard case let .function(function) = decl else { return nil }
                return ctx.interner.resolve(function.name) == "main" ? function : nil
            }.first
            let body = try XCTUnwrap(mainFunction?.body)
            let callNames = body.compactMap { instruction -> String? in
                guard case let .call(_, callee, _, _, _, _, _) = instruction else { return nil }
                return ctx.interner.resolve(callee)
            }
            XCTAssertTrue(callNames.contains("kk_array_new"), "Expected kk_array_new for vararg packing with default arg, got: \(callNames)")
        }
    }

    func testVarargEmptyProducesEmptyArrayInKIR() throws {
        let source = """
        fun noArgs(vararg items: Int): Int = 0
        fun main() = noArgs()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let mainFunction = module.arena.declarations.compactMap { decl -> KIRFunction? in
                guard case let .function(function) = decl else { return nil }
                return ctx.interner.resolve(function.name) == "main" ? function : nil
            }.first
            let body = try XCTUnwrap(mainFunction?.body)
            let callNames = body.compactMap { instruction -> String? in
                guard case let .call(_, callee, _, _, _, _, _) = instruction else { return nil }
                return ctx.interner.resolve(callee)
            }
            XCTAssertTrue(callNames.contains("kk_array_new"), "Expected kk_array_new for empty vararg, got: \(callNames)")
        }
    }

    func testDefaultArgGeneratesStubFunctionInKIR() throws {
        let source = """
        fun greetUser(name: String, greeting: String = "Hello"): String = greeting
        fun main() = greetUser("Alice")
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let allFunctions = module.arena.declarations.compactMap { decl -> KIRFunction? in
                guard case let .function(function) = decl else { return nil }
                return function
            }
            let stubNames = allFunctions.map { ctx.interner.resolve($0.name) }
                .filter { $0.hasSuffix("$default") }
            XCTAssertTrue(stubNames.contains("greetUser$default"), "Expected greetUser$default stub, got: \(stubNames)")
        }
    }

    func testDefaultArgCallSiteRedirectsToStub() throws {
        let source = """
        fun add(a: Int, b: Int = 10): Int = a + b
        fun main() = add(5)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            XCTAssertTrue(callees.contains("add$default"), "Expected call to add$default stub, got: \(callees)")
        }
    }

    func testDefaultArgStubContainsMaskParameterAndOriginalCall() throws {
        let source = """
        fun compute(x: Int, y: Int = 1, z: Int = 2): Int = x + y + z
        fun main() = compute(10)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let stubFunction = module.arena.declarations.compactMap { decl -> KIRFunction? in
                guard case let .function(function) = decl else { return nil }
                return ctx.interner.resolve(function.name) == "compute$default" ? function : nil
            }.first
            XCTAssertNotNil(stubFunction, "Expected compute$default stub function")
            if let stub = stubFunction {
                let paramCount = stub.params.count
                XCTAssertGreaterThanOrEqual(paramCount, 4, "Stub should have original params + mask param")
                let stubCallees = extractCallees(from: stub.body, interner: ctx.interner)
                XCTAssertTrue(stubCallees.contains("compute"), "Stub should call original function, got: \(stubCallees)")
            }
        }
    }

    func testDefaultArgEvaluationOrderLeftToRight() throws {
        let source = """
        fun ordered(a: Int = 1, b: Int = 2, c: Int = 3): Int = a + b + c
        fun main() = ordered()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)

            let module = try XCTUnwrap(ctx.kir)
            let stubFunction = module.arena.declarations.compactMap { decl -> KIRFunction? in
                guard case let .function(function) = decl else { return nil }
                return ctx.interner.resolve(function.name) == "ordered$default" ? function : nil
            }.first
            XCTAssertNotNil(stubFunction, "Expected ordered$default stub function")
            if let stub = stubFunction {
                var labelOrder: [Int32] = []
                for instruction in stub.body {
                    if case let .label(id) = instruction {
                        labelOrder.append(id)
                    }
                }
                for i in 1 ..< labelOrder.count {
                    XCTAssertGreaterThan(labelOrder[i], labelOrder[i - 1], "Labels should be in ascending order for left-to-right evaluation")
                }
            }
        }
    }
}
