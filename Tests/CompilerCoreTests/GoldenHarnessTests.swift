import Foundation
import XCTest
@testable import CompilerCore

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
            try SemaPassesPhase().run(ctx)

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
            .deletingLastPathComponent()
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
            case .node(let childID):
                dumpSyntaxNode(
                    id: childID,
                    syntax: syntax,
                    interner: interner,
                    indent: indent + "  ",
                    lines: &lines
                )
            case .token(let tokenID):
                let tokenIndex = Int(tokenID.rawValue)
                guard tokenIndex >= 0 && tokenIndex < syntax.tokens.count else {
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
        case .identifier(let id):
            return "identifier(\(interner.resolve(id)))"
        case .backtickedIdentifier(let id):
            return "backtickedIdentifier(\(interner.resolve(id)))"
        case .keyword(let keyword):
            return "keyword(\(keyword.rawValue))"
        case .softKeyword(let keyword):
            return "softKeyword(\(keyword.rawValue))"
        case .intLiteral(let text):
            return "intLiteral(\(text))"
        case .longLiteral(let text):
            return "longLiteral(\(text))"
        case .floatLiteral(let text):
            return "floatLiteral(\(text))"
        case .doubleLiteral(let text):
            return "doubleLiteral(\(text))"
        case .charLiteral(let value):
            return "charLiteral(\(value))"
        case .stringSegment(let id):
            return "stringSegment(\(interner.resolve(id)))"
        case .stringQuote:
            return "stringQuote"
        case .rawStringQuote:
            return "rawStringQuote"
        case .templateExprStart:
            return "templateExprStart"
        case .templateExprEnd:
            return "templateExprEnd"
        case .templateSimpleNameStart:
            return "templateSimpleNameStart"
        case .symbol(let symbol):
            return "symbol(\(symbol.rawValue))"
        case .eof:
            return "eof"
        case .missing(let expected):
            return "missing(\(renderTokenKind(expected, interner: interner)))"
        }
    }

    private func renderRange(_ range: SourceRange) -> String {
        "f\(range.start.file.rawValue):\(range.start.offset)..\(range.end.offset)"
    }

    private func renderDecl(_ decl: Decl, interner: StringInterner) -> String {
        switch decl {
        case .classDecl(let classDecl):
            return "class \(interner.resolve(classDecl.name))"
        case .interfaceDecl(let interfaceDecl):
            return "interface \(interner.resolve(interfaceDecl.name))"
        case .funDecl(let funDecl):
            return "fun \(interner.resolve(funDecl.name)) suspend=\(funDecl.isSuspend ? 1 : 0) inline=\(funDecl.isInline ? 1 : 0)"
        case .propertyDecl(let propertyDecl):
            return "property \(interner.resolve(propertyDecl.name)) var=\(propertyDecl.isVar ? 1 : 0)"
        case .typeAliasDecl(let typeAliasDecl):
            return "typealias \(interner.resolve(typeAliasDecl.name))"
        case .objectDecl(let objectDecl):
            return "object \(interner.resolve(objectDecl.name))"
        case .enumEntryDecl(let enumEntryDecl):
            return "enumEntry \(interner.resolve(enumEntryDecl.name))"
        }
    }

    private func renderDeclSymbol(_ declID: DeclID, sema: SemaModule) -> String {
        if let symbol = sema.bindings.declSymbols[declID] {
            return "s\(symbol.rawValue)"
        }
        return "_"
    }

    private func renderExpr(_ expr: Expr, interner: StringInterner) -> String {
        switch expr {
        case .intLiteral(let value, _):
            return "int(\(value))"
        case .boolLiteral(let value, _):
            return "bool(\(value ? "true" : "false"))"
        case .stringLiteral(let text, _):
            return "string(\(interner.resolve(text)))"
        case .nameRef(let name, _):
            return "name(\(interner.resolve(name)))"
        case .forExpr(let loopVariable, let iterable, let body, _):
            let variable = loopVariable.map { interner.resolve($0) } ?? "_"
            return "for var=\(variable) iterable=e\(iterable.rawValue) body=e\(body.rawValue)"
        case .whileExpr(let condition, let body, _):
            return "while cond=e\(condition.rawValue) body=e\(body.rawValue)"
        case .doWhileExpr(let body, let condition, _):
            return "doWhile body=e\(body.rawValue) cond=e\(condition.rawValue)"
        case .breakExpr:
            return "break"
        case .continueExpr:
            return "continue"
        case .localDecl(let name, let isMutable, let initializer, _):
            return "localDecl \(interner.resolve(name)) mutable=\(isMutable ? 1 : 0) init=e\(initializer.rawValue)"
        case .localAssign(let name, let value, _):
            return "localAssign \(interner.resolve(name)) value=e\(value.rawValue)"
        case .arrayAssign(let array, let index, let value, _):
            return "arrayAssign array=e\(array.rawValue) index=e\(index.rawValue) value=e\(value.rawValue)"
        case .call(let callee, let args, _):
            let renderedArgs = args.map { arg in
                let label = arg.label.map { interner.resolve($0) } ?? "_"
                return "\(label):e\(arg.expr.rawValue)"
            }.joined(separator: ",")
            return "call callee=e\(callee.rawValue) args=[\(renderedArgs)]"
        case .memberCall(let receiver, let callee, let args, _):
            let renderedArgs = args.map { arg in
                let label = arg.label.map { interner.resolve($0) } ?? "_"
                return "\(label):e\(arg.expr.rawValue)"
            }.joined(separator: ",")
            return "memberCall recv=e\(receiver.rawValue) callee=\(interner.resolve(callee)) args=[\(renderedArgs)]"
        case .arrayAccess(let array, let index, _):
            return "arrayAccess array=e\(array.rawValue) index=e\(index.rawValue)"
        case .binary(let op, let lhs, let rhs, _):
            return "binary(\(op)) lhs=e\(lhs.rawValue) rhs=e\(rhs.rawValue)"
        case .whenExpr(let subject, let branches, let elseExpr, _):
            let renderedBranches = branches.map { branch in
                let condition = branch.condition.map { "e\($0.rawValue)" } ?? "else"
                return "\(condition)->e\(branch.body.rawValue)"
            }.joined(separator: ",")
            let renderedElse = elseExpr.map { "e\($0.rawValue)" } ?? "_"
            return "when subject=e\(subject.rawValue) branches=[\(renderedBranches)] else=\(renderedElse)"
        case .returnExpr(let value, _):
            let renderedValue = value.map { "e\($0.rawValue)" } ?? "_"
            return "return value=\(renderedValue)"
        case .ifExpr(let condition, let thenExpr, let elseExpr, _):
            let renderedElse = elseExpr.map { "e\($0.rawValue)" } ?? "_"
            return "if cond=e\(condition.rawValue) then=e\(thenExpr.rawValue) else=\(renderedElse)"
        case .tryExpr(let body, let catchClauses, let finallyExpr, _):
            let catches = catchClauses.map { "e\($0.body.rawValue)" }.joined(separator: ",")
            let renderedFinally = finallyExpr.map { "e\($0.rawValue)" } ?? "_"
            return "try body=e\(body.rawValue) catches=[\(catches)] finally=\(renderedFinally)"
        case .unaryExpr(let op, let operand, _):
            return "unary(\(op)) operand=e\(operand.rawValue)"
        case .isCheck(let expr, let type, let negated, _):
            return "isCheck\(negated ? "!" : "") expr=e\(expr.rawValue) type=t\(type.rawValue)"
        case .asCast(let expr, let type, let isSafe, _):
            return "asCast\(isSafe ? "?" : "") expr=e\(expr.rawValue) type=t\(type.rawValue)"
        case .nullAssert(let expr, _):
            return "nullAssert expr=e\(expr.rawValue)"
        case .safeMemberCall(let receiver, let callee, let args, _):
            let renderedArgs = args.map { arg in
                let label = arg.label.map { interner.resolve($0) } ?? "_"
                return "\(label):e\(arg.expr.rawValue)"
            }.joined(separator: ",")
            return "safeMemberCall recv=e\(receiver.rawValue) callee=\(interner.resolve(callee)) args=[\(renderedArgs)]"
        case .compoundAssign(let op, let name, let value, _):
            return "compoundAssign(\(op)) name=\(interner.resolve(name)) value=e\(value.rawValue)"
        case .throwExpr(let value, _):
            return "throw value=e\(value.rawValue)"
        }
    }

    private func renderFunctionSignature(_ signature: FunctionSignature, types: TypeSystem) -> String {
        let receiver = signature.receiverType.map { types.renderType($0) } ?? "_"
        let parameters = signature.parameterTypes.map { types.renderType($0) }.joined(separator: ",")
        let returnType = types.renderType(signature.returnType)
        let defaults = signature.valueParameterHasDefaultValues.map { $0 ? "1" : "0" }.joined(separator: ",")
        let vararg = signature.valueParameterIsVararg.map { $0 ? "1" : "0" }.joined(separator: ",")
        return "recv=\(receiver) params=[\(parameters)] ret=\(returnType) suspend=\(signature.isSuspend ? 1 : 0) defaults=[\(defaults)] vararg=[\(vararg)]"
    }

    private func renderSymbolFlags(_ flags: SymbolFlags) -> String {
        if flags.isEmpty {
            return "_"
        }
        var names: [String] = []
        if flags.contains(.suspendFunction) { names.append("suspendFunction") }
        if flags.contains(.inlineFunction) { names.append("inlineFunction") }
        if flags.contains(.mutable) { names.append("mutable") }
        if flags.contains(.synthetic) { names.append("synthetic") }
        if flags.contains(.static) { names.append("static") }
        if flags.contains(.sealedType) { names.append("sealedType") }
        if flags.contains(.dataType) { names.append("dataType") }
        return names.joined(separator: "|")
    }

    private func renderFQName(_ fqName: [InternedString], interner: StringInterner) -> String {
        if fqName.isEmpty {
            return "_"
        }
        return fqName.map { interner.resolve($0) }.joined(separator: ".")
    }
}
