@testable import CompilerCore
import Testing

@Suite
struct UnbracedIfAssignmentTests {
    private func parsedIf(in context: CompilationContext) throws -> (ASTModule, Expr) {
        let ast = try #require(context.ast)
        let file = try #require(ast.files.first {
            context.sourceManager.origin(of: $0.fileID) == .user
        })
        let function = try #require(file.topLevelDecls.compactMap { declaration -> FunDecl? in
            guard case let .funDecl(function) = ast.arena.decl(declaration),
                  context.interner.resolve(function.name) == "choose"
            else { return nil }
            return function
        }.first)
        guard case let .block(statements, _) = function.body else {
            throw TestFailure("Expected a function block")
        }
        let statement = try #require(statements.first { expression in
            if case .ifExpr = ast.arena.expr(expression) { return true }
            return false
        })
        return (ast, try #require(ast.arena.expr(statement)))
    }

    @Test
    func assignmentThenBodyDoesNotConsumeElse() throws {
        let context = makeContextFromSource("""
        fun choose(flag: Boolean) {
            var value = 0
            if (flag) value = 1 else value = 2
        }
        """)
        try runFrontend(context)
        let (ast, branch) = try parsedIf(in: context)
        guard case let .ifExpr(_, thenID, elseID, _) = branch,
              case let .localAssign(_, thenValue, _) = ast.arena.expr(thenID),
              let elseID,
              case let .localAssign(_, elseValue, _) = ast.arena.expr(elseID)
        else {
            Issue.record("Both unbraced branches must preserve their assignments")
            return
        }
        guard case .intLiteral(1, _) = ast.arena.expr(thenValue),
              case .intLiteral(2, _) = ast.arena.expr(elseValue)
        else {
            Issue.record("Assignments must retain the value from their own branch")
            return
        }
    }

    @Test
    func comparisonInAssignmentDoesNotHideElse() throws {
        let context = makeContextFromSource("""
        fun choose(flag: Boolean, input: Int) {
            var value = false
            if (flag) value = input < 0 else value = true
        }
        """)
        try runFrontend(context)
        let (ast, branch) = try parsedIf(in: context)
        guard case let .ifExpr(_, _, elseID, _) = branch,
              let elseID,
              case let .localAssign(_, elseValue, _) = ast.arena.expr(elseID),
              case .boolLiteral(true, _) = ast.arena.expr(elseValue)
        else {
            Issue.record("A comparison must preserve the enclosing else assignment")
            return
        }
    }

    @Test
    func nestedIfValueKeepsItsElseAndTheEnclosingElse() throws {
        let context = makeContextFromSource("""
        fun choose(outer: Boolean, inner: Boolean) {
            var value = 0
            if (outer) value = if (inner) 1 else 2 else value = 3
        }
        """)
        try runFrontend(context)
        let (ast, branch) = try parsedIf(in: context)
        guard case let .ifExpr(_, thenID, elseID, _) = branch,
              case let .localAssign(_, value, _) = ast.arena.expr(thenID),
              case let .ifExpr(_, _, innerElseID, _) = ast.arena.expr(value)
        else {
            Issue.record("Expected an assignment of an if expression")
            return
        }
        #expect(elseID != nil)
        #expect(innerElseID != nil)
    }

    private struct TestFailure: Error {
        let message: String
        init(_ message: String) { self.message = message }
    }
}
