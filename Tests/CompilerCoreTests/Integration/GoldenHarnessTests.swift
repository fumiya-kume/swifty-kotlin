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

    private func renderExpr(_ expr: Expr, interner: StringInterner) -> String {
        switch expr {
        case let .intLiteral(value, _):
            return "int(\(value))"
        case let .longLiteral(value, _):
            return "long(\(value))"
        case let .floatLiteral(value, _):
            return "float(\(value))"
        case let .doubleLiteral(value, _):
            return "double(\(value))"
        case let .charLiteral(value, _):
            return "char(\(value))"
        case let .boolLiteral(value, _):
            return "bool(\(value ? "true" : "false"))"
        case let .stringLiteral(text, _):
            return "string(\(interner.resolve(text)))"
        case let .nameRef(name, _):
            return "name(\(interner.resolve(name)))"
        case let .forExpr(loopVariable, iterable, body, label, _):
            let variable = loopVariable.map { interner.resolve($0) } ?? "_"
            let labelStr = label.map { " label=\(interner.resolve($0))" } ?? ""
            return "for var=\(variable) iterable=e\(iterable.rawValue) body=e\(body.rawValue)\(labelStr)"
        case let .whileExpr(condition, body, label, _):
            let labelStr = label.map { " label=\(interner.resolve($0))" } ?? ""
            return "while cond=e\(condition.rawValue) body=e\(body.rawValue)\(labelStr)"
        case let .doWhileExpr(body, condition, label, _):
            let labelStr = label.map { " label=\(interner.resolve($0))" } ?? ""
            return "doWhile body=e\(body.rawValue) cond=e\(condition.rawValue)\(labelStr)"
        case let .breakExpr(label, _):
            let labelStr = label.map { "@\(interner.resolve($0))" } ?? ""
            return "break\(labelStr)"
        case let .continueExpr(label, _):
            let labelStr = label.map { "@\(interner.resolve($0))" } ?? ""
            return "continue\(labelStr)"
        case let .localDecl(name, isMutable, typeAnnotation, initializer, _):
            let typeStr = typeAnnotation.map { "t\($0.rawValue)" } ?? "_"
            let initStr = initializer.map { "e\($0.rawValue)" } ?? "_"
            return "localDecl \(interner.resolve(name)) mutable=\(isMutable ? 1 : 0) type=\(typeStr) init=\(initStr)"
        case let .localAssign(name, value, _):
            return "localAssign \(interner.resolve(name)) value=e\(value.rawValue)"
        case let .indexedAssign(receiver, indices, value, _):
            let idxStr = indices.map { "e\($0.rawValue)" }.joined(separator: ",")
            return "indexedAssign receiver=e\(receiver.rawValue) indices=[\(idxStr)] value=e\(value.rawValue)"
        case let .call(callee, _, args, _):
            let renderedArgs = args.map { arg in
                let label = arg.label.map { interner.resolve($0) } ?? "_"
                return "\(label):e\(arg.expr.rawValue)"
            }.joined(separator: ",")
            return "call callee=e\(callee.rawValue) args=[\(renderedArgs)]"
        case let .memberCall(receiver, callee, _, args, _):
            let renderedArgs = args.map { arg in
                let label = arg.label.map { interner.resolve($0) } ?? "_"
                return "\(label):e\(arg.expr.rawValue)"
            }.joined(separator: ",")
            return "memberCall recv=e\(receiver.rawValue) callee=\(interner.resolve(callee)) args=[\(renderedArgs)]"
        case let .indexedAccess(receiver, indices, _):
            let idxStr = indices.map { "e\($0.rawValue)" }.joined(separator: ",")
            return "indexedAccess receiver=e\(receiver.rawValue) indices=[\(idxStr)]"
        case let .binary(op, lhs, rhs, _):
            return "binary(\(op)) lhs=e\(lhs.rawValue) rhs=e\(rhs.rawValue)"
        case let .whenExpr(subject, branches, elseExpr, _):
            let renderedBranches = branches.map { branch in
                let conditions: String = if branch.conditions.isEmpty {
                    "else"
                } else {
                    branch.conditions.map { "e\($0.rawValue)" }.joined(separator: ",")
                }
                return "\(conditions)->e\(branch.body.rawValue)"
            }.joined(separator: ",")
            let renderedElse = elseExpr.map { "e\($0.rawValue)" } ?? "_"
            let renderedSubject = subject.map { "e\($0.rawValue)" } ?? "_"
            return "when subject=\(renderedSubject) branches=[\(renderedBranches)] else=\(renderedElse)"
        case let .returnExpr(value, label, _):
            let renderedValue = value.map { "e\($0.rawValue)" } ?? "_"
            let labelStr = label.map { "@\(interner.resolve($0))" } ?? ""
            return "return\(labelStr) value=\(renderedValue)"
        case let .ifExpr(condition, thenExpr, elseExpr, _):
            let renderedElse = elseExpr.map { "e\($0.rawValue)" } ?? "_"
            return "if cond=e\(condition.rawValue) then=e\(thenExpr.rawValue) else=\(renderedElse)"
        case let .tryExpr(body, catchClauses, finallyExpr, _):
            let catches = catchClauses.map { "e\($0.body.rawValue)" }.joined(separator: ",")
            let renderedFinally = finallyExpr.map { "e\($0.rawValue)" } ?? "_"
            return "try body=e\(body.rawValue) catches=[\(catches)] finally=\(renderedFinally)"
        case let .unaryExpr(op, operand, _):
            return "unary(\(op)) operand=e\(operand.rawValue)"
        case let .isCheck(expr, type, negated, _):
            return "isCheck\(negated ? "!" : "") expr=e\(expr.rawValue) type=t\(type.rawValue)"
        case let .asCast(expr, type, isSafe, _):
            return "asCast\(isSafe ? "?" : "") expr=e\(expr.rawValue) type=t\(type.rawValue)"
        case let .nullAssert(expr, _):
            return "nullAssert expr=e\(expr.rawValue)"
        case let .safeMemberCall(receiver, callee, _, args, _):
            let renderedArgs = args.map { arg in
                let label = arg.label.map { interner.resolve($0) } ?? "_"
                return "\(label):e\(arg.expr.rawValue)"
            }.joined(separator: ",")
            return "safeMemberCall recv=e\(receiver.rawValue) callee=\(interner.resolve(callee)) args=[\(renderedArgs)]"
        case let .compoundAssign(op, name, value, _):
            return "compoundAssign(\(op)) name=\(interner.resolve(name)) value=e\(value.rawValue)"
        case let .indexedCompoundAssign(op, receiver, indices, value, _):
            let idxStr = indices.map { "e\($0.rawValue)" }.joined(separator: ",")
            return "indexedCompoundAssign(\(op)) receiver=e\(receiver.rawValue) indices=[\(idxStr)] value=e\(value.rawValue)"
        case let .stringTemplate(parts, _):
            let rendered = parts.map { part -> String in
                switch part {
                case let .literal(text):
                    return "lit(\(interner.resolve(text)))"
                case let .expression(exprID):
                    return "expr(e\(exprID.rawValue))"
                }
            }.joined(separator: ",")
            return "stringTemplate[\(rendered)]"
        case let .throwExpr(value, _):
            return "throw value=e\(value.rawValue)"
        case let .lambdaLiteral(params, body, label, _):
            let renderedParams = params.map { interner.resolve($0) }.joined(separator: ",")
            let labelStr = label.map { " label=\(interner.resolve($0))" } ?? ""
            return "lambda params=[\(renderedParams)] body=e\(body.rawValue)\(labelStr)"
        case let .objectLiteral(superTypes, _):
            let renderedSuperTypes = superTypes.map { "t\($0.rawValue)" }.joined(separator: ",")
            return "objectLiteral supers=[\(renderedSuperTypes)]"
        case let .callableRef(receiver, member, _):
            let renderedReceiver = receiver.map { "e\($0.rawValue)" } ?? "_"
            return "callableRef recv=\(renderedReceiver) member=\(interner.resolve(member))"
        case let .localFunDecl(name, valueParams, returnType, body, _):
            let params = valueParams.map { interner.resolve($0.name) }.joined(separator: ",")
            let bodyStr = switch body {
            case let .block(exprs, _):
                "block[\(exprs.map { "e\($0.rawValue)" }.joined(separator: ","))]"
            case let .expr(exprID, _):
                "e\(exprID.rawValue)"
            case .unit:
                "unit"
            }
            let retStr = returnType.map { "t\($0.rawValue)" } ?? "nil"
            return "localFunDecl \(interner.resolve(name)) params=[\(params)] returnType=\(retStr) body=\(bodyStr)"
        case let .blockExpr(statements, trailingExpr, _):
            let stmts = statements.map { "e\($0.rawValue)" }.joined(separator: ",")
            let trailing = trailingExpr.map { "e\($0.rawValue)" } ?? "_"
            return "blockExpr stmts=[\(stmts)] trailing=\(trailing)"
        case .superRef:
            return "super"
        case let .thisRef(label, _):
            if let label {
                return "this@\(interner.resolve(label))"
            }
            return "this"
        case let .inExpr(lhs, rhs, _):
            return "inExpr lhs=e\(lhs.rawValue) rhs=e\(rhs.rawValue)"
        case let .notInExpr(lhs, rhs, _):
            return "notInExpr lhs=e\(lhs.rawValue) rhs=e\(rhs.rawValue)"
        case let .destructuringDecl(names, isMutable, initializer, _):
            let renderedNames = names.map { $0.map { interner.resolve($0) } ?? "_" }.joined(separator: ",")
            return "destructuringDecl names=[\(renderedNames)] mutable=\(isMutable ? 1 : 0) init=e\(initializer.rawValue)"
        case let .forDestructuringExpr(names, iterable, body, _):
            let renderedNames = names.map { $0.map { interner.resolve($0) } ?? "_" }.joined(separator: ",")
            return "forDestructuring names=[\(renderedNames)] iterable=e\(iterable.rawValue) body=e\(body.rawValue)"
        case let .memberAssign(receiver, callee, value, _):
            return "memberAssign recv=e\(receiver.rawValue) callee=\(interner.resolve(callee)) value=e\(value.rawValue)"
        }
    }

    private func renderFunctionSignature(_ signature: FunctionSignature, types: TypeSystem) -> String {
        let receiver = signature.receiverType.map { types.renderType($0) } ?? "_"
        let parameters = signature.parameterTypes.map { types.renderType($0) }.joined(separator: ",")
        let returnType = types.renderType(signature.returnType)
        let defaults = signature.valueParameterHasDefaultValues.map { $0 ? "1" : "0" }.joined(separator: ",")
        let vararg = signature.valueParameterIsVararg.map { $0 ? "1" : "0" }.joined(separator: ",")
        var result = "recv=\(receiver) params=[\(parameters)] ret=\(returnType) suspend=\(signature.isSuspend ? 1 : 0) defaults=[\(defaults)] vararg=[\(vararg)]"
        if !signature.typeParameterUpperBounds.isEmpty, signature.typeParameterUpperBounds.contains(where: { $0 != nil }) {
            let bounds = signature.typeParameterUpperBounds.map { bound in
                bound.map { types.renderType($0) } ?? "_"
            }.joined(separator: ",")
            result += " bounds=[\(bounds)]"
        }
        return result
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
        if flags.contains(.innerClass) { names.append("innerClass") }
        if flags.contains(.valueType) { names.append("valueType") }
        if flags.contains(.operatorFunction) { names.append("operatorFunction") }
        if flags.contains(.constValue) { names.append("constValue") }
        if flags.contains(.abstractType) { names.append("abstractType") }
        return names.joined(separator: "|")
    }

    private func renderFQName(_ fqName: [InternedString], interner: StringInterner) -> String {
        if fqName.isEmpty {
            return "_"
        }
        return fqName.map { interner.resolve($0) }.joined(separator: ".")
    }
}
