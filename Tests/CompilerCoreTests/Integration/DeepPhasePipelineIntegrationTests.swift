@testable import CompilerCore
import Foundation
import XCTest

final class DeepPhasePipelineIntegrationTests: XCTestCase {
    private struct SyntheticCSTFixture {
        let ctx: CompilationContext
        let tokens: [Token]
        let cst: SyntaxArena
        let root: NodeID
    }

    private struct CSTBuilder {
        let interner: StringInterner
        let file: FileID
        let cst: SyntaxArena
        var tokens: [Token] = []
        private var offset = 0

        init(interner: StringInterner) {
            self.interner = interner
            file = FileID(rawValue: 0)
            cst = SyntaxArena()
        }

        mutating func tok(_ kind: TokenKind) -> TokenID {
            let range = makeRange(file: file, start: offset, end: offset + 1)
            offset += 1
            let token = Token(kind: kind, range: range)
            tokens.append(token)
            return cst.appendToken(token)
        }

        mutating func node(_ kind: SyntaxKind, _ children: [SyntaxChild]) -> NodeID {
            cst.appendNode(kind: kind, range: makeRange(file: file, start: 0, end: max(offset, 1)), children)
        }

        mutating func makePackageAndImport() -> (NodeID, NodeID) {
            let packageNode = node(.packageHeader, [
                .token(tok(.keyword(.package))),
                .token(tok(.identifier(interner.intern("demo")))),
                .token(tok(.symbol(.dot))),
                .token(tok(.identifier(interner.intern("synthetic")))),
            ])
            let importNode = node(.importHeader, [
                .token(tok(.keyword(.import))),
                .token(tok(.identifier(interner.intern("demo")))),
                .token(tok(.symbol(.dot))),
                .token(tok(.identifier(interner.intern("synthetic")))),
                .token(tok(.symbol(.dot))),
                .token(tok(.symbol(.star))),
            ])
            return (packageNode, importNode)
        }

        mutating func makeFunExprNode() -> NodeID {
            let typeArgsNode = node(.typeArgs, [
                .token(tok(.symbol(.lessThan))),
                .token(tok(.identifier(interner.intern("T")))),
                .token(tok(.symbol(.comma))),
                .token(tok(.softKeyword(.out))),
                .token(tok(.identifier(interner.intern("R")))),
                .token(tok(.symbol(.greaterThan))),
            ])
            return node(.funDecl, [
                .token(tok(.keyword(.public))),
                .token(tok(.keyword(.private))),
                .token(tok(.keyword(.internal))),
                .token(tok(.keyword(.protected))),
                .token(tok(.keyword(.final))),
                .token(tok(.keyword(.open))),
                .token(tok(.keyword(.abstract))),
                .token(tok(.keyword(.sealed))),
                .token(tok(.keyword(.data))),
                .token(tok(.keyword(.annotation))),
                .token(tok(.keyword(.inline))),
                .token(tok(.keyword(.suspend))),
                .token(tok(.keyword(.tailrec))),
                .token(tok(.keyword(.operator))),
                .token(tok(.keyword(.infix))),
                .token(tok(.keyword(.crossinline))),
                .token(tok(.keyword(.noinline))),
                .token(tok(.keyword(.vararg))),
                .token(tok(.keyword(.external))),
                .token(tok(.keyword(.expect))),
                .token(tok(.keyword(.actual))),
                .token(tok(.keyword(.value))),
                .token(tok(.keyword(.fun))),
                .node(typeArgsNode),
                .token(tok(.identifier(interner.intern("compute")))),
                .token(tok(.symbol(.lParen))),
                .token(tok(.keyword(.vararg))),
                .token(tok(.identifier(interner.intern("items")))),
                .token(tok(.symbol(.colon))),
                .token(tok(.identifier(interner.intern("List")))),
                .token(tok(.symbol(.lessThan))),
                .token(tok(.identifier(interner.intern("String")))),
                .token(tok(.symbol(.greaterThan))),
                .token(tok(.symbol(.assign))),
                .token(tok(.identifier(interner.intern("fallback")))),
                .token(tok(.symbol(.comma))),
                .token(tok(.keyword(.noinline))),
                .token(tok(.identifier(interner.intern("fallback")))),
                .token(tok(.symbol(.colon))),
                .token(tok(.identifier(interner.intern("Int")))),
                .token(tok(.symbol(.comma))),
                .token(tok(.keyword(.crossinline))),
                .token(tok(.identifier(interner.intern("mapper")))),
                .token(tok(.symbol(.colon))),
                .token(tok(.identifier(interner.intern("T")))),
                .token(tok(.symbol(.rParen))),
                .token(tok(.symbol(.colon))),
                .token(tok(.identifier(interner.intern("Map")))),
                .token(tok(.symbol(.lessThan))),
                .token(tok(.identifier(interner.intern("String")))),
                .token(tok(.symbol(.comma))),
                .token(tok(.identifier(interner.intern("Int")))),
                .token(tok(.symbol(.greaterThan))),
                .token(tok(.symbol(.question))),
                .token(tok(.softKeyword(.where))),
                .token(tok(.identifier(interner.intern("T")))),
                .token(tok(.symbol(.colon))),
                .token(tok(.identifier(interner.intern("Any")))),
                .token(tok(.symbol(.assign))),
                .token(tok(.identifier(interner.intern("fallback")))),
            ])
        }

