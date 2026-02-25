public final class TypeSystem {
    private var kindToID: [TypeKind: TypeID] = [:]
    private var idToKind: [TypeKind] = []
    private var nominalDirectSupertypes: [SymbolID: [SymbolID]] = [:]
    private var nominalTypeParameterVariancesMap: [SymbolID: [TypeVariance]] = [:]
    private var nominalTypeParameterSymbolsMap: [SymbolID: [SymbolID]] = [:]
    private var nominalSupertypeTypeArgsMap: [SymbolID: [SymbolID: [TypeArg]]] = [:]

    public let errorType: TypeID
    public let unitType: TypeID
    public let nothingType: TypeID
    public let nullableNothingType: TypeID
    public let anyType: TypeID
    public let nullableAnyType: TypeID
    public let booleanType: TypeID
    public let charType: TypeID
    public let intType: TypeID
    public let longType: TypeID
    public let floatType: TypeID
    public let doubleType: TypeID
    public let stringType: TypeID

    public init() {
        self.errorType = TypeID(rawValue: 0)
        self.unitType = TypeID(rawValue: 1)
        self.nothingType = TypeID(rawValue: 2)
        self.nullableNothingType = TypeID(rawValue: 3)
        self.anyType = TypeID(rawValue: 4)
        self.nullableAnyType = TypeID(rawValue: 5)
        self.booleanType = TypeID(rawValue: 6)
        self.charType = TypeID(rawValue: 7)
        self.intType = TypeID(rawValue: 8)
        self.longType = TypeID(rawValue: 9)
        self.floatType = TypeID(rawValue: 10)
        self.doubleType = TypeID(rawValue: 11)
        self.stringType = TypeID(rawValue: 12)

        idToKind = [
            .error,
            .unit,
            .nothing(.nonNull),
            .nothing(.nullable),
            .any(.nonNull),
            .any(.nullable),
            .primitive(.boolean, .nonNull),
            .primitive(.char, .nonNull),
            .primitive(.int, .nonNull),
            .primitive(.long, .nonNull),
            .primitive(.float, .nonNull),
            .primitive(.double, .nonNull),
            .primitive(.string, .nonNull),
        ]
        kindToID = [
            .error: errorType,
            .unit: unitType,
            .nothing(.nonNull): nothingType,
            .nothing(.nullable): nullableNothingType,
            .any(.nonNull): anyType,
            .any(.nullable): nullableAnyType,
            .primitive(.boolean, .nonNull): booleanType,
            .primitive(.char, .nonNull): charType,
            .primitive(.int, .nonNull): intType,
            .primitive(.long, .nonNull): longType,
            .primitive(.float, .nonNull): floatType,
            .primitive(.double, .nonNull): doubleType,
            .primitive(.string, .nonNull): stringType,
        ]
    }

    public func withNullability(_ nullability: Nullability, for type: TypeID) -> TypeID {
        switch kind(of: type) {
        case .error, .unit, .intersection:
            return type
        case .nothing(let existing):
            if existing == nullability { return type }
            return nullability == .nullable ? nullableNothingType : nothingType
        case .any(let existing):
            if existing == nullability { return type }
            return nullability == .nullable ? nullableAnyType : anyType
        case .primitive(let prim, let existing):
            if existing == nullability { return type }
            return make(.primitive(prim, nullability))
        case .classType(let ct):
            if ct.nullability == nullability { return type }
            return make(.classType(ClassType(classSymbol: ct.classSymbol, args: ct.args, nullability: nullability)))
        case .typeParam(let tp):
            if tp.nullability == nullability { return type }
            return make(.typeParam(TypeParamType(symbol: tp.symbol, nullability: nullability)))
        case .functionType(let ft):
            if ft.nullability == nullability { return type }
            return make(.functionType(FunctionType(receiver: ft.receiver, params: ft.params, returnType: ft.returnType, isSuspend: ft.isSuspend, nullability: nullability)))
        }
    }

    public func makeNullable(_ type: TypeID) -> TypeID {
        withNullability(.nullable, for: type)
    }

    public func makeNonNullable(_ type: TypeID) -> TypeID {
        withNullability(.nonNull, for: type)
    }

    public func make(_ kind: TypeKind) -> TypeID {
        if let existing = kindToID[kind] {
            return existing
        }
        let id = TypeID(rawValue: Int32(idToKind.count))
        idToKind.append(kind)
        kindToID[kind] = id
        return id
    }

    public func kind(of id: TypeID) -> TypeKind {
        let index = Int(id.rawValue)
        guard index >= 0 && index < idToKind.count else {
            return .error
        }
        return idToKind[index]
    }

    public func setNominalDirectSupertypes(_ supertypes: [SymbolID], for symbol: SymbolID) {
        let unique = Array(Set(supertypes)).sorted(by: { $0.rawValue < $1.rawValue })
        nominalDirectSupertypes[symbol] = unique
    }

    public func directNominalSupertypes(for symbol: SymbolID) -> [SymbolID] {
        nominalDirectSupertypes[symbol] ?? []
    }

    public func setNominalTypeParameterVariances(_ variances: [TypeVariance], for symbol: SymbolID) {
        nominalTypeParameterVariancesMap[symbol] = variances
    }

    public func nominalTypeParameterVariances(for symbol: SymbolID) -> [TypeVariance] {
        nominalTypeParameterVariancesMap[symbol] ?? []
    }

    public func setNominalTypeParameterSymbols(_ symbols: [SymbolID], for nominal: SymbolID) {
        nominalTypeParameterSymbolsMap[nominal] = symbols
    }

    public func nominalTypeParameterSymbols(for nominal: SymbolID) -> [SymbolID] {
        nominalTypeParameterSymbolsMap[nominal] ?? []
    }

    /// Returns `true` when `type` structurally contains a reference to the
    /// type parameter identified by `symbol`.
    public func typeContainsTypeParam(_ type: TypeID, symbol: SymbolID) -> Bool {
        switch kind(of: type) {
        case .typeParam(let tp):
            return tp.symbol == symbol
        case .classType(let ct):
            return ct.args.contains { arg in
                switch arg {
                case .invariant(let inner), .out(let inner), .in(let inner):
                    return typeContainsTypeParam(inner, symbol: symbol)
                case .star:
                    return false
                }
            }
        case .functionType(let ft):
            if let receiver = ft.receiver, typeContainsTypeParam(receiver, symbol: symbol) {
                return true
            }
            if ft.params.contains(where: { typeContainsTypeParam($0, symbol: symbol) }) {
                return true
            }
            return typeContainsTypeParam(ft.returnType, symbol: symbol)
        case .intersection(let parts):
            return parts.contains { typeContainsTypeParam($0, symbol: symbol) }
        default:
            return false
        }
    }

    public func setNominalSupertypeTypeArgs(_ args: [TypeArg], for child: SymbolID, supertype parent: SymbolID) {
        nominalSupertypeTypeArgsMap[child, default: [:]][parent] = args
    }

    public func nominalSupertypeTypeArgs(for child: SymbolID, supertype parent: SymbolID) -> [TypeArg] {
        nominalSupertypeTypeArgsMap[child]?[parent] ?? []
    }
}
