@testable import CompilerCore
import Foundation

final class StableRenderContext {
    let sema: SemaModule
    let interner: StringInterner
    let arena: ASTArena

    private let sourceManager: SourceManager
    private let symbolFQ: [Int32: String]
    private let overloadSuffix: [Int32: String]
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
        var fqGroups: [String: [SemanticSymbol]] = [:]

        for symbol in sema.symbols.allSymbols() {
            let fq = GoldenHarnessSemaFormat.renderFQName(symbol.fqName, interner: interner)
            fqMap[symbol.id.rawValue] = fq
            fqGroups[fq, default: []].append(symbol)
        }

        var stableTypeParameterFQ: [Int32: String] = [:]
        for symbol in sema.symbols.allSymbols() where symbol.kind == .typeParameter {
            if let fq = fqMap[symbol.id.rawValue] {
                stableTypeParameterFQ[symbol.id.rawValue] = Self.stabilizeTypeParameterFQName(fq)
            }
        }

        self.symbolFQ = fqMap

        var suffixes: [Int32: String] = [:]
        for (_, symbols) in fqGroups where symbols.count > 1 {
            // Rendering and stabilizing a signature is independent of the
            // comparison partner, so compute each key only once per symbol.
            let keyedSymbols = symbols.map { symbol in
                (
                    id: symbol.id,
                    key: Self.overloadSortKey(
                        symbol,
                        sema: sema,
                        fqMap: fqMap,
                        stableTypeParameterFQ: stableTypeParameterFQ
                    )
                )
            }
            let sorted = keyedSymbols.sorted { lhs, rhs in
                Self.overloadSortKeyPrecedes(
                    lhs.key,
                    lhsSymbolID: lhs.id.rawValue,
                    rhs.key,
                    rhsSymbolID: rhs.id.rawValue
                )
            }
            for (idx, sym) in sorted.enumerated() {
                suffixes[sym.id.rawValue] = "#\(idx)"
            }
        }
        self.overloadSuffix = suffixes
    }

    func stableKey(for symbolID: SymbolID) -> String {
        let fq = symbolFQ[symbolID.rawValue] ?? "_"
        let suffix = overloadSuffix[symbolID.rawValue] ?? ""
        return fq + suffix
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

    private static func overloadSortKey(
        _ symbol: SemanticSymbol,
        sema: SemaModule,
        fqMap: [Int32: String],
        stableTypeParameterFQ: [Int32: String]
    ) -> String {
        guard let sig = sema.symbols.functionSignature(for: symbol.id) else {
            return ""
        }
        let recv = sig.receiverType.map {
            stabilizeTypeRefsStatic(
                sema.types.renderType($0),
                fqMap: fqMap,
                stableTypeParameterFQ: stableTypeParameterFQ
            )
        } ?? "_"
        let params = sig.parameterTypes.map {
            stabilizeTypeRefsStatic(
                sema.types.renderType($0),
                fqMap: fqMap,
                stableTypeParameterFQ: stableTypeParameterFQ
            )
        }
        return "\(recv)|\(params.joined(separator: ","))"
    }

    /// Orders overload keys numerically because generated generic-owner names
    /// contain unpadded symbol IDs such as `$9999` and `$10001`.
    static func overloadSortKeyPrecedes(
        _ lhsKey: String,
        lhsSymbolID: Int32,
        _ rhsKey: String,
        rhsSymbolID: Int32
    ) -> Bool {
        switch lhsKey.compare(rhsKey, options: .numeric) {
        case .orderedAscending:
            return true
        case .orderedDescending:
            return false
        case .orderedSame:
            if lhsKey != rhsKey {
                return lhsKey < rhsKey
            }
            return lhsSymbolID < rhsSymbolID
        }
    }

    private static func stabilizeTypeRefsStatic(
        _ text: String,
        fqMap: [Int32: String],
        stableTypeParameterFQ: [Int32: String]
    ) -> String {
        let nsText = text as NSString
        let range = NSRange(location: 0, length: nsText.length)
        let matches = typeRefRegex.matches(in: text, range: range)
        guard !matches.isEmpty else { return text }

        let mutable = NSMutableString(string: text)
        for match in matches.reversed() {
            let idRange = match.range(at: 2)
            guard idRange.location != NSNotFound,
                  let rawID = Int32(nsText.substring(with: idRange))
            else { continue }
            let prefix = nsText.substring(with: match.range(at: 1))
            let stableFQ: String?
            if prefix == "T#" {
                stableFQ = stableTypeParameterFQ[rawID] ?? fqMap[rawID]
            } else {
                stableFQ = fqMap[rawID]
            }
            guard let stableFQ else {
                continue
            }
            mutable.replaceCharacters(in: match.range, with: stableFQ)
        }
        return mutable as String
    }

    private static func stabilizeTypeParameterFQName(_ fq: String) -> String {
        let components = fq.split(separator: ".", omittingEmptySubsequences: false)
        return components.map { component in
            let characters = Array(component)
            guard characters.first == "$" else { return String(component) }

            var digitStart = 1
            while digitStart < characters.count, characters[digitStart].isLetter {
                digitStart += 1
            }
            guard digitStart < characters.count,
                  characters[digitStart...].allSatisfy(\.isNumber),
                  let ownerID = Int64(String(characters[digitStart...]))
            else {
                return String(component)
            }

            let prefix = String(characters[..<digitStart])
            return prefix + String(format: "%010lld", ownerID)
        }.joined(separator: ".")
    }
}
