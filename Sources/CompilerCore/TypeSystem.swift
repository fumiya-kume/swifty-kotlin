public final class TypeSystem {
    private var kindToID: [TypeKind: TypeID] = [:]
    private var idToKind: [TypeKind] = []
    private var nominalDirectSupertypes: [SymbolID: [SymbolID]] = [:]
    private var nominalTypeParameterVariancesMap: [SymbolID: [TypeVariance]] = [:]
    private var nominalSupertypeTypeArgsMap: [SymbolID: [SymbolID: [TypeArg]]] = [:]

    public let errorType: TypeID
    public let unitType: TypeID
    public let nothingType: TypeID
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
        self.anyType = TypeID(rawValue: 3)
        self.nullableAnyType = TypeID(rawValue: 4)
        self.booleanType = TypeID(rawValue: 5)
        self.charType = TypeID(rawValue: 6)
        self.intType = TypeID(rawValue: 7)
        self.longType = TypeID(rawValue: 8)
        self.floatType = TypeID(rawValue: 9)
        self.doubleType = TypeID(rawValue: 10)
        self.stringType = TypeID(rawValue: 11)

        idToKind = [
            .error,
            .unit,
            .nothing,
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
            .nothing: nothingType,
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
        case .error, .unit, .nothing, .intersection:
            return type
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

    public func setNominalSupertypeTypeArgs(_ args: [TypeArg], for child: SymbolID, supertype parent: SymbolID) {
        nominalSupertypeTypeArgsMap[child, default: [:]][parent] = args
    }

    public func nominalSupertypeTypeArgs(for child: SymbolID, supertype parent: SymbolID) -> [TypeArg] {
        nominalSupertypeTypeArgsMap[child]?[parent] ?? []
    }
}
