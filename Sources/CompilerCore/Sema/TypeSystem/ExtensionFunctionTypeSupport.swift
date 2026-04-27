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
        let hasExtensionFunctionType = annotations.contains(where: isExtensionFunctionTypeAnnotation)
        let contextAnnotation = annotations.last(where: isContextFunctionTypeParamsAnnotation)
        guard hasExtensionFunctionType || contextAnnotation != nil else {
            return baseType
        }
        let contextCount: Int
        if let contextAnnotation {
            guard let parsedCount = parseContextFunctionTypeParamsCount(
                contextAnnotation,
                diagnostics: diagnostics,
                range: range
            ) else {
                return types.errorType
            }
            contextCount = parsedCount
        } else {
            contextCount = 0
        }

        switch types.kind(of: baseType) {
        case .functionType:
            return baseType

        case let .classType(classType):
            guard let symbol = symbols.symbol(classType.classSymbol) else {
                diagnostics?.error(
                    diagnosticCode(hasContextFunctionTypeParams: contextAnnotation != nil),
                    functionTypeAnnotationMessage(
                        hasExtensionFunctionType: hasExtensionFunctionType,
                        hasContextFunctionTypeParams: contextAnnotation != nil,
                        detail: "requires a FunctionN type."
                    ),
                    range: range
                )
                return types.errorType
            }
            guard let arity = functionArity(of: symbol, interner: interner) else {
                diagnostics?.error(
                    diagnosticCode(hasContextFunctionTypeParams: contextAnnotation != nil),
                    functionTypeAnnotationMessage(
                        hasExtensionFunctionType: hasExtensionFunctionType,
                        hasContextFunctionTypeParams: contextAnnotation != nil,
                        detail: "requires a FunctionN type."
                    ),
                    range: range
                )
                return types.errorType
            }
            guard contextCount <= arity else {
                diagnostics?.error(
                    "KSWIFTK-SEMA-CONTEXT-FN-TYPE",
                    "ContextFunctionTypeParams count \(contextCount) exceeds Function\(arity) arity.",
                    range: range
                )
                return types.errorType
            }

            let typeArgs = classType.args.compactMap(typeID(from:))
            guard typeArgs.count == arity + 1 else {
                diagnostics?.error(
                    diagnosticCode(hasContextFunctionTypeParams: contextAnnotation != nil),
                    functionTypeAnnotationMessage(
                        hasExtensionFunctionType: hasExtensionFunctionType,
                        hasContextFunctionTypeParams: contextAnnotation != nil,
                        detail: "requires Function\(arity) to have exactly \(arity + 1) type arguments."
                    ),
                    range: range
                )
                return types.errorType
            }
            if hasExtensionFunctionType, contextCount >= arity {
                diagnostics?.error(
                    "KSWIFTK-SEMA-EXTFN-TYPE",
                    "ExtensionFunctionType requires a receiver type after ContextFunctionTypeParams context receivers.",
                    range: range
                )
                return types.errorType
            }

            let contextReceivers = Array(typeArgs.prefix(contextCount))
            let functionalParameters = Array(typeArgs.dropFirst(contextCount).dropLast())
            let receiver = hasExtensionFunctionType ? functionalParameters.first : nil
            let params = hasExtensionFunctionType
                ? Array(functionalParameters.dropFirst())
                : functionalParameters
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
                diagnosticCode(hasContextFunctionTypeParams: contextAnnotation != nil),
                functionTypeAnnotationMessage(
                    hasExtensionFunctionType: hasExtensionFunctionType,
                    hasContextFunctionTypeParams: contextAnnotation != nil,
                    detail: "requires a FunctionN type."
                ),
                range: range
            )
            return types.errorType
        }
    }

    static func isExtensionFunctionTypeAnnotation(_ annotation: AnnotationNode) -> Bool {
        annotation.name == "ExtensionFunctionType"
            || annotation.name == "kotlin.ExtensionFunctionType"
    }

    static func isContextFunctionTypeParamsAnnotation(_ annotation: AnnotationNode) -> Bool {
        KnownCompilerAnnotation.contextFunctionTypeParams.matches(annotation.name)
    }

    private static func parseContextFunctionTypeParamsCount(
        _ annotation: AnnotationNode,
        diagnostics: DiagnosticEngine?,
        range: SourceRange?
    ) -> Int? {
        guard let argument = annotation.arguments.first else {
            diagnostics?.error(
                "KSWIFTK-SEMA-CONTEXT-FN-TYPE",
                "ContextFunctionTypeParams requires a non-negative count argument.",
                range: range
            )
            return nil
        }
        let value = annotationArgumentValue(argument)
        guard let count = Int(value), count >= 0 else {
            diagnostics?.error(
                "KSWIFTK-SEMA-CONTEXT-FN-TYPE",
                "ContextFunctionTypeParams count must be a non-negative Int literal.",
                range: range
            )
            return nil
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

    private static func diagnosticCode(hasContextFunctionTypeParams: Bool) -> String {
        hasContextFunctionTypeParams ? "KSWIFTK-SEMA-CONTEXT-FN-TYPE" : "KSWIFTK-SEMA-EXTFN-TYPE"
    }

    private static func functionTypeAnnotationMessage(
        hasExtensionFunctionType: Bool,
        hasContextFunctionTypeParams: Bool,
        detail: String
    ) -> String {
        switch (hasExtensionFunctionType, hasContextFunctionTypeParams) {
        case (true, true):
            "ContextFunctionTypeParams with ExtensionFunctionType \(detail)"
        case (true, false):
            "ExtensionFunctionType \(detail)"
        case (false, true):
            "ContextFunctionTypeParams \(detail)"
        case (false, false):
            "Function type annotation \(detail)"
        }
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
