public struct CallArg {
    public let label: InternedString?
    public let type: TypeID

    public init(label: InternedString? = nil, type: TypeID) {
        self.label = label
        self.type = type
    }
}

public struct CallExpr {
    public let range: SourceRange
    public let calleeName: InternedString
    public let args: [CallArg]

    public init(range: SourceRange, calleeName: InternedString, args: [CallArg]) {
        self.range = range
        self.calleeName = calleeName
        self.args = args
    }
}

public struct ResolvedCall {
    public let chosenCallee: SymbolID?
    public let substitutedTypeArguments: [TypeVarID: TypeID]
    public let parameterMapping: [Int: Int]
    public let diagnostic: Diagnostic?

    public init(
        chosenCallee: SymbolID?,
        substitutedTypeArguments: [TypeVarID: TypeID],
        parameterMapping: [Int: Int],
        diagnostic: Diagnostic?
    ) {
        self.chosenCallee = chosenCallee
        self.substitutedTypeArguments = substitutedTypeArguments
        self.parameterMapping = parameterMapping
        self.diagnostic = diagnostic
    }
}

public final class OverloadResolver {
    public init() {}

    public func resolveCall(
        candidates: [SymbolID],
        call: CallExpr,
        expectedType: TypeID?,
        ctx: SemaContext
    ) -> ResolvedCall {
        var viable: [(symbol: SymbolID, signature: FunctionSignature)] = []
        for candidate in candidates {
            guard let symbol = ctx.symbols.symbol(candidate) else {
                continue
            }
            guard symbol.kind == .function || symbol.kind == .constructor else {
                continue
            }
            guard let signature = ctx.symbols.functionSignature(for: candidate) else {
                continue
            }
            if signature.parameterTypes.count != call.args.count {
                continue
            }
            var matches = true
            for (arg, paramType) in zip(call.args, signature.parameterTypes) {
                if !ctx.types.isSubtype(arg.type, paramType) {
                    matches = false
                    break
                }
            }
            if let expectedType, !ctx.types.isSubtype(signature.returnType, expectedType) {
                matches = false
            }
            if matches {
                viable.append((candidate, signature))
            }
        }

        if viable.isEmpty {
            let diagnostic = Diagnostic(
                severity: .error,
                code: "KSWIFTK-SEMA-0002",
                message: "No viable overload found for call.",
                primaryRange: call.range,
                secondaryRanges: []
            )
            return ResolvedCall(
                chosenCallee: nil,
                substitutedTypeArguments: [:],
                parameterMapping: [:],
                diagnostic: diagnostic
            )
        }

        if viable.count > 1 {
            let diagnostic = Diagnostic(
                severity: .error,
                code: "KSWIFTK-SEMA-0003",
                message: "Ambiguous overload resolution.",
                primaryRange: call.range,
                secondaryRanges: []
            )
            return ResolvedCall(
                chosenCallee: nil,
                substitutedTypeArguments: [:],
                parameterMapping: [:],
                diagnostic: diagnostic
            )
        }

        let chosen = viable[0]
        var mapping: [Int: Int] = [:]
        for index in call.args.indices {
            mapping[index] = index
        }
        return ResolvedCall(
            chosenCallee: chosen.symbol,
            substitutedTypeArguments: [:],
            parameterMapping: mapping,
            diagnostic: nil
        )
    }
}
