@testable import CompilerCore
import XCTest

final class ASTContextFunctionTypeTests: XCTestCase {
    private func buildAST(from source: String) throws -> ASTModule {
        let ctx = makeContextFromSource(source)
        try runFrontend(ctx)
        return try XCTUnwrap(ctx.ast)
    }

    func testBuildASTParsesContextFunctionTypeAlias() throws {
        let source = """
        package demo
        typealias Handler = context(A) (B) -> C
        """
        let ast = try buildAST(from: source)
        let typeAliasDecl = try XCTUnwrap(ast.arena.declarations().compactMap { decl -> TypeAliasDecl? in
            guard case let .typeAliasDecl(typeAliasDecl) = decl else { return nil }
            return typeAliasDecl
        }.first)
        let underlyingType = try XCTUnwrap(typeAliasDecl.underlyingType)

        guard case let .functionType(contextReceivers, receiver, params, returnType, isSuspend, nullable) = ast.arena.typeRef(underlyingType) else {
            return XCTFail("Expected function type")
        }

        XCTAssertEqual(contextReceivers.count, 1)
        XCTAssertNil(receiver)
        XCTAssertEqual(params.count, 1)
        XCTAssertFalse(isSuspend)
        XCTAssertFalse(nullable)
        XCTAssertEqual(renderTypeRef(ast.arena.typeRef(contextReceivers[0]), in: ast), "A")
        XCTAssertEqual(renderTypeRef(ast.arena.typeRef(params[0]), in: ast), "B")
        XCTAssertEqual(renderTypeRef(ast.arena.typeRef(returnType), in: ast), "C")
    }

    func testBuildASTParsesSuspendContextFunctionTypeAlias() throws {
        let source = """
        package demo
        typealias Handler = context(A, B) suspend (C, D) -> E
        """
        let ast = try buildAST(from: source)
        let typeAliasDecl = try XCTUnwrap(ast.arena.declarations().compactMap { decl -> TypeAliasDecl? in
            guard case let .typeAliasDecl(typeAliasDecl) = decl else { return nil }
            return typeAliasDecl
        }.first)
        let underlyingType = try XCTUnwrap(typeAliasDecl.underlyingType)

        guard case let .functionType(contextReceivers, receiver, params, returnType, isSuspend, nullable) = ast.arena.typeRef(underlyingType) else {
            return XCTFail("Expected function type")
        }

        XCTAssertEqual(contextReceivers.map { renderTypeRef(ast.arena.typeRef($0), in: ast) }, ["A", "B"])
        XCTAssertNil(receiver)
        XCTAssertEqual(params.map { renderTypeRef(ast.arena.typeRef($0), in: ast) }, ["C", "D"])
        XCTAssertEqual(renderTypeRef(ast.arena.typeRef(returnType), in: ast), "E")
        XCTAssertTrue(isSuspend)
        XCTAssertFalse(nullable)
    }

    func testBuildASTParsesContextReceiverFunctionTypeAlias() throws {
        let source = """
        package demo
        typealias Handler = context(A) Receiver.() -> R
        """
        let ast = try buildAST(from: source)
        let typeAliasDecl = try XCTUnwrap(ast.arena.declarations().compactMap { decl -> TypeAliasDecl? in
            guard case let .typeAliasDecl(typeAliasDecl) = decl else { return nil }
            return typeAliasDecl
        }.first)
        let underlyingType = try XCTUnwrap(typeAliasDecl.underlyingType)

        guard case let .functionType(contextReceivers, receiver, params, returnType, isSuspend, nullable) = ast.arena.typeRef(underlyingType) else {
            return XCTFail("Expected function type")
        }

        XCTAssertEqual(contextReceivers.count, 1)
        XCTAssertEqual(renderTypeRef(ast.arena.typeRef(contextReceivers[0]), in: ast), "A")
        XCTAssertEqual(renderTypeRef(ast.arena.typeRef(try XCTUnwrap(receiver)), in: ast), "Receiver")
        XCTAssertTrue(params.isEmpty)
        XCTAssertEqual(renderTypeRef(ast.arena.typeRef(returnType), in: ast), "R")
        XCTAssertFalse(isSuspend)
        XCTAssertFalse(nullable)
    }

    func testBuildASTParsesNestedGenericContextFunctionTypeAlias() throws {
        let source = """
        package demo
        typealias Handler = context(A<B>) (C<D>) -> E
        """
        let ast = try buildAST(from: source)
        let typeAliasDecl = try XCTUnwrap(ast.arena.declarations().compactMap { decl -> TypeAliasDecl? in
            guard case let .typeAliasDecl(typeAliasDecl) = decl else { return nil }
            return typeAliasDecl
        }.first)
        let underlyingType = try XCTUnwrap(typeAliasDecl.underlyingType)

        guard case let .functionType(contextReceivers, _, params, returnType, _, _) = ast.arena.typeRef(underlyingType) else {
            return XCTFail("Expected function type")
        }

        XCTAssertEqual(renderTypeRef(ast.arena.typeRef(contextReceivers[0]), in: ast), "A<B>")
        XCTAssertEqual(renderTypeRef(ast.arena.typeRef(params[0]), in: ast), "C<D>")
        XCTAssertEqual(renderTypeRef(ast.arena.typeRef(returnType), in: ast), "E")
    }

    private func renderTypeRef(_ typeRef: TypeRef, in ast: ASTModule) -> String {
        switch typeRef {
        case let .named(path, args, nullable):
            let base = path.map(ast.interner.resolve).joined(separator: ".")
            let renderedArgs = if args.isEmpty {
                ""
            } else {
                "<" + args.map { renderTypeArgRef($0, in: ast) }.joined(separator: ", ") + ">"
            }
            return base + renderedArgs + (nullable ? "?" : "")
        case let .functionType(contextReceivers, receiver, params, returnType, isSuspend, nullable):
            let contextPrefix = if contextReceivers.isEmpty {
                ""
            } else {
                "context(" + contextReceivers.map { renderTypeRef(ast.arena.typeRef($0), in: ast) }.joined(separator: ", ") + ") "
            }
            let suspendPrefix = isSuspend ? "suspend " : ""
            let receiverPrefix = receiver.map { renderTypeRef(ast.arena.typeRef($0), in: ast) + "." } ?? ""
            let paramsPart = params.map { renderTypeRef(ast.arena.typeRef($0), in: ast) }.joined(separator: ", ")
            let rendered = contextPrefix + suspendPrefix + receiverPrefix + "(\(paramsPart)) -> " + renderTypeRef(ast.arena.typeRef(returnType), in: ast)
            return rendered + (nullable ? "?" : "")
        }
    }

    private func renderTypeArgRef(_ typeArgRef: TypeArgRef, in ast: ASTModule) -> String {
        switch typeArgRef {
        case let .invariant(typeRefID):
            renderTypeRef(ast.arena.typeRef(typeRefID), in: ast)
        case let .out(typeRefID):
            "out " + renderTypeRef(ast.arena.typeRef(typeRefID), in: ast)
        case let .in(typeRefID):
            "in " + renderTypeRef(ast.arena.typeRef(typeRefID), in: ast)
        case .star:
            "*"
        }
    }
}
