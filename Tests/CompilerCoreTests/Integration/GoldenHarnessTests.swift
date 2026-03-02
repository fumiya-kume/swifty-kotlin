@testable import CompilerCore
import Foundation
import XCTest

final class GoldenHarnessTests: XCTestCase {
    private enum GoldenSuite: String, CaseIterable {
        case lexer = "Lexer"
        case parser = "Parser"
        case sema = "Sema"
    }

    func testLexerGolden() throws {
        try runGoldenSuite(.lexer) { sourcePath in
            let ctx = makeCompilationContext(inputs: [sourcePath], moduleName: "GoldenLexer", emit: .kirDump)
            try LoadSourcesPhase().run(ctx)
            try LexPhase().run(ctx)

            var lines: [String] = []
            for token in ctx.tokens {
                lines.append("\(renderTokenKind(token.kind, interner: ctx.interner)) \(renderRange(token.range))")
            }
            return lines.joined(separator: "\n") + "\n"
        }
    }

    func testParserGolden() throws {
        try runGoldenSuite(.parser) { sourcePath in
            let ctx = makeCompilationContext(inputs: [sourcePath], moduleName: "GoldenParser", emit: .kirDump)
            try LoadSourcesPhase().run(ctx)
            try LexPhase().run(ctx)
            try ParsePhase().run(ctx)

            let syntax = try XCTUnwrap(ctx.syntaxTree)
            var lines: [String] = []
            dumpSyntaxNode(
                id: ctx.syntaxTreeRoot,
                syntax: syntax,
                interner: ctx.interner,
                indent: "",
                lines: &lines
            )
            return lines.joined(separator: "\n") + "\n"
        }
    }

    func testSemaGolden() throws {
        try runGoldenSuite(.sema) { sourcePath in
            let ctx = makeCompilationContext(inputs: [sourcePath], moduleName: "GoldenSema", emit: .kirDump)
            try runFrontend(ctx)
            try SemaPhase().run(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)
            var lines: [String] = []

            let symbols = sema.symbols.allSymbols().sorted { lhs, rhs in
                lhs.id.rawValue < rhs.id.rawValue
            }
            for symbol in symbols {
                var extra: [String] = []
                if let signature = sema.symbols.functionSignature(for: symbol.id) {
                    extra.append("sig=\(renderFunctionSignature(signature, types: sema.types))")
                }
                if let propertyType = sema.symbols.propertyType(for: symbol.id) {
                    extra.append("type=\(sema.types.renderType(propertyType))")
                }
                let extras = extra.isEmpty ? "" : " " + extra.joined(separator: " ")
                lines.append(
                    "symbol s\(symbol.id.rawValue) kind=\(symbol.kind) fq=\(renderFQName(symbol.fqName, interner: ctx.interner)) vis=\(symbol.visibility) flags=\(renderSymbolFlags(symbol.flags))\(extras)"
                )
            }

            for file in ast.sortedFiles {
                lines.append(
                    "file f\(file.fileID.rawValue) package=\(renderFQName(file.packageFQName, interner: ctx.interner))"
                )
                for declID in file.topLevelDecls {
                    guard let decl = ast.arena.decl(declID) else {
                        continue
                    }
                    lines.append(
                        "  decl d\(declID.rawValue) \(renderDecl(decl, interner: ctx.interner)) sym=\(renderDeclSymbol(declID, sema: sema))"
                    )
                }
            }

            for raw in ast.arena.exprs.indices {
                let exprID = ExprID(rawValue: Int32(raw))
                guard let expr = ast.arena.expr(exprID) else {
                    continue
                }
                var line = "expr e\(exprID.rawValue) \(renderExpr(expr, interner: ctx.interner))"
                if let exprType = sema.bindings.exprTypes[exprID] {
                    line += " type=\(sema.types.renderType(exprType))"
                } else {
                    line += " type=_"
                }
                if let refSymbol = sema.bindings.identifierSymbols[exprID] {
                    line += " ref=s\(refSymbol.rawValue)"
                }
                if let callBinding = sema.bindings.callBindings[exprID] {
                    let map = callBinding.parameterMapping.keys.sorted().map { key in
                        "\(key)->\(callBinding.parameterMapping[key] ?? -1)"
                    }.joined(separator: ",")
                    let typeArgs = callBinding.substitutedTypeArguments.map { sema.types.renderType($0) }.joined(separator: ",")
                    line += " call=s\(callBinding.chosenCallee.rawValue) map=[\(map)] targs=[\(typeArgs)]"
                }
                lines.append(line)
            }

            return lines.joined(separator: "\n") + "\n"
        }
    }