        mutating func makeFunBlockNode() -> NodeID {
            let stmtBool = node(.statement, [.token(tok(.keyword(.true)))])
            let stmtBinary = node(.statement, [
                .token(tok(.intLiteral("1"))),
                .token(tok(.symbol(.plus))),
                .token(tok(.intLiteral("2"))),
            ])
            let stringSegment = interner.intern("txt")
            let stmtString = node(.statement, [
                .token(tok(.stringQuote)),
                .token(tok(.stringSegment(stringSegment))),
                .token(tok(.stringQuote)),
            ])
            let stmtCall = node(.statement, [
                .token(tok(.identifier(interner.intern("compute")))),
                .token(tok(.symbol(.lParen))),
                .token(tok(.intLiteral("3"))),
                .token(tok(.symbol(.comma))),
                .token(tok(.intLiteral("4"))),
                .token(tok(.symbol(.rParen))),
            ])
            let stmtWhen = node(.statement, [
                .token(tok(.keyword(.when))),
                .token(tok(.symbol(.lParen))),
                .token(tok(.keyword(.true))),
                .token(tok(.symbol(.rParen))),
                .token(tok(.symbol(.lBrace))),
                .token(tok(.keyword(.true))),
                .token(tok(.symbol(.arrow))),
                .token(tok(.intLiteral("1"))),
                .token(tok(.symbol(.comma))),
                .token(tok(.keyword(.false))),
                .token(tok(.symbol(.arrow))),
                .token(tok(.intLiteral("0"))),
                .token(tok(.symbol(.comma))),
                .token(tok(.keyword(.else))),
                .token(tok(.symbol(.arrow))),
                .token(tok(.intLiteral("2"))),
                .token(tok(.symbol(.rBrace))),
            ])
            let blockNode = node(.block, [
                .token(tok(.symbol(.lBrace))),
                .node(stmtBool),
                .node(stmtBinary),
                .node(stmtString),
                .node(stmtCall),
                .node(stmtWhen),
                .token(tok(.symbol(.rBrace))),
            ])
            return node(.funDecl, [
                .token(tok(.keyword(.fun))),
                .token(tok(.identifier(interner.intern("blocky")))),
                .token(tok(.symbol(.lParen))),
                .token(tok(.symbol(.rParen))),
                .node(blockNode),
            ])
        }

