import Foundation

enum ExtensionFunctionTypeSupport {
    static func normalizeAnnotatedType(
        baseType: TypeID,
        annotations: [AnnotationNode],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        diagnostics: DiagnosticEngine?,
        range: SourceRange? = nil
    ) -> TypeID {
        guard annotations.contains(where: isExtensionFunctionTypeAnnotation) else {
            return baseType
        }

        switch types.kind(of: baseType) {
        case .functionType:
            return baseType

        case let .classType(classType):
            guard let symbol = symbols.symbol(classType.classSymbol) else {
                diagnostics?.error(
                    "KSWIFTK-SEMA-EXTFN-TYPE",
                    "ExtensionFunctionType requires a FunctionN type.",
                    range: range
                )
                return types.errorType
            }
            guard let arity = functionArity(of: symbol, interner: interner) else {
                diagnostics?.error(
                    "KSWIFTK-SEMA-EXTFN-TYPE",
                    "ExtensionFunctionType requires a FunctionN type.",
                    range: range
                )
                return types.errorType
            }
            guard arity > 0 else {
                diagnostics?.error(
                    "KSWIFTK-SEMA-EXTFN-TYPE",
                    "ExtensionFunctionType requires a receiver type and cannot be applied to Function0.",
                    range: range
                )
                return types.errorType
            }

            let typeArgs = classType.args.compactMap(typeID(from:))
            guard typeArgs.count == arity + 1 else {
                diagnostics?.error(
                    "KSWIFTK-SEMA-EXTFN-TYPE",
                    "ExtensionFunctionType requires Function\(arity) to have exactly \(arity + 1) type arguments.",
                    range: range
                )
                return types.errorType
            }

            let receiver = typeArgs[0]
            let params = Array(typeArgs.dropFirst().dropLast())
            let returnType = typeArgs[typeArgs.count - 1]
            return types.make(.functionType(FunctionType(
                receiver: receiver,
                params: params,
                returnType: returnType,
                isSuspend: false,
                nullability: classType.nullability
            )))

        default:
            diagnostics?.error(
                "KSWIFTK-SEMA-EXTFN-TYPE",
                "ExtensionFunctionType requires a FunctionN type.",
                range: range
            )
            return types.errorType
        }
    }

    static func isExtensionFunctionTypeAnnotation(_ annotation: AnnotationNode) -> Bool {
        annotation.name == "ExtensionFunctionType"
            || annotation.name == "kotlin.ExtensionFunctionType"
    }

    private static func functionArity(of symbol: SemanticSymbol, interner: StringInterner) -> Int? {
        let name = symbol.fqName.last.map(interner.resolve) ?? interner.resolve(symbol.name)
        guard name.hasPrefix("Function"),
              let arity = Int(name.dropFirst("Function".count))
        else {
            return nil
        }
        return arity
    }

    private static func typeID(from arg: TypeArg) -> TypeID? {
        switch arg {
        case let .invariant(type), let .out(type), let .in(type):
            type
        case .star:
            nil
        }
    }
}
