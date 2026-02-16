public struct TypeID: Hashable {
    public let rawValue: Int32

    public static let invalid = TypeID(rawValue: -1)

    public init(rawValue: Int32 = -1) {
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

public enum TypeVariance: Hashable {
    case invariant
    case out
    case `in`
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
    private var nominalTypeParameterVariances: [SymbolID: [TypeVariance]] = [:]

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

    public func setNominalTypeParameterVariances(_ variances: [TypeVariance], for symbol: SymbolID) {
        nominalTypeParameterVariances[symbol] = variances
    }

    public func nominalTypeParameterVariances(for symbol: SymbolID) -> [TypeVariance] {
        nominalTypeParameterVariances[symbol] ?? []
    }

    public func isSubtype(_ subtype: TypeID, _ supertype: TypeID) -> Bool {
        if subtype == supertype {
            return true
        }

        let lhs = kind(of: subtype)
        let rhs = kind(of: supertype)

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
                return parts.allSatisfy { isSubtype($0, supertype) }
            default:
                return false
            }
        }

        switch (lhs, rhs) {
        case (.any(.nonNull), .any(.nullable)):
            return true

        case let (.primitive(leftPrimitive, leftNullability), .primitive(rightPrimitive, rightNullability)):
            return leftPrimitive == rightPrimitive && nullabilitySubtype(leftNullability, rightNullability)

        case let (.classType(leftClass), .classType(rightClass)):
            guard nullabilitySubtype(leftClass.nullability, rightClass.nullability) else {
                return false
            }
            if leftClass.classSymbol != rightClass.classSymbol {
                guard isNominalSubtypeSymbol(leftClass.classSymbol, of: rightClass.classSymbol) else {
                    return false
                }
                return rightClass.args.isEmpty || rightClass.args.allSatisfy { arg in
                    if case .star = arg {
                        return true
                    }
                    return false
                }
            }
            if leftClass.args.count != rightClass.args.count {
                return false
            }
            let declarationVariances = normalizedNominalVariances(
                for: leftClass.classSymbol,
                arity: leftClass.args.count
            )
            for index in 0..<leftClass.args.count {
                let lhsProjection = composedProjection(
                    declarationVariance: declarationVariances[index],
                    useSite: leftClass.args[index]
                )
                let rhsProjection = composedProjection(
                    declarationVariance: declarationVariances[index],
                    useSite: rightClass.args[index]
                )
                if !isProjectionSubtype(lhsProjection, rhsProjection) {
                    return false
                }
            }
            return true

        case let (.functionType(leftFunction), .functionType(rightFunction)):
            guard leftFunction.params.count == rightFunction.params.count else {
                return false
            }
            guard leftFunction.isSuspend == rightFunction.isSuspend else {
                return false
            }
            guard nullabilitySubtype(leftFunction.nullability, rightFunction.nullability) else {
                return false
            }
            if let lReceiver = leftFunction.receiver, let rReceiver = rightFunction.receiver {
                if !isSubtype(rReceiver, lReceiver) {
                    return false
                }
            } else if leftFunction.receiver != nil || rightFunction.receiver != nil {
                return false
            }
            for (leftParam, rightParam) in zip(leftFunction.params, rightFunction.params) {
                if !isSubtype(rightParam, leftParam) {
                    return false
                }
            }
            return isSubtype(leftFunction.returnType, rightFunction.returnType)

        case let (.intersection(parts), _):
            return parts.allSatisfy { isSubtype($0, supertype) }

        case let (_, .intersection(parts)):
            return parts.contains { isSubtype(subtype, $0) }

        case (.any(let leftNullability), .any(let rightNullability)):
            return nullabilitySubtype(leftNullability, rightNullability)

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

    @available(*, deprecated, message: "Use lub(_:) instead.")
    public func leastUpperBound(_ types: [TypeID]) -> TypeID {
        lub(types)
    }

    @available(*, deprecated, message: "Use glb(_:) instead.")
    public func greatestLowerBound(_ types: [TypeID]) -> TypeID {
        glb(types)
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

    private enum Projection {
        case invariant(TypeID)
        case out(TypeID)
        case `in`(TypeID)
        case star
        case invalid
    }

    private func normalizedNominalVariances(for symbol: SymbolID, arity: Int) -> [TypeVariance] {
        let stored = nominalTypeParameterVariances[symbol] ?? []
        if stored.count >= arity {
            return Array(stored.prefix(arity))
        }
        if stored.isEmpty {
            return Array(repeating: .invariant, count: arity)
        }
        return stored + Array(repeating: .invariant, count: arity - stored.count)
    }

    private func composedProjection(
        declarationVariance: TypeVariance,
        useSite: TypeArg
    ) -> Projection {
        switch declarationVariance {
        case .invariant:
            return projection(from: useSite)
        case .out:
            switch useSite {
            case .invariant(let type):
                return .out(type)
            case .out(let type):
                return .out(type)
            case .star:
                return .star
            case .in:
                return .invalid
            }
        case .in:
            switch useSite {
            case .invariant(let type):
                return .in(type)
            case .in(let type):
                return .in(type)
            case .star:
                return .star
            case .out:
                return .invalid
            }
        }
    }

    private func projection(from arg: TypeArg) -> Projection {
        switch arg {
        case .invariant(let type):
            return .invariant(type)
        case .out(let type):
            return .out(type)
        case .in(let type):
            return .in(type)
        case .star:
            return .star
        }
    }

    private func isProjectionSubtype(_ lhs: Projection, _ rhs: Projection) -> Bool {
        switch rhs {
        case .star:
            return true
        case .invalid:
            return false
        default:
            break
        }
        switch lhs {
        case .invalid, .star:
            return false
        default:
            break
        }

        switch (lhs, rhs) {
        case let (.invariant(la), .invariant(ra)):
            return isSubtype(la, ra) && isSubtype(ra, la)
        case let (.invariant(la), .out(ra)):
            return isSubtype(la, ra)
        case let (.invariant(la), .in(ra)):
            return isSubtype(ra, la)
        case let (.out(la), .out(ra)):
            return isSubtype(la, ra)
        case let (.in(la), .in(ra)):
            return isSubtype(ra, la)
        default:
            return false
        }
    }

    func renderType(_ type: TypeID) -> String {
        switch kind(of: type) {
        case .error:
            return "<error>"
        case .unit:
            return "Unit"
        case .nothing:
            return "Nothing"
        case .any(let nullability):
            return nullability == .nullable ? "Any?" : "Any"
        case .primitive(let primitive, let nullability):
            let base: String
            switch primitive {
            case .boolean:
                base = "Boolean"
            case .char:
                base = "Char"
            case .int:
                base = "Int"
            case .long:
                base = "Long"
            case .float:
                base = "Float"
            case .double:
                base = "Double"
            case .string:
                base = "String"
            }
            return nullability == .nullable ? "\(base)?" : base
        case .classType(let classType):
            let args: String
            if classType.args.isEmpty {
                args = ""
            } else {
                args = "<" + classType.args.map(renderTypeArg).joined(separator: ", ") + ">"
            }
            let nullSuffix = classType.nullability == .nullable ? "?" : ""
            return "Class#\(classType.classSymbol.rawValue)\(args)\(nullSuffix)"
        case .typeParam(let typeParam):
            let nullSuffix = typeParam.nullability == .nullable ? "?" : ""
            return "T#\(typeParam.symbol.rawValue)\(nullSuffix)"
        case .functionType(let functionType):
            let receiverPrefix: String
            if let receiver = functionType.receiver {
                receiverPrefix = "\(renderType(receiver))."
            } else {
                receiverPrefix = ""
            }
            let suspendPrefix = functionType.isSuspend ? "suspend " : ""
            let params = functionType.params.map(renderType).joined(separator: ", ")
            let nullSuffix = functionType.nullability == .nullable ? "?" : ""
            return "\(suspendPrefix)\(receiverPrefix)(\(params)) -> \(renderType(functionType.returnType))\(nullSuffix)"
        case .intersection(let parts):
            return parts.map(renderType).joined(separator: " & ")
        }
    }

    private func renderTypeArg(_ arg: TypeArg) -> String {
        switch arg {
        case .invariant(let type):
            return renderType(type)
        case .out(let type):
            return "out \(renderType(type))"
        case .in(let type):
            return "in \(renderType(type))"
        case .star:
            return "*"
        }
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
