@testable import CompilerCore
import Foundation

final class StableRenderContext {
    let sema: SemaModule
    let interner: StringInterner
    let arena: ASTArena

    private let sourceManager: SourceManager
    private let symbolFQ: [Int32: String]
    /// Maps `SymbolID.rawValue` to a stable key derived from the declaration's
    /// meaning (`<fq>[kind=…;recv=…;params=…]`), not from its position in the
    /// candidate set. Adding or removing *unreferenced* same-FQName symbols
    /// never renumbers existing references.
    private let symbolKeys: [Int32: String]
    /// Maps `ExprID.rawValue` to a stable, source-position-derived key so that
    /// inserting an expression elsewhere in the file does not renumber every
    /// later expression in the golden dump.
    private let exprKeys: [Int32: String]
    /// Maps `FileID.rawValue` to a stable, path-derived key so that inserting
    /// bundled source files before the test input does not renumber the file line.
    private let fileKeys: [Int32: String]
    private(set) var requiredSymbols = Set<Int32>()

    // swiftlint:disable:next force_try
    private static let typeRefRegex = try! NSRegularExpression(pattern: "(Class#|T#)(\\d+)")

    init(sema: SemaModule, interner: StringInterner, ast: ASTModule, sourceManager: SourceManager) {
        self.sema = sema
        self.interner = interner
        self.arena = ast.arena
        self.sourceManager = sourceManager
        self.exprKeys = Self.buildExprKeys(arena: ast.arena, sourceManager: sourceManager)
        self.fileKeys = Self.buildFileKeys(sourceManager: sourceManager)

        var fqMap: [Int32: String] = [:]
        for symbol in sema.symbols.allSymbols() {
            fqMap[symbol.id.rawValue] = GoldenHarnessSemaFormat.renderFQName(symbol.fqName, interner: interner)
        }
        self.symbolFQ = fqMap

        self.symbolKeys = StableSemanticKeyComputer(
            sema: sema,
            interner: interner,
            symbolFQ: fqMap,
            fileKeys: fileKeys,
            sourceManager: sourceManager
        ).computeKeys()
    }

    /// Returns the stable, meaning-derived key for a symbol. The key combines the
    /// rendered FQName with a bracketed descriptor of the declaration itself
    /// (kind, receiver, parameter types, generic arity, and — only when needed —
    /// a declaration-scope discriminator). It never depends on how many other
    /// candidates share the FQName, their registration order, or SymbolIDs.
    func stableKey(for symbolID: SymbolID) -> String {
        symbolKeys[symbolID.rawValue] ?? "_"
    }

    /// Returns the stable, source-position-derived key for an expression.
    func exprKey(_ id: ExprID) -> String {
        exprKeys[id.rawValue] ?? "e?\(id.rawValue)"
    }

    /// Returns the stable, path-derived key for a file.
    func fileKey(_ file: FileID) -> String {
        fileKeys[file.rawValue] ?? "f?\(file.rawValue)"
    }

    /// Renders a syntactic type reference to a stable, arena-ID-free string.
    /// Used for the type positions that have no resolved sema `TypeID` binding
    /// (local declaration annotations, object-literal supertypes, local-function
    /// return types). The output never contains arena ordinals, so it stays
    /// stable across unrelated source edits.
    func renderTypeRef(_ id: TypeRefID) -> String {
        guard let ref = arena.typeRef(id) else { return "?" }
        switch ref {
        case let .named(path, args, nullable):
            let name = path.map { interner.resolve($0) }.joined(separator: ".")
            let argStr = args.isEmpty
                ? ""
                : "<\(args.map { renderTypeArgRef($0) }.joined(separator: ","))>"
            return "\(name)\(argStr)\(nullable ? "?" : "")"
        case let .functionType(contextReceivers, receiver, params, returnType, isSuspend, nullable):
            var prefix = isSuspend ? "suspend " : ""
            if !contextReceivers.isEmpty {
                prefix += "context(\(contextReceivers.map { renderTypeRef($0) }.joined(separator: ","))) "
            }
            let recv = receiver.map { "\(renderTypeRef($0))." } ?? ""
            let params = params.map { renderTypeRef($0) }.joined(separator: ",")
            let core = "\(prefix)\(recv)(\(params))->\(renderTypeRef(returnType))"
            return nullable ? "(\(core))?" : core
        case let .intersection(parts):
            return parts.map { renderTypeRef($0) }.joined(separator: "&")
        case let .annotated(base, _):
            return renderTypeRef(base)
        }
    }

