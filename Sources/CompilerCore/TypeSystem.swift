public struct TypeID: Hashable {
    public let rawValue: Int32

    public init(rawValue: Int32 = invalidID) {
        self.rawValue = rawValue
    }
}

public enum PrimitiveType: String, Hashable {
    case boolean
    case char
    case int
    case long
    case float
    case double
    case string
}

public enum Nullability: Hashable {
    case nonNull
    case nullable
}

public struct ClassType: Hashable {
    public let classSymbol: SymbolID
    public let args: [TypeArg]
    public let nullability: Nullability

    public init(classSymbol: SymbolID, args: [TypeArg] = [], nullability: Nullability = .nonNull) {
        self.classSymbol = classSymbol
        self.args = args
        self.nullability = nullability
    }
}

public enum TypeArg: Hashable {
    case invariant(TypeID)
    case out(TypeID)
    case `in`(TypeID)
    case star
}

public struct TypeParamType: Hashable {
    public let symbol: SymbolID
    public let nullability: Nullability

    public init(symbol: SymbolID, nullability: Nullability = .nonNull) {
        self.symbol = symbol
        self.nullability = nullability
    }
}

public struct FunctionType: Hashable {
    public let receiver: TypeID?
    public let params: [TypeID]
    public let returnType: TypeID
    public let isSuspend: Bool
    public let nullability: Nullability

    public init(
        receiver: TypeID? = nil,
        params: [TypeID],
        returnType: TypeID,
        isSuspend: Bool = false,
        nullability: Nullability = .nonNull
    ) {
        self.receiver = receiver
        self.params = params
        self.returnType = returnType
        self.isSuspend = isSuspend
        self.nullability = nullability
    }
}

public enum TypeKind: Hashable {
    case error
    case unit
    case nothing
    case any(Nullability)

    case primitive(PrimitiveType, Nullability)
    case classType(ClassType)
    case typeParam(TypeParamType)
    case functionType(FunctionType)
    case intersection([TypeID])
}

public final class TypeSystem {
    private var kindToID: [TypeKind: TypeID] = [:]
    private var idToKind: [TypeKind] = []
    private var nominalDirectSupertypes: [SymbolID: [SymbolID]] = [:]

    public let errorType: TypeID
    public let unitType: TypeID
    public let nothingType: TypeID
    public let anyType: TypeID
    public let nullableAnyType: TypeID

