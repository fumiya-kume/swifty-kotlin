@testable import CompilerCore
import XCTest

extension BuildASTBodyParsingRegressionTests {
    // MARK: - Trailing lambda call parsing

    func testTrailingLambdaCallsWithoutParenthesesParseAsCalls() throws {
        let source = """
        fun main() {
            val s = buildString {
                append("hello ")
                append("world")
            }
            val xs = buildList {
                add(1)
                add(2)
            }
            println(s)
            println(xs)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runFrontend(ctx)
            let ast = try XCTUnwrap(ctx.ast)
            let localsByName = try mainLocalInitializers(ast: ast, interner: ctx.interner)
            try assertBuilderLambdaInitializer(
                named: "s",
                expectedStatementCalls: 1,
                localsByName: localsByName,
                ast: ast
            )
            try assertBuilderLambdaInitializer(
                named: "xs",
                expectedStatementCalls: 1,
                localsByName: localsByName,
                ast: ast
            )
        }
    }

    private func mainLocalInitializers(ast: ASTModule, interner: StringInterner) throws -> [String: ExprID] {
        let mainDecl = ast.arena.declarations().compactMap { decl -> FunDecl? in
            guard case let .funDecl(funDecl) = decl else { return nil }
            return interner.resolve(funDecl.name) == "main" ? funDecl : nil
        }.first
        guard let mainDecl,
              case let .block(exprs, _) = mainDecl.body
        else {
            XCTFail("main function block was not parsed.")
            return [:]
        }

        let localInitializers = exprs.compactMap { exprID -> (String, ExprID)? in
            guard let expr = ast.arena.expr(exprID),
                  case let .localDecl(name, _, _, initializer, _) = expr,
                  let initializer
            else {
                return nil
            }
            return (interner.resolve(name), initializer)
        }
        return Dictionary(uniqueKeysWithValues: localInitializers)
    }

    private func assertBuilderLambdaInitializer(
        named name: String,
        expectedStatementCalls: Int,
        localsByName: [String: ExprID],
        ast: ASTModule
    ) throws {
        let initializer = try XCTUnwrap(localsByName[name], "Missing '\(name)' initializer.")
        guard let initExpr = ast.arena.expr(initializer),
              case let .call(_, _, args, _) = initExpr
        else {
            XCTFail("Expected '\(name)' initializer to be .call with trailing lambda.")
            return
        }
        XCTAssertEqual(args.count, 1, "Expected '\(name)' call to have exactly one trailing lambda argument.")
        guard let lambdaArg = args.first,
              let lambdaExpr = ast.arena.expr(lambdaArg.expr),
              case let .lambdaLiteral(_, body, _, _) = lambdaExpr,
              let bodyExpr = ast.arena.expr(body),
              case let .blockExpr(statements, trailingExpr, _) = bodyExpr
        else {
            XCTFail("Expected '\(name)' call argument to be .lambdaLiteral with .blockExpr body.")
            return
        }
        XCTAssertEqual(
            statements.count,
            expectedStatementCalls,
            "Unexpected statement count for '\(name)' lambda body."
        )
        for (index, statement) in statements.enumerated() {
            assertCallExpression(statement, label: "'\(name)' lambda statement[\(index)]", ast: ast)
        }
        let trailing = try XCTUnwrap(trailingExpr, "Expected '\(name)' lambda body to have trailing expression.")
        assertCallExpression(trailing, label: "'\(name)' lambda trailing expression", ast: ast)
    }

    private func assertCallExpression(_ exprID: ExprID, label: String, ast: ASTModule) {
        guard let expr = ast.arena.expr(exprID) else {
            XCTFail("Missing AST expr for \(label).")
            return
        }
        guard case .call = expr else {
            XCTFail("Expected \(label) to be .call, got \(expr).")
            return
        }
    }
}