    private func renderTypeArgRef(_ arg: TypeArgRef) -> String {
        switch arg {
        case let .invariant(ref): return renderTypeRef(ref)
        case let .out(ref): return "out \(renderTypeRef(ref))"
        case let .in(ref): return "in \(renderTypeRef(ref))"
        case .star: return "*"
        }
    }

    func requireSymbol(_ symbolID: SymbolID) {
        requiredSymbols.insert(symbolID.rawValue)
    }

    func renderType(_ typeID: TypeID) -> String {
        let raw = sema.types.renderType(typeID)
        return stabilizeTypeRefs(in: raw)
    }

    func renderSignature(_ signature: FunctionSignature) -> String {
        let raw = GoldenHarnessSemaFormat.renderFunctionSignature(signature, types: sema.types)
        return stabilizeTypeRefs(in: raw)
    }

    func expandRequiredSymbols() {
        var queue = Array(requiredSymbols)
        var visited = Set<Int32>()
        while !queue.isEmpty {
            let rawID = queue.removeFirst()
            guard visited.insert(rawID).inserted else { continue }
            let symID = SymbolID(rawValue: rawID)
            if let sig = sema.symbols.functionSignature(for: symID) {
                collectTypeSymbols(sig.receiverType, into: &queue)
                for paramType in sig.parameterTypes {
                    collectTypeSymbols(paramType, into: &queue)
                }
                collectTypeSymbols(sig.returnType, into: &queue)
                for bounds in sig.typeParameterUpperBoundsList {
                    for bound in bounds {
                        collectTypeSymbols(bound, into: &queue)
                    }
                }
                for tpSym in sig.typeParameterSymbols {
                    if requiredSymbols.insert(tpSym.rawValue).inserted {
                        queue.append(tpSym.rawValue)
                    }
                }
                for vpSym in sig.valueParameterSymbols {
                    if requiredSymbols.insert(vpSym.rawValue).inserted {
                        queue.append(vpSym.rawValue)
                    }
                }
            }
            if let propType = sema.symbols.propertyType(for: symID) {
                collectTypeSymbols(propType, into: &queue)
            }
        }
        requiredSymbols = visited
    }

    // MARK: - Private

    /// Builds the stable expression keys for every expression in the arena.
    ///
    /// Each key is derived from the expression's source start position
    /// (`e@<line>:<column>`) so the dump stays stable when unrelated
    /// expressions are inserted elsewhere. When several expressions share the
    /// same start position, a deterministic occurrence suffix (`#0`, `#1`, …)
    /// in arena order disambiguates them. Synthetic expressions without a
    /// source range fall back to a re-numbered ordinal (`e?<index>`).
    private static func buildExprKeys(arena: ASTArena, sourceManager: SourceManager) -> [Int32: String] {
        let exprs = arena.exprs
        var baseKeys: [(id: Int32, base: String)] = []
        baseKeys.reserveCapacity(exprs.count)
        var syntheticCounter = 0
        for raw in exprs.indices {
            let id = ExprID(rawValue: Int32(raw))
            if let range = arena.exprRange(id) {
                let location = sourceManager.lineColumn(of: range.start)
                baseKeys.append((Int32(raw), "e@\(location.line):\(location.column)"))
            } else {
                baseKeys.append((Int32(raw), "e?\(syntheticCounter)"))
                syntheticCounter += 1
            }
        }

        var counts: [String: Int] = [:]
        for entry in baseKeys {
            counts[entry.base, default: 0] += 1
        }

        var occurrences: [String: Int] = [:]
        var result: [Int32: String] = [:]
        result.reserveCapacity(baseKeys.count)
        for entry in baseKeys {
            if (counts[entry.base] ?? 0) > 1 {
                let index = occurrences[entry.base, default: 0]
                occurrences[entry.base] = index + 1
                result[entry.id] = "\(entry.base)#\(index)"
            } else {
                result[entry.id] = entry.base
            }
        }
        return result
    }

