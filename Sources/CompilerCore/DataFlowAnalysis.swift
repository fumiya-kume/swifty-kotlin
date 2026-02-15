public struct VariableFlowState: Equatable {
    public var possibleTypes: Set<TypeID>
    public var nullability: Nullability
    public var isStable: Bool

    public init(possibleTypes: Set<TypeID>, nullability: Nullability, isStable: Bool) {
        self.possibleTypes = possibleTypes
        self.nullability = nullability
        self.isStable = isStable
    }
}

public struct DataFlowState: Equatable {
    public var variables: [SymbolID: VariableFlowState]

    public init(variables: [SymbolID: VariableFlowState] = [:]) {
        self.variables = variables
    }
}

public struct WhenBranchSummary {
    public let coveredSymbols: Set<InternedString>
    public let hasElse: Bool

    public init(coveredSymbols: Set<InternedString>, hasElse: Bool) {
        self.coveredSymbols = coveredSymbols
        self.hasElse = hasElse
    }
}

public final class DataFlowAnalyzer {
    public init() {}

    public func merge(_ lhs: DataFlowState, _ rhs: DataFlowState) -> DataFlowState {
        var merged = lhs.variables
        for (symbol, rhsState) in rhs.variables {
            if let lhsState = merged[symbol] {
                let types = lhsState.possibleTypes.union(rhsState.possibleTypes)
                let nullability: Nullability = (lhsState.nullability == .nullable || rhsState.nullability == .nullable)
                    ? .nullable
                    : .nonNull
                merged[symbol] = VariableFlowState(
                    possibleTypes: types,
                    nullability: nullability,
                    isStable: lhsState.isStable && rhsState.isStable
                )
            } else {
                merged[symbol] = rhsState
            }
        }
        return DataFlowState(variables: merged)
    }

    public func isWhenExhaustive(
        subjectType: TypeID,
        branches: WhenBranchSummary,
        sema: SemaModule
    ) -> Bool {
        if branches.hasElse {
            return true
        }
        let kind = sema.types.kind(of: subjectType)
        switch kind {
        case .primitive(.boolean, _):
            // `true` and `false` branches are both required when `else` is absent.
            return branches.coveredSymbols.count >= 2
        case .classType:
            // For now rely on else branch for class-like types.
            return false
        case .any(.nullable):
            return false
        default:
            return false
        }
    }
}
