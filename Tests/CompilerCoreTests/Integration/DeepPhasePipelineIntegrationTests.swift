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

        let file = FileID(rawValue: 0)
        let cst = SyntaxArena()
        var tokens: [Token] = []
        var offset = 0

        func token(_ kind: TokenKind) -> TokenID {
            let range = makeRange(file: file, start: offset, end: offset + 1)
            offset += 1
            let tok = Token(kind: kind, range: range)
            tokens.append(tok)
            return cst.appendToken(tok)
        }

        func node(_ kind: SyntaxKind, _ children: [SyntaxChild]) -> NodeID {
            cst.appendNode(kind: kind, range: makeRange(file: file, start: 0, end: max(offset, 1)), children)
        }

        let packageNode = node(.packageHeader, [
            .token(token(.keyword(.package))),
            .token(token(.identifier(interner.intern("demo")))),
            .token(token(.symbol(.dot))),
            .token(token(.identifier(interner.intern("synthetic")))),
        ])

        let importNode = node(.importHeader, [
            .token(token(.keyword(.import))),
            .token(token(.identifier(interner.intern("demo")))),
            .token(token(.symbol(.dot))),
            .token(token(.identifier(interner.intern("synthetic")))),
            .token(token(.symbol(.dot))),
            .token(token(.symbol(.star))),
        ])

        let typeArgsNode = node(.typeArgs, [
            .token(token(.symbol(.lessThan))),
            .token(token(.identifier(interner.intern("T")))),
            .token(token(.symbol(.comma))),
            .token(token(.softKeyword(.out))),
            .token(token(.identifier(interner.intern("R")))),
            .token(token(.symbol(.greaterThan))),
        ])

        let funExprNode = node(.funDecl, [
            .token(token(.keyword(.public))),
            .token(token(.keyword(.private))),
            .token(token(.keyword(.internal))),
            .token(token(.keyword(.protected))),
            .token(token(.keyword(.final))),
            .token(token(.keyword(.open))),
            .token(token(.keyword(.abstract))),
            .token(token(.keyword(.sealed))),
            .token(token(.keyword(.data))),
            .token(token(.keyword(.annotation))),
            .token(token(.keyword(.inline))),
            .token(token(.keyword(.suspend))),
            .token(token(.keyword(.tailrec))),
            .token(token(.keyword(.operator))),
            .token(token(.keyword(.infix))),
            .token(token(.keyword(.crossinline))),
            .token(token(.keyword(.noinline))),
            .token(token(.keyword(.vararg))),
            .token(token(.keyword(.external))),
            .token(token(.keyword(.expect))),
            .token(token(.keyword(.actual))),
            .token(token(.keyword(.value))),
            .token(token(.keyword(.fun))),
            .node(typeArgsNode),
            .token(token(.identifier(interner.intern("compute")))),
            .token(token(.symbol(.lParen))),
            .token(token(.keyword(.vararg))),
            .token(token(.identifier(interner.intern("items")))),
            .token(token(.symbol(.colon))),
            .token(token(.identifier(interner.intern("List")))),
            .token(token(.symbol(.lessThan))),
            .token(token(.identifier(interner.intern("String")))),
            .token(token(.symbol(.greaterThan))),
            .token(token(.symbol(.assign))),
            .token(token(.identifier(interner.intern("fallback")))),
            .token(token(.symbol(.comma))),
            .token(token(.keyword(.noinline))),
            .token(token(.identifier(interner.intern("fallback")))),
            .token(token(.symbol(.colon))),
            .token(token(.identifier(interner.intern("Int")))),
            .token(token(.symbol(.comma))),
            .token(token(.keyword(.crossinline))),
            .token(token(.identifier(interner.intern("mapper")))),
            .token(token(.symbol(.colon))),
            .token(token(.identifier(interner.intern("T")))),
            .token(token(.symbol(.rParen))),
            .token(token(.symbol(.colon))),
            .token(token(.identifier(interner.intern("Map")))),
            .token(token(.symbol(.lessThan))),
            .token(token(.identifier(interner.intern("String")))),
            .token(token(.symbol(.comma))),
            .token(token(.identifier(interner.intern("Int")))),
            .token(token(.symbol(.greaterThan))),
            .token(token(.symbol(.question))),
            .token(token(.softKeyword(.where))),
            .token(token(.identifier(interner.intern("T")))),
            .token(token(.symbol(.colon))),
            .token(token(.identifier(interner.intern("Any")))),
            .token(token(.symbol(.assign))),
            .token(token(.identifier(interner.intern("fallback")))),
        ])

        let stmtBool = node(.statement, [
            .token(token(.keyword(.true))),
        ])
        let stmtBinary = node(.statement, [
            .token(token(.intLiteral("1"))),
            .token(token(.symbol(.plus))),
            .token(token(.intLiteral("2"))),
        ])
        let stringSegment = interner.intern("txt")
        let stmtString = node(.statement, [
            .token(token(.stringQuote)),
            .token(token(.stringSegment(stringSegment))),
            .token(token(.stringQuote)),
        ])
        let stmtCall = node(.statement, [
            .token(token(.identifier(interner.intern("compute")))),
            .token(token(.symbol(.lParen))),
            .token(token(.intLiteral("3"))),
            .token(token(.symbol(.comma))),
            .token(token(.intLiteral("4"))),
            .token(token(.symbol(.rParen))),
        ])
        let stmtWhen = node(.statement, [
            .token(token(.keyword(.when))),
            .token(token(.symbol(.lParen))),
            .token(token(.keyword(.true))),
            .token(token(.symbol(.rParen))),
            .token(token(.symbol(.lBrace))),
            .token(token(.keyword(.true))),
            .token(token(.symbol(.arrow))),
            .token(token(.intLiteral("1"))),
            .token(token(.symbol(.comma))),
            .token(token(.keyword(.false))),
            .token(token(.symbol(.arrow))),
            .token(token(.intLiteral("0"))),
            .token(token(.symbol(.comma))),
            .token(token(.keyword(.else))),
            .token(token(.symbol(.arrow))),
            .token(token(.intLiteral("2"))),
            .token(token(.symbol(.rBrace))),
        ])

        let blockNode = node(.block, [
            .token(token(.symbol(.lBrace))),
            .node(stmtBool),
            .node(stmtBinary),
            .node(stmtString),
            .node(stmtCall),
            .node(stmtWhen),
            .token(token(.symbol(.rBrace))),
        ])

        let funBlockNode = node(.funDecl, [
            .token(token(.keyword(.fun))),
            .token(token(.identifier(interner.intern("blocky")))),
            .token(token(.symbol(.lParen))),
            .token(token(.symbol(.rParen))),
            .node(blockNode),
        ])

        let propertyTypedNode = node(.propertyDecl, [
            .token(token(.keyword(.val))),
            .token(token(.identifier(interner.intern("typed")))),
            .token(token(.symbol(.colon))),
            .token(token(.identifier(interner.intern("String")))),
            .token(token(.symbol(.question))),
            .token(token(.symbol(.assign))),
            .token(token(.stringQuote)),
            .token(token(.stringSegment(interner.intern("hello")))),
            .token(token(.stringQuote)),
        ])

        let propertyDelegatedNode = node(.propertyDecl, [
            .token(token(.keyword(.var))),
            .token(token(.identifier(interner.intern("delegated")))),
            .token(token(.softKeyword(.by))),
            .token(token(.identifier(interner.intern("provider")))),
        ])

        let classNode = node(.classDecl, [
            .token(token(.keyword(.class))),
            .token(token(.identifier(interner.intern("C")))),
        ])

        let objectNode = node(.objectDecl, [
            .token(token(.keyword(.object))),
            .token(token(.identifier(interner.intern("O")))),
        ])

        let typeAliasNode = node(.typeAliasDecl, [
            .token(token(.keyword(.typealias))),
            .token(token(.identifier(interner.intern("Alias")))),
            .token(token(.symbol(.assign))),
            .token(token(.identifier(interner.intern("Int")))),
        ])

        let enumEntryNode = node(.enumEntry, [
            .token(token(.identifier(interner.intern("Entry")))),
        ])

        let root = node(.kotlinFile, [
            .node(packageNode),
            .node(importNode),
            .node(classNode),
            .node(objectNode),
            .node(typeAliasNode),
            .node(enumEntryNode),
            .node(propertyTypedNode),
            .node(propertyDelegatedNode),
            .node(funExprNode),
            .node(funBlockNode),
        ])

        return SyntheticCSTFixture(ctx: ctx, tokens: tokens, cst: cst, root: root)
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