    private static func buildFileKeys(sourceManager: SourceManager) -> [Int32: String] {
        var keys: [Int32: String] = [:]
        for file in sourceManager.fileIDs() {
            let path = sourceManager.path(of: file)
            let key: String
            if path.isEmpty {
                key = "f?\(file.rawValue)"
            } else {
                let basename = (path as NSString).lastPathComponent
                let name = (basename as NSString).deletingPathExtension
                key = name.isEmpty ? "f?\(file.rawValue)" : name
            }
            keys[file.rawValue] = key
        }
        return keys
    }

    private func stabilizeTypeRefs(in text: String) -> String {
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        let matches = Self.typeRefRegex.matches(in: text, range: range)
        guard !matches.isEmpty else { return text }

        let mutable = NSMutableString(string: text)
        for match in matches.reversed() {
            let idRange = match.range(at: 2)
            guard idRange.location != NSNotFound,
                  let rawID = Int32(nsText.substring(with: idRange)),
                  let fq = symbolFQ[rawID]
            else { continue }
            requiredSymbols.insert(rawID)
            mutable.replaceCharacters(in: match.range, with: fq)
        }
        return mutable as String
    }

    private func collectTypeSymbols(_ typeID: TypeID?, into queue: inout [Int32]) {
        guard let typeID else { return }
        switch sema.types.kind(of: typeID) {
        case let .classType(ct):
            if requiredSymbols.insert(ct.classSymbol.rawValue).inserted {
                queue.append(ct.classSymbol.rawValue)
            }
            for arg in ct.args {
                switch arg {
                case let .invariant(t), let .out(t), let .in(t):
                    collectTypeSymbols(t, into: &queue)
                case .star:
                    break
                }
            }
        case let .typeParam(tp):
            if requiredSymbols.insert(tp.symbol.rawValue).inserted {
                queue.append(tp.symbol.rawValue)
            }
        case let .functionType(ft):
            for cr in ft.contextReceivers { collectTypeSymbols(cr, into: &queue) }
            collectTypeSymbols(ft.receiver, into: &queue)
            for p in ft.params { collectTypeSymbols(p, into: &queue) }
            collectTypeSymbols(ft.returnType, into: &queue)
        case let .kClassType(kc):
            if let kClassSymbol = sema.types.kClassInterfaceSymbol,
               requiredSymbols.insert(kClassSymbol.rawValue).inserted {
                queue.append(kClassSymbol.rawValue)
            }
            collectTypeSymbols(kc.argument, into: &queue)
        case let .intersection(parts):
            for part in parts { collectTypeSymbols(part, into: &queue) }
        case .error, .unit, .nothing, .any, .primitive, .stringStruct:
            break
        }
    }

}

/// Computes the meaning-based stable key for every symbol in a compilation.
///
/// The previous scheme numbered same-FQName candidates `#0`, `#1`, … in
/// signature order, so adding an *unreferenced* overload renumbered existing
/// references and a 1→2 candidate transition toggled the suffix entirely.
/// This computer instead derives each key from the declaration itself:
///
///     <fq>[kind=<k>;recv=<type>;params=<type,…>;susp;gen=<n>;scope=<disc>]
///
/// `kind` is always present. `recv`/`params`/`susp`/`gen` come from the
/// function signature (a bare `params=` distinguishes `fun f()` from `val f`).
/// `scope` is emitted only when several symbols would otherwise produce an
/// identical key, using the declaration's source position or enclosing symbol —
/// never a counter or a SymbolID.
///
/// Types are encoded structurally (`encodeTypeKey`) rather than reusing the
/// display `renderType` string, so `(() -> String)?` and `() -> String?`,
/// `T` / `T?` / `T!`, star/`in`/`out` projections, suspend and context
/// receivers stay distinct. Type parameters normalize to `T<declarationIndex>`
/// within their owner instead of names or symbol IDs. All memoization lives in
/// this per-render computer; nothing crosses case or process boundaries.
private final class StableSemanticKeyComputer {
    private let sema: SemaModule
    private let interner: StringInterner
    private let symbolFQ: [Int32: String]
    private let fileKeys: [Int32: String]
    private let sourceManager: SourceManager