    private func runGoldenSuite(_ suite: GoldenSuite, dump: (String) throws -> String) throws {
        let suiteURL = goldenRootURL.appendingPathComponent(suite.rawValue, isDirectory: true)
        let fm = FileManager.default
        guard fm.fileExists(atPath: suiteURL.path) else {
            XCTFail("Golden suite directory does not exist: \(suiteURL.path)")
            return
        }

        let sourceFiles = try fm.contentsOfDirectory(at: suiteURL, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "kt" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        XCTAssertFalse(sourceFiles.isEmpty, "No golden .kt files in \(suiteURL.path)")

        let shouldUpdate = ProcessInfo.processInfo.environment["UPDATE_GOLDEN"] == "1"
        for sourceURL in sourceFiles {
            let goldenURL = sourceURL.deletingPathExtension().appendingPathExtension("golden")
            let actual = try dump(sourceURL.path)

            if shouldUpdate {
                try actual.write(to: goldenURL, atomically: false, encoding: .utf8)
                continue
            }

            guard fm.fileExists(atPath: goldenURL.path) else {
                XCTFail("Missing golden file: \(goldenURL.path). Run with UPDATE_GOLDEN=1.")
                continue
            }
            let expected = try String(contentsOf: goldenURL, encoding: .utf8)
            XCTAssertEqual(actual, expected, "Golden mismatch: \(sourceURL.lastPathComponent)")
        }
    }

    private var goldenRootURL: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Integration/
            .deletingLastPathComponent() // CompilerCoreTests/
            .appendingPathComponent("GoldenCases", isDirectory: true)
    }

    private func dumpSyntaxNode(
        id: NodeID,
        syntax: SyntaxArena,
        interner: StringInterner,
        indent: String,
        lines: inout [String]
    ) {
        let node = syntax.node(id)
        lines.append("\(indent)node \(node.kind) \(renderRange(node.range))")
        for child in syntax.children(of: id) {
            switch child {
            case let .node(childID):
                dumpSyntaxNode(
                    id: childID,
                    syntax: syntax,
                    interner: interner,
                    indent: indent + "  ",
                    lines: &lines
                )
            case let .token(tokenID):
                let tokenIndex = Int(tokenID.rawValue)
                guard tokenIndex >= 0, tokenIndex < syntax.tokens.count else {
                    lines.append("\(indent)  tok <invalid>")
                    continue
                }
                let token = syntax.tokens[tokenIndex]
                lines.append("\(indent)  tok \(renderTokenKind(token.kind, interner: interner)) \(renderRange(token.range))")
            }
        }
    }

    private func renderTokenKind(_ kind: TokenKind, interner: StringInterner) -> String {
        switch kind {
        case let .identifier(id):
            "identifier(\(interner.resolve(id)))"
        case let .backtickedIdentifier(id):
            "backtickedIdentifier(\(interner.resolve(id)))"
        case let .keyword(keyword):
            "keyword(\(keyword.rawValue))"
        case let .softKeyword(keyword):
            "softKeyword(\(keyword.rawValue))"
        case let .intLiteral(text):
            "intLiteral(\(text))"
        case let .longLiteral(text):
            "longLiteral(\(text))"
        case let .floatLiteral(text):
            "floatLiteral(\(text))"
        case let .doubleLiteral(text):
            "doubleLiteral(\(text))"
        case let .charLiteral(value):
            "charLiteral(\(value))"
        case let .stringSegment(id):
            "stringSegment(\(interner.resolve(id)))"
        case .stringQuote:
            "stringQuote"
        case .rawStringQuote:
            "rawStringQuote"
        case .templateExprStart:
            "templateExprStart"
        case .templateExprEnd:
            "templateExprEnd"
        case .templateSimpleNameStart:
            "templateSimpleNameStart"
        case let .symbol(symbol):
            "symbol(\(symbol.rawValue))"
        case .eof:
            "eof"
        case let .missing(expected):
            "missing(\(renderTokenKind(expected, interner: interner)))"
        }
    }

    private func renderRange(_ range: SourceRange) -> String {
        "f\(range.start.file.rawValue):\(range.start.offset)..\(range.end.offset)"
    }

    private func renderDecl(_ decl: Decl, interner: StringInterner) -> String {
        switch decl {
        case let .classDecl(classDecl):
            "class \(interner.resolve(classDecl.name))"
        case let .interfaceDecl(interfaceDecl):
            "interface \(interner.resolve(interfaceDecl.name))"
        case let .funDecl(funDecl):
            "fun \(interner.resolve(funDecl.name)) suspend=\(funDecl.isSuspend ? 1 : 0) inline=\(funDecl.isInline ? 1 : 0)"
        case let .propertyDecl(propertyDecl):
            "property \(interner.resolve(propertyDecl.name)) var=\(propertyDecl.isVar ? 1 : 0)"
        case let .typeAliasDecl(typeAliasDecl):
            "typealias \(interner.resolve(typeAliasDecl.name))"
        case let .objectDecl(objectDecl):
            "object \(interner.resolve(objectDecl.name))"
        case let .enumEntryDecl(enumEntryDecl):
            "enumEntry \(interner.resolve(enumEntryDecl.name))"
        }
    }

    private func renderDeclSymbol(_ declID: DeclID, sema: SemaModule) -> String {
        if let symbol = sema.bindings.declSymbols[declID] {
            return "s\(symbol.rawValue)"
        }
        return "_"
    }

}