    public init() {
        self.errorType = TypeID(rawValue: 0)
        self.unitType = TypeID(rawValue: 1)
        self.nothingType = TypeID(rawValue: 2)
        self.anyType = TypeID(rawValue: 3)
        self.nullableAnyType = TypeID(rawValue: 4)

        idToKind = [
            .error,
            .unit,
            .nothing,
            .any(.nonNull),
            .any(.nullable)
        ]
        kindToID = [
            .error: errorType,
            .unit: unitType,
            .nothing: nothingType,
            .any(.nonNull): anyType,
            .any(.nullable): nullableAnyType
        ]
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

    public func isSubtype(_ a: TypeID, _ b: TypeID) -> Bool {
        if a == b {
            return true
        }

        let lhs = kind(of: a)
        let rhs = kind(of: b)

        if case .nothing = lhs {
            return true
        }
        if case .error = lhs {
            return true
        }
        if case .error = rhs {
            return true
        }
        if case .any(.nullable) = rhs {
            return true
        }
        if case .any(.nonNull) = rhs {
            switch lhs {
            case .any(.nonNull), .unit, .nothing:
                return true
            case .primitive(_, let nullability):
                return nullability == .nonNull
            case .classType(let classType):
                return classType.nullability == .nonNull
            case .functionType(let functionType):
                return functionType.nullability == .nonNull
            case .typeParam(let typeParam):
                return typeParam.nullability == .nonNull
            case .intersection(let parts):
                return parts.allSatisfy { isSubtype($0, b) }
            default:
                return false
            }
        }

        switch (lhs, rhs) {
        case (.any(.nonNull), .any(.nullable)):
            return true

        case let (.primitive(lp, ln), .primitive(rp, rn)):
            return lp == rp && nullabilitySubtype(ln, rn)

        case let (.classType(lt), .classType(rt)):
            if lt.classSymbol != rt.classSymbol {
                guard isNominalSubtypeSymbol(lt.classSymbol, of: rt.classSymbol) else {
                    return false
                }
                return rt.args.isEmpty || rt.args.allSatisfy { arg in
                    if case .star = arg {
                        return true
                    }
                    return false
                }
            }
            if lt.args.count != rt.args.count {
                return false
            }
            guard nullabilitySubtype(lt.nullability, rt.nullability) else {
                return false
            }
            for (lhsArg, rhsArg) in zip(lt.args, rt.args) {
                switch (lhsArg, rhsArg) {
                case let (.invariant(la), .invariant(ra)):
                    if !isSubtype(la, ra) || !isSubtype(ra, la) {
                        return false
                    }
                case let (.out(la), .out(ra)):
                    if !isSubtype(la, ra) {
                        return false
                    }
                case let (.in(la), .in(ra)):
                    if !isSubtype(ra, la) {
                        return false
                    }
                case (.star, .star):
                    continue
                default:
                    return false
                }
            }
            return true

        case let (.functionType(lf), .functionType(rf)):
            guard lf.params.count == rf.params.count else {
                return false
            }
            guard lf.isSuspend == rf.isSuspend else {
                return false
            }
            guard nullabilitySubtype(lf.nullability, rf.nullability) else {
                return false
            }
            if let lReceiver = lf.receiver, let rReceiver = rf.receiver {
                if !isSubtype(rReceiver, lReceiver) {
                    return false
                }
            } else if lf.receiver != nil || rf.receiver != nil {
                return false
            }
            for (lp, rp) in zip(lf.params, rf.params) {
                if !isSubtype(rp, lp) {
                    return false
                }
            }
            return isSubtype(lf.returnType, rf.returnType)

        case let (.intersection(parts), _):
            return parts.allSatisfy { isSubtype($0, b) }

        case let (_, .intersection(parts)):
            return parts.contains { isSubtype(a, $0) }

        case (.any(let ln), .any(let rn)):
            return nullabilitySubtype(ln, rn)

        default:
            return false
        }
    }

    public func lub(_ types: [TypeID]) -> TypeID {
        let filtered = types.filter { kind(of: $0) != .error }
        guard let first = filtered.first else {
            return errorType
        }
        if filtered.dropFirst().allSatisfy({ $0 == first }) {
            return first
        }
        if filtered.allSatisfy({ isSubtype($0, nullableAnyType) }) {
            return nullableAnyType
        }
        return anyType
    }

    public func glb(_ types: [TypeID]) -> TypeID {
        guard let first = types.first else {
            return errorType
        }
        if types.dropFirst().allSatisfy({ $0 == first }) {
            return first
        }
        if types.contains(where: { kind(of: $0) == .nothing }) {
            return nothingType
        }
        return make(.intersection(types))
    }

    private func nullabilitySubtype(_ lhs: Nullability, _ rhs: Nullability) -> Bool {
        if lhs == rhs {
            return true
        }
        return lhs == .nonNull && rhs == .nullable
    }

    private func isNominalSubtypeSymbol(_ candidate: SymbolID, of base: SymbolID) -> Bool {
        if candidate == base {
            return true
        }
        var queue = directNominalSupertypes(for: candidate)
        var visited: Set<SymbolID> = [candidate]
        while let current = queue.first {
            queue.removeFirst()
            if current == base {
                return true
            }
            if visited.insert(current).inserted {
                queue.append(contentsOf: directNominalSupertypes(for: current))
            }
        }
        return false
    }

    public func makeTypeVarBySymbol(_ symbols: [SymbolID]) -> [SymbolID: TypeVarID] {
        var mapping: [SymbolID: TypeVarID] = [:]
        var index: Int32 = 0
        for symbol in symbols {
            mapping[symbol] = TypeVarID(rawValue: index)
            index += 1
        }
        return mapping
    }

    public func substituteTypeParameters(
        in type: TypeID,
        substitution: [TypeVarID: TypeID],
        typeVarBySymbol: [SymbolID: TypeVarID]
    ) -> TypeID {
        let kind = kind(of: type)
        switch kind {
        case .typeParam(let typeParam):
            if let variable = typeVarBySymbol[typeParam.symbol],
               let concrete = substitution[variable] {
                return concrete
            }
            return type

        case .classType(let classType):
            let newArgs: [TypeArg] = classType.args.map { arg in
                switch arg {
                case .invariant(let inner):
                    return .invariant(substituteTypeParameters(
                        in: inner,
                        substitution: substitution,
                        typeVarBySymbol: typeVarBySymbol
                    ))
                case .out(let inner):
                    return .out(substituteTypeParameters(
                        in: inner,
                        substitution: substitution,
                        typeVarBySymbol: typeVarBySymbol
                    ))
                case .in(let inner):
                    return .in(substituteTypeParameters(
                        in: inner,
                        substitution: substitution,
                        typeVarBySymbol: typeVarBySymbol
                    ))
                case .star:
                    return .star
                }
            }
            if newArgs == classType.args {
                return type
            }
            return make(.classType(ClassType(
                classSymbol: classType.classSymbol,
                args: newArgs,
                nullability: classType.nullability
            )))

        case .functionType(let functionType):
            let newReceiver = functionType.receiver.map { receiver in
                substituteTypeParameters(
                    in: receiver,
                    substitution: substitution,
                    typeVarBySymbol: typeVarBySymbol
                )
            }
            let newParams = functionType.params.map { param in
                substituteTypeParameters(
                    in: param,
                    substitution: substitution,
                    typeVarBySymbol: typeVarBySymbol
                )
            }
            let newReturn = substituteTypeParameters(
                in: functionType.returnType,
                substitution: substitution,
                typeVarBySymbol: typeVarBySymbol
            )
            if newReceiver == functionType.receiver &&
                newParams == functionType.params &&
                newReturn == functionType.returnType {
                return type
            }
            return make(.functionType(FunctionType(
                receiver: newReceiver,
                params: newParams,
                returnType: newReturn,
                isSuspend: functionType.isSuspend,
                nullability: functionType.nullability
            )))

        case .intersection(let parts):
            let newParts = parts.map { part in
                substituteTypeParameters(
                    in: part,
                    substitution: substitution,
                    typeVarBySymbol: typeVarBySymbol
                )
            }
            if newParts == parts {
                return type
            }
            return make(.intersection(newParts))

        default:
            return type
        }
    }
}