    /// Per-render memoization of encoded types and type-parameter indices.
    private var typeKeyMemo: [TypeID: String] = [:]
    private var typeParamIndexMemo: [Int32: String] = [:]
    /// Reverse map `typeParameter symbol → declaration index inside its owner`.
    /// Built by scanning every signature / nominal parameter list, so a type
    /// parameter resolves by its declared position even when `parentSymbol`
    /// or its `fqName` parent is not resolvable (synthetic scopes, merged
    /// stub declarations).
    private var typeParamIndexBySymbol: [Int32: Int] = [:]

    init(
        sema: SemaModule,
        interner: StringInterner,
        symbolFQ: [Int32: String],
        fileKeys: [Int32: String],
        sourceManager: SourceManager
    ) {
        self.sema = sema
        self.interner = interner
        self.symbolFQ = symbolFQ
        self.fileKeys = fileKeys
        self.sourceManager = sourceManager
    }

    /// Returns `stableKey` for every symbol: `<displayFQ>[<inner>]`.
    func computeKeys() -> [Int32: String] {
        let allSymbols = sema.symbols.allSymbols()

        for symbol in allSymbols {
            // Nominal declarations first: a class-level type parameter keeps
            // the same index whether it is seen through the class itself or
            // through a member signature that lists class parameters first.
            for (index, typeParam) in sema.types.nominalTypeParameterSymbols(for: symbol.id).enumerated() {
                if typeParamIndexBySymbol[typeParam.rawValue] == nil {
                    typeParamIndexBySymbol[typeParam.rawValue] = index
                }
            }
            if let signature = sema.symbols.functionSignature(for: symbol.id) {
                for (index, typeParam) in signature.typeParameterSymbols.enumerated() {
                    if typeParamIndexBySymbol[typeParam.rawValue] == nil {
                        typeParamIndexBySymbol[typeParam.rawValue] = index
                    }
                }
            }
        }

        var inner: [Int32: String] = [:]
        inner.reserveCapacity(allSymbols.count)
        var fullKeyGroups: [String: [SemanticSymbol]] = [:]

        for symbol in allSymbols {
            let key = innerKey(for: symbol)
            inner[symbol.id.rawValue] = key
            let displayFQ = symbolFQ[symbol.id.rawValue] ?? "_"
            fullKeyGroups["\(displayFQ)\u{0}\(key)", default: []].append(symbol)
        }

        // Two declarations can only share a full key when they are genuine
        // same-scope redeclarations (e.g. shadowed locals) or synthetic stubs
        // that duplicate one declaration. Distinguish them by declaration
        // scope: source position first, then the enclosing symbol's key.
        for (_, group) in fullKeyGroups where group.count > 1 {
            for symbol in group {
                guard let scope = scopeDiscriminator(for: symbol) else { continue }
                inner[symbol.id.rawValue] = (inner[symbol.id.rawValue] ?? "") + ";scope=\(scope)"
            }
        }

        var result: [Int32: String] = [:]
        result.reserveCapacity(allSymbols.count)
        for symbol in allSymbols {
            let displayFQ = symbolFQ[symbol.id.rawValue] ?? "_"
            result[symbol.id.rawValue] = "\(displayFQ)[\(inner[symbol.id.rawValue] ?? "kind=?")]"
        }
        return result
    }

    // MARK: - Inner key

