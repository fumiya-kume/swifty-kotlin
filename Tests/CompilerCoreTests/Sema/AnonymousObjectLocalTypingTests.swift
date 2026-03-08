import CompilerCore
import XCTest

final class AnonymousObjectLocalTypingTests: XCTestCase {
    func testAnonymousObjectBodyProducesLocalNominalTypeAndResolvableProperty() throws {
        let source = """
        fun main() {
            val local = object {
                val value = 7
            }
            println(local.value)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            let mainDecl = try XCTUnwrap(topLevelFunction(named: "main", in: ast, interner: ctx.interner))
            guard case let .block(statements, _) = mainDecl.body else {
                XCTFail("Expected block body for main.")
                return
            }

            let localDeclExprID = try XCTUnwrap(statements.first)
            guard let localDeclExpr = ast.arena.expr(localDeclExprID),
                  case let .localDecl(_, _, _, initializer, _) = localDeclExpr,
                  let initializer
            else {
                XCTFail("Expected local declaration with object literal initializer.")
                return
            }

            guard let objectExpr = ast.arena.expr(initializer),
                  case let .objectLiteral(_, declID, _) = objectExpr,
                  let declID,
                  let decl = ast.arena.decl(declID),
                  case let .objectDecl(objectDecl) = decl
            else {
                XCTFail("Expected object literal to retain a synthetic object declaration.")
                return
            }

            XCTAssertEqual(objectDecl.memberProperties.count, 1)
            let objectSymbol = try XCTUnwrap(sema.bindings.declSymbol(for: declID))
            XCTAssertNotNil(sema.symbols.symbol(objectSymbol))

            let propertyDeclID = try XCTUnwrap(objectDecl.memberProperties.first)
            let propertySymbol = sema.bindings.declSymbol(for: propertyDeclID)
            XCTAssertNotNil(
                propertySymbol,
                "Anonymous object property should be bound. Diagnostics: \(renderDiagnostics(ctx))"
            )

            let objectType = try XCTUnwrap(sema.bindings.exprType(for: initializer))
            guard case .classType = sema.types.kind(of: objectType) else {
                XCTFail("Expected anonymous object initializer to infer a nominal class type.")
                return
            }

            let memberExprID = try XCTUnwrap(
                findMemberCall(named: "value", in: statements, ast: ast, interner: ctx.interner)
            )
            let receiverExprID = try XCTUnwrap(memberCallReceiver(for: memberExprID, ast: ast))
            let receiverType = try XCTUnwrap(
                sema.bindings.exprType(for: receiverExprID),
                "Receiver type should be inferred. Diagnostics: \(renderDiagnostics(ctx))"
            )
            XCTAssertEqual(receiverType, objectType)

            let memberSymbol = sema.bindings.identifierSymbol(for: memberExprID)
            XCTAssertNotNil(
                memberSymbol,
                "Member access should resolve to the anonymous object property. Diagnostics: \(renderDiagnostics(ctx))"
            )
            XCTAssertFalse(ctx.diagnostics.hasError, "Unexpected diagnostics: \(renderDiagnostics(ctx))")
        }
    }

    func testAnonymousObjectCanImplementMultipleInterfacesWithoutClassInheritanceDiagnostic() throws {
        let source = """
        interface First
        interface Second
        fun main() {
            val local = object : First, Second {
                val marker = 1
            }
            println(local)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let sema = try XCTUnwrap(ctx.sema)
            let ast = try XCTUnwrap(ctx.ast)
            guard let declID = firstObjectDeclID(in: ast)
            else {
                XCTFail("Expected object literal declaration.")
                return
            }

            let objectSymbol = try XCTUnwrap(sema.bindings.declSymbol(for: declID))
            let directSupertypes = sema.symbols.directSupertypes(for: objectSymbol)
            let supertypeNames = Set(
                directSupertypes.compactMap { symbolID in
                    sema.symbols.symbol(symbolID)?.fqName.last.map(ctx.interner.resolve)
                }
            )

            XCTAssertEqual(supertypeNames, ["First", "Second"])
            assertNoDiagnostic("KSWIFTK-SEMA-0170", in: ctx)
            XCTAssertFalse(ctx.diagnostics.hasError, "Unexpected diagnostics: \(renderDiagnostics(ctx))")
        }
    }

