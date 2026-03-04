@testable import CompilerCore
import Foundation
import XCTest

extension CompilerCoreTests {
    func testTrailingLambdaWithoutParensParsesAsCallExpression() throws {
        let source = """
        fun apply(block: () -> Int): Int = block()
        fun main(): Int = apply { 42 }
        """
        let ctx = makeContextFromSource(source)
        try runFrontend(ctx)

        let ast = try XCTUnwrap(ctx.ast)
        let function = try XCTUnwrap(topLevelFunction(named: "main", in: ast, interner: ctx.interner))
        guard case let .expr(exprID, _) = function.body,
              let expr = ast.arena.expr(exprID),
              case let .call(calleeID, _, args, _) = expr
        else {
            XCTFail("Expected trailing lambda call to parse as call expression.")
            return
        }

        XCTAssertEqual(args.count, 1)
        guard let calleeExpr = ast.arena.expr(calleeID),
              case let .nameRef(calleeName, _) = calleeExpr
        else {
            XCTFail("Expected call callee to be a name reference.")
            return
        }
        XCTAssertEqual(ctx.interner.resolve(calleeName), "apply")

        guard let lambdaExpr = ast.arena.expr(args[0].expr),
              case .lambdaLiteral = lambdaExpr
        else {
            XCTFail("Expected trailing lambda argument.")
            return
        }
    }

    func testTrailingLambdaWithExplicitTypeArgsParsesAsCallExpression() throws {
        let source = """
        fun <T> build(block: () -> T): T = block()
        fun main(): Int = build<Int> { 1 }
        """
        let ctx = makeContextFromSource(source)
        try runFrontend(ctx)

        let ast = try XCTUnwrap(ctx.ast)
        let function = try XCTUnwrap(topLevelFunction(named: "main", in: ast, interner: ctx.interner))
        guard case let .expr(exprID, _) = function.body,
              let expr = ast.arena.expr(exprID),
              case let .call(_, typeArgs, args, _) = expr
        else {
            XCTFail("Expected generic trailing lambda call to parse as call expression.")
            return
        }

        XCTAssertEqual(typeArgs.count, 1)
        XCTAssertEqual(args.count, 1)
    }

    func testTrailingLambdaWithMultipleStatementsParsesAsLambdaBlockBody() throws {
        let source = """
        fun main() {
            val s = buildString {
                append("hello ")
                append("world")
            }
            println(s)
        }
        """
        let ctx = makeContextFromSource(source)
        try runFrontend(ctx)

        let ast = try XCTUnwrap(ctx.ast)
        let function = try XCTUnwrap(topLevelFunction(named: "main", in: ast, interner: ctx.interner))
        guard case let .block(statements, _) = function.body,
              let localDeclID = statements.first,
              let localDeclExpr = ast.arena.expr(localDeclID),
              case let .localDecl(_, _, _, initializer, _) = localDeclExpr,
              let callExprID = initializer,
              let callExpr = ast.arena.expr(callExprID),
              case let .call(_, _, args, _) = callExpr,
              let lambdaArg = args.first,
              let lambdaExpr = ast.arena.expr(lambdaArg.expr),
              case let .lambdaLiteral(_, lambdaBodyID, _, _) = lambdaExpr,
              let lambdaBody = ast.arena.expr(lambdaBodyID),
              case let .blockExpr(bodyStatements, trailingExpr, _) = lambdaBody
        else {
            XCTFail("Expected builder trailing lambda body to be parsed as block expression.")
            return
        }

        XCTAssertEqual(bodyStatements.count, 1)
        let firstStmtID = try XCTUnwrap(bodyStatements.first)
        let trailingID = try XCTUnwrap(trailingExpr)
        guard let firstStmt = ast.arena.expr(firstStmtID), case .call = firstStmt else {
            XCTFail("Expected first lambda statement to be a call expression.")
            return
        }
        guard let trailing = ast.arena.expr(trailingID), case .call = trailing else {
            XCTFail("Expected trailing lambda expression to be a call expression.")
            return
        }
    }
}
