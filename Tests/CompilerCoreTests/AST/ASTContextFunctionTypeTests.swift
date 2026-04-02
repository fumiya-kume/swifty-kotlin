@testable import CompilerCore
import XCTest

final class ASTContextFunctionTypeTests: XCTestCase {
    private func buildAST(from source: String) throws -> (ASTModule, CompilationContext) {
        let ctx = makeContextFromSource(source)
        try runFrontend(ctx)
        return (try XCTUnwrap(ctx.ast), ctx)
    }

    func testBuildASTParsesContextFunctionTypeAlias() throws {
        let source = """
        package demo
        typealias Handler = context(A) (B) -> C
        """
        let (ast, ctx) = try buildAST(from: source)
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
        XCTAssertEqual(renderTypeRef(contextReceivers[0], in: ast, interner: ctx.interner), "A")
        XCTAssertEqual(renderTypeRef(params[0], in: ast, interner: ctx.interner), "B")
        XCTAssertEqual(renderTypeRef(returnType, in: ast, interner: ctx.interner), "C")
    }

    func testBuildASTParsesSuspendContextFunctionTypeAlias() throws {
        let source = """
        package demo
        typealias Handler = context(A, B) suspend (C, D) -> E
        """
        let (ast, ctx) = try buildAST(from: source)
        let typeAliasDecl = try XCTUnwrap(ast.arena.declarations().compactMap { decl -> TypeAliasDecl? in
            guard case let .typeAliasDecl(typeAliasDecl) = decl else { return nil }
            return typeAliasDecl
        }.first)
        let underlyingType = try XCTUnwrap(typeAliasDecl.underlyingType)

        guard case let .functionType(contextReceivers, receiver, params, returnType, isSuspend, nullable) = ast.arena.typeRef(underlyingType) else {
            return XCTFail("Expected function type")
        }

        XCTAssertEqual(contextReceivers.map { renderTypeRef($0, in: ast, interner: ctx.interner) }, ["A", "B"])
        XCTAssertNil(receiver)
        XCTAssertEqual(params.map { renderTypeRef($0, in: ast, interner: ctx.interner) }, ["C", "D"])
        XCTAssertEqual(renderTypeRef(returnType, in: ast, interner: ctx.interner), "E")
        XCTAssertTrue(isSuspend)
        XCTAssertFalse(nullable)
    }

    func testBuildASTParsesContextReceiverFunctionTypeAlias() throws {
        let source = """
        package demo
        typealias Handler = context(A) (Receiver) -> R
        """
        let (ast, ctx) = try buildAST(from: source)
        let typeAliasDecl = try XCTUnwrap(ast.arena.declarations().compactMap { decl -> TypeAliasDecl? in
            guard case let .typeAliasDecl(typeAliasDecl) = decl else { return nil }
            return typeAliasDecl
        }.first)
        let underlyingType = try XCTUnwrap(typeAliasDecl.underlyingType)

        guard case let .functionType(contextReceivers, receiver, params, returnType, isSuspend, nullable) = ast.arena.typeRef(underlyingType) else {
            return XCTFail("Expected function type")
        }

        XCTAssertEqual(contextReceivers.count, 1)
        XCTAssertEqual(renderTypeRef(contextReceivers[0], in: ast, interner: ctx.interner), "A")
        XCTAssertNil(receiver)
        XCTAssertEqual(params.count, 1)
        XCTAssertEqual(renderTypeRef(params[0], in: ast, interner: ctx.interner), "Receiver")
        XCTAssertEqual(renderTypeRef(returnType, in: ast, interner: ctx.interner), "R")
        XCTAssertFalse(isSuspend)
        XCTAssertFalse(nullable)
    }

    func testBuildASTParsesNestedGenericContextFunctionTypeAlias() throws {
        let source = """
        package demo
        typealias Handler = context(A<B>) (C<D>) -> E
        """
        let (ast, ctx) = try buildAST(from: source)
        let typeAliasDecl = try XCTUnwrap(ast.arena.declarations().compactMap { decl -> TypeAliasDecl? in
            guard case let .typeAliasDecl(typeAliasDecl) = decl else { return nil }
            return typeAliasDecl
        }.first)
        let underlyingType = try XCTUnwrap(typeAliasDecl.underlyingType)

        guard case let .functionType(contextReceivers, _, params, returnType, _, _) = ast.arena.typeRef(underlyingType) else {
            return XCTFail("Expected function type")
        }

        XCTAssertEqual(renderTypeRef(contextReceivers[0], in: ast, interner: ctx.interner), "A<B>")
        XCTAssertEqual(renderTypeRef(params[0], in: ast, interner: ctx.interner), "C<D>")
        XCTAssertEqual(renderTypeRef(returnType, in: ast, interner: ctx.interner), "E")
    }

    private func renderTypeRef(_ typeRefID: TypeRefID, in ast: ASTModule, interner: StringInterner) -> String {
        guard let typeRef = ast.arena.typeRef(typeRefID) else {
            return "<invalid>"
        }
        switch typeRef {
        case let .annotated(base, annotations):
            return renderTypeRef(base, in: ast, interner: interner)
        case let .named(path, args, nullable):
            let base = path.map(interner.resolve).joined(separator: ".")
            let renderedArgs = if args.isEmpty {
                ""
            } else {
                "<" + args.map { renderTypeArgRef($0, in: ast, interner: interner) }.joined(separator: ", ") + ">"
            }
            return base + renderedArgs + (nullable ? "?" : "")
        case let .functionType(contextReceivers, receiver, params, returnType, isSuspend, nullable):
            let contextPrefix = if contextReceivers.isEmpty {
                ""
            } else {
                "context(" + contextReceivers.map { renderTypeRef($0, in: ast, interner: interner) }.joined(separator: ", ") + ") "
            }
            let suspendPrefix = isSuspend ? "suspend " : ""
            let receiverPrefix = receiver.map { renderTypeRef($0, in: ast, interner: interner) + "." } ?? ""
            let paramsPart = params.map { renderTypeRef($0, in: ast, interner: interner) }.joined(separator: ", ")
            let rendered = contextPrefix + suspendPrefix + receiverPrefix + "(\(paramsPart)) -> " + renderTypeRef(returnType, in: ast, interner: interner)
            return rendered + (nullable ? "?" : "")
        case let .intersection(parts):
            return parts.map { renderTypeRef($0, in: ast, interner: interner) }.joined(separator: " & ")
        }
    }

    private func renderTypeArgRef(_ typeArgRef: TypeArgRef, in ast: ASTModule, interner: StringInterner) -> String {
        switch typeArgRef {
        case let .invariant(typeRefID):
            renderTypeRef(typeRefID, in: ast, interner: interner)
        case let .out(typeRefID):
            "out " + renderTypeRef(typeRefID, in: ast, interner: interner)
        case let .in(typeRefID):
            "in " + renderTypeRef(typeRefID, in: ast, interner: interner)
        case .star:
            "*"
        }
    }
}