    private func topLevelFunction(
        named name: String,
        in ast: ASTModule,
        interner: StringInterner
    ) -> FunDecl? {
        for file in ast.files {
            for declID in file.topLevelDecls {
                guard let decl = ast.arena.decl(declID),
                      case let .funDecl(function) = decl
                else {
                    continue
                }
                if interner.resolve(function.name) == name {
                    return function
                }
            }
        }
        return nil
    }

    private func findMemberCall(
        named name: String,
        in exprIDs: [ExprID],
        ast: ASTModule,
        interner: StringInterner
    ) -> ExprID? {
        for exprID in exprIDs {
            if let match = findMemberCall(named: name, exprID: exprID, ast: ast, interner: interner) {
                return match
            }
        }
        return nil
    }

    private func findMemberCall(
        named name: String,
        exprID: ExprID,
        ast: ASTModule,
        interner: StringInterner
    ) -> ExprID? {
        guard let expr = ast.arena.expr(exprID) else {
            return nil
        }
        switch expr {
        case let .memberCall(receiver, callee, _, args, _):
            if args.isEmpty, interner.resolve(callee) == name {
                return exprID
            }
            if let nested = findMemberCall(named: name, exprID: receiver, ast: ast, interner: interner) {
                return nested
            }
            for arg in args {
                if let nested = findMemberCall(named: name, exprID: arg.expr, ast: ast, interner: interner) {
                    return nested
                }
            }
            return nil
        case let .call(callee, _, args, _):
            if let nested = findMemberCall(named: name, exprID: callee, ast: ast, interner: interner) {
                return nested
            }
            for arg in args {
                if let nested = findMemberCall(named: name, exprID: arg.expr, ast: ast, interner: interner) {
                    return nested
                }
            }
            return nil
        case let .blockExpr(statements, trailingExpr, _):
            for statement in statements {
                if let nested = findMemberCall(named: name, exprID: statement, ast: ast, interner: interner) {
                    return nested
                }
            }
            if let trailingExpr,
               let nested = findMemberCall(named: name, exprID: trailingExpr, ast: ast, interner: interner)
            {
                return nested
            }
            return nil
        default:
            return nil
        }
    }

    private func memberCallReceiver(
        for exprID: ExprID,
        ast: ASTModule
    ) -> ExprID? {
        guard let expr = ast.arena.expr(exprID),
              case let .memberCall(receiver, _, _, _, _) = expr
        else {
            return nil
        }
        return receiver
    }

    private func findObjectLiteralInitializer(
        in exprIDs: [ExprID],
        ast: ASTModule
    ) -> (ExprID, DeclID)? {
        for exprID in exprIDs {
            if let match = findObjectLiteralInitializer(in: exprID, ast: ast) {
                return match
            }
        }
        return nil
    }

    private func findObjectLiteralInitializer(
        in exprID: ExprID,
        ast: ASTModule
    ) -> (ExprID, DeclID)? {
        guard let expr = ast.arena.expr(exprID) else {
            return nil
        }
        switch expr {
        case let .localDecl(_, _, _, initializer, _):
            guard let initializer,
                  let objectExpr = ast.arena.expr(initializer),
                  case let .objectLiteral(_, declID, _) = objectExpr,
                  let declID
            else {
                return nil
            }
            return (initializer, declID)
        case let .blockExpr(statements, trailingExpr, _):
            if let match = findObjectLiteralInitializer(in: statements, ast: ast) {
                return match
            }
            if let trailingExpr {
                return findObjectLiteralInitializer(in: trailingExpr, ast: ast)
            }
            return nil
        case let .call(callee, _, args, _):
            if let match = findObjectLiteralInitializer(in: callee, ast: ast) {
                return match
            }
            for arg in args {
                if let match = findObjectLiteralInitializer(in: arg.expr, ast: ast) {
                    return match
                }
            }
            return nil
        case let .memberCall(receiver, _, _, args, _):
            if let match = findObjectLiteralInitializer(in: receiver, ast: ast) {
                return match
            }
            for arg in args {
                if let match = findObjectLiteralInitializer(in: arg.expr, ast: ast) {
                    return match
                }
            }
            return nil
        default:
            return nil
        }
    }

    private func firstObjectDeclID(in ast: ASTModule) -> DeclID? {
        for (index, decl) in ast.arena.declarations().enumerated() {
            guard case .objectDecl = decl else {
                continue
            }
            return DeclID(rawValue: Int32(index))
        }
        return nil
    }

    private func renderDiagnostics(_ ctx: CompilationContext) -> String {
        ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
    }
}
