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

        switch (lhs, rhs) {
        case (.any(.nonNull), .any(.nullable)):
            return true

        case let (.primitive(lp, ln), .primitive(rp, rn)):
            return lp == rp && nullabilitySubtype(ln, rn)

        case let (.classType(lt), .classType(rt)):
            if lt.classSymbol != rt.classSymbol || lt.args.count != rt.args.count {
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
}
