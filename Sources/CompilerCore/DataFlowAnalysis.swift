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
    public let hasNullCase: Bool
    public let hasTrueCase: Bool
    public let hasFalseCase: Bool

    public init(
        coveredSymbols: Set<InternedString>,
        hasElse: Bool,
        hasNullCase: Bool = false,
        hasTrueCase: Bool? = nil,
        hasFalseCase: Bool? = nil
    ) {
        self.coveredSymbols = coveredSymbols
        self.hasElse = hasElse
        self.hasNullCase = hasNullCase
        self.hasTrueCase = hasTrueCase ?? coveredSymbols.contains(InternedString(rawValue: 1))
        self.hasFalseCase = hasFalseCase ?? coveredSymbols.contains(InternedString(rawValue: 2))
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
        case .primitive(.boolean, .nonNull):
            return branches.hasTrueCase && branches.hasFalseCase
        case .primitive(.boolean, .nullable):
            return branches.hasTrueCase && branches.hasFalseCase && branches.hasNullCase
        case .classType(let classType):
            return isClassWhenExhaustive(
                classType: classType,
                branches: branches,
                sema: sema
            )
        case .any(.nullable):
            return false
        default:
            return false
        }
    }

    private func isClassWhenExhaustive(
        classType: ClassType,
        branches: WhenBranchSummary,
        sema: SemaModule
    ) -> Bool {
        guard let classSymbol = sema.symbols.symbol(classType.classSymbol) else {
            return false
        }

        switch classSymbol.kind {
        case .enumClass:
            let enumEntryNames = enumEntryNames(for: classSymbol, sema: sema)
            guard !enumEntryNames.isEmpty else {
                return false
            }
            let hasAllEnumEntries = enumEntryNames.isSubset(of: branches.coveredSymbols)
            if classType.nullability == .nullable {
                return hasAllEnumEntries && branches.hasNullCase
            }
            return hasAllEnumEntries

        default:
            if classSymbol.flags.contains(.sealedType) {
                let subtypeNames = Set(sema.symbols.directSubtypes(of: classSymbol.id).compactMap { subtype in
                    sema.symbols.symbol(subtype)?.name
                })
                guard !subtypeNames.isEmpty else {
                    return false
                }
                let hasAllSealedSubtypes = subtypeNames.isSubset(of: branches.coveredSymbols)
                if classType.nullability == .nullable {
                    return hasAllSealedSubtypes && branches.hasNullCase
                }
                return hasAllSealedSubtypes
            }
            return false
        }
    }

    private func enumEntryNames(for enumSymbol: SemanticSymbol, sema: SemaModule) -> Set<InternedString> {
        let enumFQName = enumSymbol.fqName
        let expectedCount = enumFQName.count + 1
        let entries = sema.symbols.allSymbols().filter { symbol in
            guard symbol.kind == .field else {
                return false
            }
            guard symbol.fqName.count == expectedCount else {
                return false
            }
            return Array(symbol.fqName.dropLast()) == enumFQName
        }
        return Set(entries.map(\.name))
    }
}
