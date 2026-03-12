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
    case uint
    case ulong
    case ubyte
    case ushort
}

public extension PrimitiveType {
    /// The Kotlin source-level name for this primitive type.
    var kotlinName: String {
        switch self {
        case .boolean: "Boolean"
        case .char: "Char"
        case .int: "Int"
        case .long: "Long"
        case .float: "Float"
        case .double: "Double"
        case .string: "String"
        case .uint: "UInt"
        case .ulong: "ULong"
        case .ubyte: "UByte"
        case .ushort: "UShort"
        }
    }
}

public enum Nullability: Hashable, Sendable {
    case nonNull
    case nullable
    case platformType // T! — nullability unknown (from external declarations)

    /// Nullability used by metadata/signature encodings that only support
    /// two states (non-null / nullable). Platform types are erased to nullable.
    public var erasedForMetadata: Nullability {
        switch self {
        case .nonNull:
            .nonNull
        case .nullable, .platformType:
            .nullable
        }
    }
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