        mutating func makeNominalAndPropertyNodes() -> (
            propertyTyped: NodeID,
            propertyDelegated: NodeID,
            classNode: NodeID,
            objectNode: NodeID,
            typeAliasNode: NodeID,
            enumEntry: NodeID
        ) {
            let propertyTyped = node(.propertyDecl, [
                .token(tok(.keyword(.val))),
                .token(tok(.identifier(interner.intern("typed")))),
                .token(tok(.symbol(.colon))),
                .token(tok(.identifier(interner.intern("String")))),
                .token(tok(.symbol(.question))),
                .token(tok(.symbol(.assign))),
                .token(tok(.stringQuote)),
                .token(tok(.stringSegment(interner.intern("hello")))),
                .token(tok(.stringQuote)),
            ])
            let propertyDelegated = node(.propertyDecl, [
                .token(tok(.keyword(.var))),
                .token(tok(.identifier(interner.intern("delegated")))),
                .token(tok(.softKeyword(.by))),
                .token(tok(.identifier(interner.intern("provider")))),
            ])
            let classNode = node(.classDecl, [
                .token(tok(.keyword(.class))),
                .token(tok(.identifier(interner.intern("C")))),
            ])
            let objectNode = node(.objectDecl, [
                .token(tok(.keyword(.object))),
                .token(tok(.identifier(interner.intern("O")))),
            ])
            let typeAliasNode = node(.typeAliasDecl, [
                .token(tok(.keyword(.typealias))),
                .token(tok(.identifier(interner.intern("Alias")))),
                .token(tok(.symbol(.assign))),
                .token(tok(.identifier(interner.intern("Int")))),
            ])
            let enumEntry = node(.enumEntry, [
                .token(tok(.identifier(interner.intern("Entry")))),
            ])
            return (propertyTyped, propertyDelegated, classNode, objectNode, typeAliasNode, enumEntry)
        }
    }

    private func makeSyntheticCSTFixture() -> SyntheticCSTFixture {
        let interner = StringInterner()
        let diagnostics = DiagnosticEngine()
        let options = CompilerOptions(
            moduleName: "Synthetic",
            inputs: [],
            outputPath: FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path,
            emit: .kirDump,
            target: defaultTargetTriple()
        )
        let ctx = CompilationContext(
            options: options,
            sourceManager: SourceManager(),
            diagnostics: diagnostics,
            interner: interner
        )

        var builder = CSTBuilder(interner: interner)
        let (packageNode, importNode) = builder.makePackageAndImport()
        let funExprNode = builder.makeFunExprNode()
        let funBlockNode = builder.makeFunBlockNode()
        let nominals = builder.makeNominalAndPropertyNodes()

        let root = builder.node(.kotlinFile, [
            .node(packageNode),
            .node(importNode),
            .node(nominals.classNode),
            .node(nominals.objectNode),
            .node(nominals.typeAliasNode),
            .node(nominals.enumEntry),
            .node(nominals.propertyTyped),
            .node(nominals.propertyDelegated),
            .node(funExprNode),
            .node(funBlockNode),
        ])

        return SyntheticCSTFixture(ctx: ctx, tokens: builder.tokens, cst: builder.cst, root: root)
    }

    func testSyntheticCSTDrivesFrontendSemaAndKIRPaths() throws {
        let fixture = makeSyntheticCSTFixture()
        let ctx = fixture.ctx
        ctx.tokens = fixture.tokens
        ctx.syntaxTree = fixture.cst
        ctx.syntaxTreeRoot = fixture.root

        try BuildASTPhase().run(ctx)
        let ast = try XCTUnwrap(ctx.ast)
        // CST contains: class, object, typealias, enum entry, 2 properties, 2 functions = 8+ decls
        XCTAssertGreaterThanOrEqual(ast.declarationCount, 8)

        try SemaPhase().run(ctx)
        try BuildKIRPhase().run(ctx)
        try LoweringPhase().run(ctx)

        let module = try XCTUnwrap(ctx.kir)
        // At minimum: compute and blocky functions
        XCTAssertGreaterThanOrEqual(module.functionCount, 2)
        XCTAssertFalse(module.executedLowerings.isEmpty)
    }
}
