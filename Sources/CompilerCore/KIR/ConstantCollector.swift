import Foundation

/// Stateless utility struct for collecting property constant initializers.
/// No driver reference needed — all methods are pure functions.
struct ConstantCollector {

    func collectPropertyConstantInitializers(
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner,
        sourceByFileID: [Int32: String]
    ) -> [SymbolID: KIRExprKind] {
        var mapping: [SymbolID: KIRExprKind] = [:]
        for file in ast.sortedFiles {
            let source = sourceByFileID[file.fileID.rawValue] ?? ""
            for declID in file.topLevelDecls {
                collectPropertyConstant(declID, ast: ast, sema: sema, interner: interner, source: source, mapping: &mapping)
            }
        }
        return mapping
    }

    func collectPropertyConstant(
        _ declID: DeclID,
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner,
        source: String,
        mapping: inout [SymbolID: KIRExprKind]
    ) {
        guard let decl = ast.arena.decl(declID) else { return }
        switch decl {
        case .propertyDecl(let property):
            guard let symbol = sema.bindings.declSymbols[declID] else { return }
            // Prioritize const val values stored during sema (compile-time constants)
            if let constKind = sema.symbols.constValueExprKind(for: symbol) {
                mapping[symbol] = constKind
                if let propertySymbol = sema.symbols.symbol(symbol) {
                    let related = sema.symbols.lookupAll(fqName: propertySymbol.fqName)
                    for relatedID in related {
                        guard let relatedSymbol = sema.symbols.symbol(relatedID) else {
                            continue
                        }
                        if relatedSymbol.kind == .property || relatedSymbol.kind == .field {
                            mapping[relatedID] = constKind
                        }
                    }
                }
                return
            }
            let constant =
                literalConstantExpr(property: property, ast: ast) ??
                inlineGetterConstantExpr(
                    propertyName: interner.resolve(property.name),
                    source: source,
                    interner: interner
                )
            guard let constant else { return }
            mapping[symbol] = constant
            if let propertySymbol = sema.symbols.symbol(symbol) {
                let related = sema.symbols.lookupAll(fqName: propertySymbol.fqName)
                for relatedID in related {
                    guard let relatedSymbol = sema.symbols.symbol(relatedID) else {
                        continue
                    }
                    if relatedSymbol.kind == .property || relatedSymbol.kind == .field {
                        mapping[relatedID] = constant
                    }
                }
            }
        case .classDecl(let classDecl):
            for memberDeclID in classDecl.memberProperties {
                collectPropertyConstant(memberDeclID, ast: ast, sema: sema, interner: interner, source: source, mapping: &mapping)
            }
            for nestedDeclID in classDecl.nestedClasses + classDecl.nestedObjects {
                collectPropertyConstant(nestedDeclID, ast: ast, sema: sema, interner: interner, source: source, mapping: &mapping)
            }
        case .objectDecl(let objectDecl):
            for memberDeclID in objectDecl.memberProperties {
                collectPropertyConstant(memberDeclID, ast: ast, sema: sema, interner: interner, source: source, mapping: &mapping)
            }
            for nestedDeclID in objectDecl.nestedClasses + objectDecl.nestedObjects {
                collectPropertyConstant(nestedDeclID, ast: ast, sema: sema, interner: interner, source: source, mapping: &mapping)
            }
        default:
            break
        }
    }

    func inlineGetterConstantExpr(
        propertyName: String,
        source: String,
        interner: StringInterner
    ) -> KIRExprKind? {
        guard !propertyName.isEmpty else {
            return nil
        }
        let escapedPropertyName = NSRegularExpression.escapedPattern(for: propertyName)
        let pattern = #"(?m)^\s*(?:val|var)\s+\#(escapedPropertyName)\b[^\n]*\n\s*get\s*\(\s*\)\s*=\s*([^\n;]+)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(
                in: source,
                range: NSRange(source.startIndex..<source.endIndex, in: source)
              ),
              match.numberOfRanges >= 2,
              let bodyRange = Range(match.range(at: 1), in: source) else {
            return nil
        }
        let rawBody = source[bodyRange].trimmingCharacters(in: .whitespacesAndNewlines)
        if rawBody == "true" {
            return .boolLiteral(true)
        }
        if rawBody == "false" {
            return .boolLiteral(false)
        }
        let normalized = rawBody.replacingOccurrences(of: "_", with: "")
        if let intValue = Int64(normalized) {
            return .intLiteral(intValue)
        }
        if rawBody.hasPrefix("\""), rawBody.hasSuffix("\""), rawBody.count >= 2 {
            let start = rawBody.index(after: rawBody.startIndex)
            let end = rawBody.index(before: rawBody.endIndex)
            return .stringLiteral(interner.intern(String(rawBody[start..<end])))
        }
        return nil
    }

    func literalConstantExpr(property: PropertyDecl, ast: ASTModule) -> KIRExprKind? {
        if let initializer = property.initializer,
           let literal = literalConstantExpr(initializer, ast: ast) {
            return literal
        }
        if let getter = property.getter {
            return literalConstantExpr(getterBody: getter.body, ast: ast)
        }
        return nil
    }

    func literalConstantExpr(getterBody: FunctionBody, ast: ASTModule) -> KIRExprKind? {
        switch getterBody {
        case .expr(let exprID, _):
            return literalConstantExpr(exprID, ast: ast)
        case .block(let exprIDs, _):
            guard let lastExprID = exprIDs.last,
                  let lastExpr = ast.arena.expr(lastExprID) else {
                return nil
            }
            if case .returnExpr(let valueExprID, _) = lastExpr,
               let valueExprID {
                return literalConstantExpr(valueExprID, ast: ast)
            }
            return literalConstantExpr(lastExprID, ast: ast)
        case .unit:
            return nil
        }
    }

    func literalConstantExpr(_ exprID: ExprID, ast: ASTModule) -> KIRExprKind? {
        guard let expr = ast.arena.expr(exprID) else {
            return nil
        }
        switch expr {
        case .intLiteral(let value, _):
            return .intLiteral(value)
        case .longLiteral(let value, _):
            return .longLiteral(value)
        case .floatLiteral(let value, _):
            return .floatLiteral(value)
        case .doubleLiteral(let value, _):
            return .doubleLiteral(value)
        case .charLiteral(let value, _):
            return .charLiteral(value)
        case .boolLiteral(let value, _):
            return .boolLiteral(value)
        case .stringLiteral(let value, _):
            return .stringLiteral(value)
        default:
            return nil
        }
    }
}