    private func innerKey(for symbol: SemanticSymbol) -> String {
        var parts = ["kind=\(Self.kindToken(symbol.kind))"]
        if let signature = sema.symbols.functionSignature(for: symbol.id) {
            if let receiver = signature.receiverType {
                parts.append("recv=\(encodeTypeKey(receiver))")
            }
            let params = signature.parameterTypes.enumerated().map { index, type in
                let isVararg = index < signature.valueParameterIsVararg.count
                    && signature.valueParameterIsVararg[index]
                return (isVararg ? "*" : "") + encodeTypeKey(type)
            }
            parts.append("params=\(params.joined(separator: ","))")
            if signature.isSuspend {
                parts.append("susp")
            }
            if !signature.typeParameterSymbols.isEmpty {
                parts.append("gen=\(signature.typeParameterSymbols.count)")
            }
        } else {
            switch symbol.kind {
            case .class, .interface, .object, .enumClass, .annotationClass, .typeAlias:
                let arity = sema.types.nominalTypeParameterSymbols(for: symbol.id).count
                if arity > 0 {
                    parts.append("gen=\(arity)")
                }
            default:
                break
            }
        }
        return parts.joined(separator: ";")
    }

    private static func kindToken(_ kind: SymbolKind) -> String {
        switch kind {
        case .package: "pkg"
        case .class: "class"
        case .interface: "iface"
        case .object: "obj"
        case .enumClass: "enum"
        case .annotationClass: "anno"
        case .typeAlias: "alias"
        case .function: "fun"
        case .constructor: "ctor"
        case .property: "prop"
        case .field: "field"
        case .backingField: "bfield"
        case .typeParameter: "tparam"
        case .valueParameter: "vparam"
        case .local: "local"
        case .label: "label"
        }
    }

    // MARK: - Structural type encoding

    /// Structural type key. Unlike `renderType`, nullability is part of the
    /// encoded shape: a nullable function type renders `fn{…}?` while a
    /// nullable return stays inside `ret=…?`, so the two never collapse.
    private func encodeTypeKey(_ typeID: TypeID, depth: Int = 0) -> String {
        if let cached = typeKeyMemo[typeID] {
            return cached
        }
        guard depth < 64 else { return "…" }
        let result: String
        switch sema.types.kind(of: typeID) {
        case .error:
            result = "err"
        case .unit:
            result = "Unit"
        case let .nothing(nullability):
            result = "Nothing\(Self.nullabilityMark(nullability))"
        case let .any(nullability):
            result = "Any\(Self.nullabilityMark(nullability))"
        case let .stringStruct(nullability):
            result = "String\(Self.nullabilityMark(nullability))"
        case let .primitive(primitive, nullability):
            result = "\(Self.escapeKeyAtom(primitive.kotlinName))\(Self.nullabilityMark(nullability))"
        case let .classType(classType):
            let base = escapedFQName(of: classType.classSymbol)
            let args = classType.args.isEmpty
                ? ""
                : "<\(classType.args.map { encodeTypeArg($0, depth: depth + 1) }.joined(separator: ","))>"
            result = "\(base)\(args)\(Self.nullabilityMark(classType.nullability))"
        case let .typeParam(typeParam):
            result = "\(typeParamKey(typeParam.symbol))\(Self.nullabilityMark(typeParam.nullability))"
        case let .functionType(functionType):
            var inner = functionType.isSuspend ? "su;" : ""
            if !functionType.contextReceivers.isEmpty {
                let receivers = functionType.contextReceivers
                    .map { encodeTypeKey($0, depth: depth + 1) }
                    .joined(separator: ",")
                inner += "ctx=\(receivers);"
            }
            if let receiver = functionType.receiver {
                inner += "r=\(encodeTypeKey(receiver, depth: depth + 1));"
            }
            let params = functionType.params
                .map { encodeTypeKey($0, depth: depth + 1) }
                .joined(separator: ",")
            inner += "p=\(params);ret=\(encodeTypeKey(functionType.returnType, depth: depth + 1))"
            if !functionType.throws.isEmpty {
                let thrown = functionType.throws
                    .map { encodeTypeKey($0, depth: depth + 1) }
                    .joined(separator: ",")
                inner += ";thr=\(thrown)"
            }
            result = "fn{\(inner)}\(Self.nullabilityMark(functionType.nullability))"
        case let .kClassType(kClassType):
            result = "kclass{\(encodeTypeKey(kClassType.argument, depth: depth + 1))}\(Self.nullabilityMark(kClassType.nullability))"
        case let .intersection(parts):
            let encoded = parts.map { encodeTypeKey($0, depth: depth + 1) }.sorted()
            result = "is{\(encoded.joined(separator: ";"))}"
        }
        typeKeyMemo[typeID] = result
        return result
    }

