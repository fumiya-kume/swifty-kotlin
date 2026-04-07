public struct CallArg {
    public let label: InternedString?
    public let isSpread: Bool
    public let type: TypeID

    public init(label: InternedString? = nil, isSpread: Bool = false, type: TypeID) {
        self.label = label
        self.isSpread = isSpread
        self.type = type
    }
}

public struct CallExpr {
    public let range: SourceRange
    public let calleeName: InternedString
    public let args: [CallArg]
    public let explicitTypeArgs: [TypeID]

    public init(range: SourceRange, calleeName: InternedString, args: [CallArg], explicitTypeArgs: [TypeID] = []) {
        self.range = range
        self.calleeName = calleeName
        self.args = args
        self.explicitTypeArgs = explicitTypeArgs
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

public struct ProbedCallCandidate {
    public let symbol: SymbolID
    public let instantiatedParameterTypes: [TypeID]
    public let substitutedTypeArguments: [TypeVarID: TypeID]
    public let parameterMapping: [Int: Int]

    public init(
        symbol: SymbolID,
        instantiatedParameterTypes: [TypeID],
        substitutedTypeArguments: [TypeVarID: TypeID],
        parameterMapping: [Int: Int]
    ) {
        self.symbol = symbol
        self.instantiatedParameterTypes = instantiatedParameterTypes
        self.substitutedTypeArguments = substitutedTypeArguments
        self.parameterMapping = parameterMapping
    }
}

public struct ProbedCallResult {
    public let viableCandidates: [ProbedCallCandidate]
    public let diagnostic: Diagnostic?

    public init(viableCandidates: [ProbedCallCandidate], diagnostic: Diagnostic?) {
        self.viableCandidates = viableCandidates
        self.diagnostic = diagnostic
    }
}

public final class OverloadResolver {
    /// Optional sema cache context.  When non-nil the resolver checks the
    /// call-resolution cache before performing full candidate evaluation.
    var cacheContext: SemaCacheContext?

    public init() {}
}
