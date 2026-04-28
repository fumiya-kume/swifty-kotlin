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
        let hasExtensionReceiver = annotations.contains(where: isExtensionFunctionTypeAnnotation)
        let contextReceiverCount = contextFunctionTypeParamsCount(in: annotations, diagnostics: diagnostics, range: range)

        guard hasExtensionReceiver || contextReceiverCount != nil else {
            return baseType
        }

        switch types.kind(of: baseType) {
        case .functionType:
            return baseType

        case let .classType(classType):
            guard let symbol = symbols.symbol(classType.classSymbol) else {
                diagnostics?.error(
                    diagnosticCode(hasExtensionReceiver: hasExtensionReceiver),
                    functionTypeAnnotationRequiresFunctionMessage(hasExtensionReceiver: hasExtensionReceiver),
                    range: range
                )
                return types.errorType
            }
            guard let arity = functionArity(of: symbol, interner: interner) else {
                diagnostics?.error(
                    diagnosticCode(hasExtensionReceiver: hasExtensionReceiver),
                    functionTypeAnnotationRequiresFunctionMessage(hasExtensionReceiver: hasExtensionReceiver),
                    range: range
                )
                return types.errorType
            }
            let contextCount = contextReceiverCount ?? 0
            guard contextCount >= 0 else {
                diagnostics?.error(
                    "KSWIFTK-SEMA-CONTEXT-FN-TYPE",
                    "ContextFunctionTypeParams count must be non-negative.",
                    range: range
                )
                return types.errorType
            }
            guard contextCount <= arity else {
                diagnostics?.error(
                    "KSWIFTK-SEMA-CONTEXT-FN-TYPE",
                    "ContextFunctionTypeParams count cannot exceed Function\(arity) arity.",
                    range: range
                )
                return types.errorType
            }
            guard !hasExtensionReceiver || arity > contextCount else {
                diagnostics?.error(
                    "KSWIFTK-SEMA-EXTFN-TYPE",
                    "ExtensionFunctionType requires a receiver type after context receiver parameters.",
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

            let contextReceivers = Array(typeArgs.prefix(contextCount))
            let receiver = hasExtensionReceiver ? typeArgs[contextCount] : nil
            let paramStart = contextCount + (hasExtensionReceiver ? 1 : 0)
            let params = Array(typeArgs[paramStart..<(typeArgs.count - 1)])
            let returnType = typeArgs[typeArgs.count - 1]
            return types.make(.functionType(FunctionType(
                contextReceivers: contextReceivers,
                receiver: receiver,
                params: params,
                returnType: returnType,
                isSuspend: false,
                nullability: classType.nullability
            )))

        default:
            diagnostics?.error(
                diagnosticCode(hasExtensionReceiver: hasExtensionReceiver),
                functionTypeAnnotationRequiresFunctionMessage(hasExtensionReceiver: hasExtensionReceiver),
                range: range
            )
            return types.errorType
        }
    }

    static func isExtensionFunctionTypeAnnotation(_ annotation: AnnotationNode) -> Bool {
        annotation.name == "ExtensionFunctionType"
            || annotation.name == "kotlin.ExtensionFunctionType"
    }

    private static func isContextFunctionTypeParamsAnnotation(_ annotation: AnnotationNode) -> Bool {
        annotation.name == "ContextFunctionTypeParams"
            || annotation.name == "kotlin.ContextFunctionTypeParams"
    }

    private static func contextFunctionTypeParamsCount(
        in annotations: [AnnotationNode],
        diagnostics: DiagnosticEngine?,
        range: SourceRange?
    ) -> Int? {
        guard let annotation = annotations.first(where: isContextFunctionTypeParamsAnnotation) else {
            return nil
        }
        guard let rawCount = annotation.arguments.first else {
            diagnostics?.error(
                "KSWIFTK-SEMA-CONTEXT-FN-TYPE",
                "ContextFunctionTypeParams requires a count argument.",
                range: range
            )
            return 0
        }
        let value = annotationArgumentValue(rawCount)
        guard let count = Int(value) else {
            diagnostics?.error(
                "KSWIFTK-SEMA-CONTEXT-FN-TYPE",
                "ContextFunctionTypeParams count must be an integer literal.",
                range: range
            )
            return 0
        }
        return count
    }

    private static func annotationArgumentValue(_ argument: String) -> String {
        let trimmed = argument.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let equalIndex = trimmed.firstIndex(of: "=") else {
            return trimmed
        }
        return String(trimmed[trimmed.index(after: equalIndex)...]).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func diagnosticCode(hasExtensionReceiver: Bool) -> String {
        hasExtensionReceiver ? "KSWIFTK-SEMA-EXTFN-TYPE" : "KSWIFTK-SEMA-CONTEXT-FN-TYPE"
    }

    private static func functionTypeAnnotationRequiresFunctionMessage(hasExtensionReceiver: Bool) -> String {
        if hasExtensionReceiver {
            return "ExtensionFunctionType requires a FunctionN type."
        }
        return "ContextFunctionTypeParams requires a FunctionN type."
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