    private func encodeTypeArg(_ arg: TypeArg, depth: Int) -> String {
        switch arg {
        case let .invariant(type): encodeTypeKey(type, depth: depth)
        case let .out(type): "out \(encodeTypeKey(type, depth: depth))"
        case let .in(type): "in \(encodeTypeKey(type, depth: depth))"
        case .star: "*"
        }
    }

    /// Type parameters key by declaration position (`T0`, `T1`, …) inside their
    /// owner, so renaming a type parameter or regenerating symbol IDs cannot
    /// shift references. When the owner scan did not record a position
    /// (declarations detached from every parameter list), the declared name is
    /// used as a last-resort discriminator rather than an index.
    private func typeParamKey(_ symbol: SymbolID) -> String {
        if let cached = typeParamIndexMemo[symbol.rawValue] {
            return cached
        }
        let result: String
        if let index = typeParamIndexBySymbol[symbol.rawValue] {
            result = "T\(index)"
        } else if let sym = sema.symbols.symbol(symbol) {
            result = "T?\(Self.escapeKeyAtom(interner.resolve(sym.name)))"
        } else {
            result = "T?"
        }
        typeParamIndexMemo[symbol.rawValue] = result
        return result
    }

    // MARK: - Scope discriminator

    /// Last-resort identity when the semantic key collides: the declaration's
    /// own source position (stable across unrelated bundled-stdlib edits, same
    /// convention as `e@line:col` expression keys), or the enclosing symbol's
    /// key for position-less synthetic declarations.
    private func scopeDiscriminator(for symbol: SemanticSymbol) -> String? {
        if let site = symbol.declSite {
            let position = sourceManager.lineColumn(of: site.start)
            let file = fileKeys[site.start.file.rawValue] ?? "f?"
            return "\(Self.escapeKeyAtom(file))@\(position.line).\(position.column)"
        }
        if let parent = sema.symbols.parentSymbol(for: symbol.id),
           let parentSymbol = sema.symbols.symbol(parent) {
            let parentFQ = symbolFQ[parent.rawValue] ?? "_"
            return "up:\(parentFQ)[\(innerKey(for: parentSymbol))]"
        }
        return nil
    }

    // MARK: - Atoms

    private static func nullabilityMark(_ nullability: Nullability) -> String {
        switch nullability {
        case .nonNull: ""
        case .nullable: "?"
        case .platformType: "!"
        }
    }

    /// Escapes characters that are structural in the key grammar so that
    /// backtick identifiers or synthetic names can never blur field, list, or
    /// type boundaries.
    private static let keyReservedCharacters: Set<Character> = [
        "\\", ".", ";", ",", "[", "]", "{", "}", "<", ">", "=", "?", "!", "*", "(", ")", ":", " ",
    ]

    private static func escapeKeyAtom(_ text: String) -> String {
        var output = ""
        output.reserveCapacity(text.count)
        for character in text {
            if keyReservedCharacters.contains(character) {
                output.append("\\")
            }
            output.append(character)
        }
        return output
    }

    private func escapedFQName(of symbolID: SymbolID) -> String {
        guard let symbol = sema.symbols.symbol(symbolID) else { return "?" }
        return symbol.fqName
            .map { Self.escapeKeyAtom(interner.resolve($0)) }
            .joined(separator: ".")
    }
}
