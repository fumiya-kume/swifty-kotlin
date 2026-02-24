public struct ASTNodeID: Hashable, Sendable {
    public let rawValue: Int32

    public static let invalid = ASTNodeID(rawValue: -1)

    public init(rawValue: Int32 = -1) {
        self.rawValue = rawValue
    }
}

public struct ExprID: Hashable, Sendable {
    public let rawValue: Int32

    public static let invalid = ExprID(rawValue: -1)

    public init(rawValue: Int32 = -1) {
        self.rawValue = rawValue
    }
}

public struct TypeRefID: Hashable, Sendable {
    public let rawValue: Int32

    public static let invalid = TypeRefID(rawValue: -1)

    public init(rawValue: Int32 = -1) {
        self.rawValue = rawValue
    }
}

public enum Visibility: Int {
    case `public`
    case `private`
    case `internal`
    case `protected`
}

public struct Modifiers: OptionSet, Sendable {
    public let rawValue: Int32

    public init(rawValue: Int32) { self.rawValue = rawValue }
    public static let `public` = Modifiers(rawValue: Int32(1) << 0)
    public static let `internal` = Modifiers(rawValue: Int32(1) << 1)
    public static let `private` = Modifiers(rawValue: Int32(1) << 2)
    public static let `protected` = Modifiers(rawValue: Int32(1) << 3)
    public static let final = Modifiers(rawValue: Int32(1) << 4)
    public static let open = Modifiers(rawValue: Int32(1) << 5)
    public static let abstract = Modifiers(rawValue: Int32(1) << 6)
    public static let sealed = Modifiers(rawValue: Int32(1) << 7)
    public static let `data` = Modifiers(rawValue: Int32(1) << 8)
    public static let annotationClass = Modifiers(rawValue: Int32(1) << 9)
    public static let `inline` = Modifiers(rawValue: Int32(1) << 10)
    public static let suspend = Modifiers(rawValue: Int32(1) << 11)
    public static let tailrec = Modifiers(rawValue: Int32(1) << 12)
    public static let `operator` = Modifiers(rawValue: Int32(1) << 13)
    public static let infix = Modifiers(rawValue: Int32(1) << 14)
    public static let crossinline = Modifiers(rawValue: Int32(1) << 15)
    public static let noinline = Modifiers(rawValue: Int32(1) << 16)
    public static let vararg = Modifiers(rawValue: Int32(1) << 17)
    public static let external = Modifiers(rawValue: Int32(1) << 18)
    public static let expect = Modifiers(rawValue: Int32(1) << 19)
    public static let actual = Modifiers(rawValue: Int32(1) << 20)
    public static let value = Modifiers(rawValue: Int32(1) << 21)
    public static let enumModifier = Modifiers(rawValue: Int32(1) << 22)
    public static let inner = Modifiers(rawValue: Int32(1) << 23)
}

public enum Decl {
    case classDecl(ClassDecl)
    case interfaceDecl(InterfaceDecl)
    case funDecl(FunDecl)
    case propertyDecl(PropertyDecl)
    case typeAliasDecl(TypeAliasDecl)
    case objectDecl(ObjectDecl)
    case enumEntryDecl(EnumEntryDecl)
}
