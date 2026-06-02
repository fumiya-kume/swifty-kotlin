import Foundation

public extension TypeSystem {
    /// Produces a human-readable, Kotlin-style type string for display in IDE
    /// features such as hover and signatures.
    ///
    /// Unlike the internal `renderType` debug renderer (which prints class and
    /// type-parameter symbols as `Class#<id>` / `T#<id>`), this resolves those
    /// symbols to their source-level names via the symbol table and interner.
    func displayName(of type: TypeID, symbols: SymbolTable, interner: StringInterner) -> String {
        switch kind(of: type) {
        case .error:
            return "<error>"
        case .unit:
            return "Unit"
        case let .nothing(nullability):
            return "Nothing\(nullabilitySuffix(nullability))"
        case let .any(nullability):
            return "Any\(nullabilitySuffix(nullability))"
        case let .primitive(primitive, nullability):
            return "\(primitive.kotlinName)\(nullabilitySuffix(nullability))"
        case let .classType(classType):
            let base = symbolDisplayName(classType.classSymbol, symbols: symbols, interner: interner)
                ?? "Class#\(classType.classSymbol.rawValue)"
            let args = classType.args.isEmpty
                ? ""
                : "<" + classType.args
                    .map { displayTypeArg($0, symbols: symbols, interner: interner) }
                    .joined(separator: ", ") + ">"
            return "\(base)\(args)\(nullabilitySuffix(classType.nullability))"
        case let .typeParam(typeParam):
            let name = symbolDisplayName(typeParam.symbol, symbols: symbols, interner: interner)
                ?? "T#\(typeParam.symbol.rawValue)"
            return "\(name)\(nullabilitySuffix(typeParam.nullability))"
        case let .functionType(functionType):
            return displayFunctionType(functionType, symbols: symbols, interner: interner)
        case let .kClassType(kClassType):
            let arg = displayName(of: kClassType.argument, symbols: symbols, interner: interner)
            return "KClass<\(arg)>\(nullabilitySuffix(kClassType.nullability))"
        case let .intersection(parts):
            return parts
                .map { displayName(of: $0, symbols: symbols, interner: interner) }
                .joined(separator: " & ")
        }
    }

    private func displayFunctionType(
        _ functionType: FunctionType,
        symbols: SymbolTable,
        interner: StringInterner
    ) -> String {
        let contextPrefix = functionType.contextReceivers.isEmpty
            ? ""
            : "context(" + functionType.contextReceivers
                .map { displayName(of: $0, symbols: symbols, interner: interner) }
                .joined(separator: ", ") + ") "
        let receiverPrefix = functionType.receiver
            .map { "\(displayName(of: $0, symbols: symbols, interner: interner))." } ?? ""
        let suspendPrefix = functionType.isSuspend ? "suspend " : ""
        let params = functionType.params
            .map { displayName(of: $0, symbols: symbols, interner: interner) }
            .joined(separator: ", ")
        let ret = displayName(of: functionType.returnType, symbols: symbols, interner: interner)
        let suffix = nullabilitySuffix(functionType.nullability)
        return "\(contextPrefix)\(suspendPrefix)\(receiverPrefix)(\(params)) -> \(ret)\(suffix)"
    }

    private func displayTypeArg(
        _ arg: TypeArg,
        symbols: SymbolTable,
        interner: StringInterner
    ) -> String {
        switch arg {
        case let .invariant(type):
            displayName(of: type, symbols: symbols, interner: interner)
        case let .out(type):
            "out \(displayName(of: type, symbols: symbols, interner: interner))"
        case let .in(type):
            "in \(displayName(of: type, symbols: symbols, interner: interner))"
        case .star:
            "*"
        }
    }

    private func symbolDisplayName(
        _ symbol: SymbolID,
        symbols: SymbolTable,
        interner: StringInterner
    ) -> String? {
        guard let sym = symbols.symbol(symbol) else { return nil }
        let short = interner.resolve(sym.name)
        if !short.isEmpty { return short }
        if let last = sym.fqName.last {
            let resolved = interner.resolve(last)
            if !resolved.isEmpty { return resolved }
        }
        return nil
    }
}
