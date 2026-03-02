public struct TypeID: Hashable, Sendable {
    public let rawValue: Int32

    public static let invalid = TypeID(rawValue: -1)

    public init(rawValue: Int32 = -1) {
        self.rawValue = rawValue
    }
}

public enum PrimitiveType: String, Hashable, Sendable {
    case boolean
    case char
    case int
    case long
    case float
    case double
    case string
}

public enum Nullability: Hashable, Sendable {
    case nonNull
    case nullable
}

public struct ClassType: Hashable, Sendable {
    public let classSymbol: SymbolID
    public let args: [TypeArg]
    public let nullability: Nullability

    public init(classSymbol: SymbolID, args: [TypeArg] = [], nullability: Nullability = .nonNull) {
        self.classSymbol = classSymbol
        self.args = args
        self.nullability = nullability
    }
}

public enum TypeVariance: Hashable, Sendable {
    case invariant
    case out
    case `in`
}

public enum TypeArg: Hashable, Sendable {
    case invariant(TypeID)
    case out(TypeID)
    case `in`(TypeID)
    case star
}

public struct TypeParamType: Hashable, Sendable {
    public let symbol: SymbolID
    public let nullability: Nullability

    public init(symbol: SymbolID, nullability: Nullability = .nonNull) {
        self.symbol = symbol
        self.nullability = nullability
    }
}

public struct FunctionType: Hashable, Sendable {
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
    case nothing(Nullability)
    case any(Nullability)

    case primitive(PrimitiveType, Nullability)
    case classType(ClassType)
    case typeParam(TypeParamType)
    case functionType(FunctionType)
    case intersection([TypeID])
}
