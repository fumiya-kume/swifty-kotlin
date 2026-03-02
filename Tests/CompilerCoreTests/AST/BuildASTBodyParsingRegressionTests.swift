@testable import CompilerCore
import Foundation
import XCTest

// MARK: - BuildAST BodyParsing Regression Tests

// Target: BuildASTPhase+BodyParsing.swift (56.9%)

final class BuildASTBodyParsingRegressionTests: XCTestCase {
    // MARK: - Typed local variable declaration

    func testTypedLocalVariableDeclaration() throws {
        let source = """
        fun main(): Int {
            val x: Int = 42
            var y: String = "hello"
            val z: Boolean = true
            return x
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runFrontend(ctx)
            let ast = try XCTUnwrap(ctx.ast)
            XCTAssertGreaterThanOrEqual(ast.declarationCount, 1)
        }
    }

    // MARK: - Local variable without initializer

    func testLocalVariableWithoutInitializer() throws {
        let source = """
        fun main(): Int {
            var x: Int
            x = 5
            return x
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runFrontend(ctx)
            let ast = try XCTUnwrap(ctx.ast)
            XCTAssertGreaterThanOrEqual(ast.declarationCount, 1)
        }
    }

    // MARK: - Local function with expression body

    func testLocalFunctionWithExpressionBody() throws {
        let source = """
        fun outer(): Int {
            fun add(a: Int, b: Int) = a + b
            return add(1, 2)
        }
        fun main() = outer()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            XCTAssertFalse(sema.bindings.exprTypes.isEmpty)
        }
    }

    // MARK: - Nested local function

    func testNestedLocalFunction() throws {
        let source = """
        fun outer(): Int {
            fun inner(): Int {
                fun deep(): Int = 42
                return deep()
            }
            return inner()
        }
        fun main() = outer()
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            XCTAssertFalse(sema.bindings.exprTypes.isEmpty)
        }
    }

    // MARK: - Compound assignment operators in body parsing

    func testCompoundAssignmentOperatorsInBody() throws {
        let source = """
        fun main(): Int {
            var x = 10
            x += 5
            x -= 3
            x *= 2
            x /= 4
            x %= 3
            return x
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runFrontend(ctx)
            let ast = try XCTUnwrap(ctx.ast)
            XCTAssertGreaterThanOrEqual(ast.declarationCount, 1)
        }
    }

    // MARK: - Array assignment

    func testArrayAssignmentInBody() throws {
        let source = """
        fun main(): Int {
            val arr = IntArray(5)
            arr[0] = 42
            arr[1] = 99
            return arr[0]
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runFrontend(ctx)
            let ast = try XCTUnwrap(ctx.ast)
            XCTAssertGreaterThanOrEqual(ast.declarationCount, 1)
        }
    }

    // MARK: - Block body with multiple statements

    func testBlockBodyMultipleStatements() throws {
        let source = """
        fun compute(a: Int, b: Int): Int {
            val sum = a + b
            val diff = a - b
            val product = sum * diff
            return product
        }
        fun main() = compute(5, 3)
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let module = try XCTUnwrap(ctx.kir)
            let body = try findKIRFunctionBody(named: "compute", in: module, interner: ctx.interner)
            XCTAssertFalse(body.isEmpty)
        }
    }

    // MARK: - String template in body

    func testStringTemplateInBody() throws {
        let source = """
        fun greet(name: String): String {
            val greeting = "Hello, $name!"
            return greeting
        }
        fun main() = greet("World")
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runToKIR(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            XCTAssertFalse(sema.bindings.exprTypes.isEmpty)
        }
    }

    // MARK: - Lambda/Object literal/Callable reference roundtrip

    func testLambdaObjectLiteralAndCallableReferenceRoundtripToASTLocals() throws {
        let source = """
        fun host(receiver: String): Int {
            val lambda = { value: Int -> value + 1 }
            val instance = object {
                fun size(): Int = 1
            }
            val ref = receiver::length
            return lambda(41)
        }

        fun after(): Int = 7
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runFrontend(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let funDecls = ast.arena.declarations().compactMap { decl -> FunDecl? in
                guard case let .funDecl(funDecl) = decl else {
                    return nil
                }
                return funDecl
            }
            let funNames = Set(funDecls.map { ctx.interner.resolve($0.name) })
            XCTAssertTrue(funNames.contains("host"))
            XCTAssertTrue(funNames.contains("after"))

            let hostDecl = try XCTUnwrap(funDecls.first(where: { ctx.interner.resolve($0.name) == "host" }))
            guard case let .block(bodyExprs, _) = hostDecl.body else {
                XCTFail("host should have a block body")
                return
            }

            let localInitializers = bodyExprs.compactMap { exprID -> (String, ExprID)? in
                guard let expr = ast.arena.expr(exprID),
                      case let .localDecl(name, _, _, initializer, _) = expr,
                      let initializer
                else {
                    return nil
                }
                return (ctx.interner.resolve(name), initializer)
            }
            let localsByName = Dictionary(uniqueKeysWithValues: localInitializers.map { ($0.0, $0.1) })

            let lambdaInit = try XCTUnwrap(localsByName["lambda"], "Missing lambda initializer")
            guard let lambdaExpr = ast.arena.expr(lambdaInit),
                  case .lambdaLiteral = lambdaExpr
            else {
                XCTFail("Expected `lambda` local initializer to be `.lambdaLiteral`.")
                return
            }

            let objectInit = try XCTUnwrap(localsByName["instance"], "Missing object initializer")
            guard let objectExpr = ast.arena.expr(objectInit),
                  case .objectLiteral = objectExpr
            else {
                XCTFail("Expected `instance` local initializer to be `.objectLiteral`.")
                return
            }

            let callableInit = try XCTUnwrap(localsByName["ref"], "Missing callable reference initializer")
            guard let callableExpr = ast.arena.expr(callableInit),
                  case .callableRef = callableExpr
            else {
                XCTFail("Expected `ref` local initializer to be `.callableRef`.")
                return
            }
        }
    }
}
