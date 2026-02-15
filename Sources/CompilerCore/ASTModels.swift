public struct ASTNodeID: Hashable {
    public let rawValue: Int32

    public init(rawValue: Int32 = invalidID) {
        self.rawValue = rawValue
    }
}

public struct ExprID: Hashable {
    public let rawValue: Int32

    public init(rawValue: Int32 = invalidID) {
        self.rawValue = rawValue
    }
}

public struct TypeRefID: Hashable {
    public let rawValue: Int32

    public init(rawValue: Int32 = invalidID) {
        self.rawValue = rawValue
    }
}

public enum Visibility: Int {
    case `public`
    case `private`
    case `internal`
    case `protected`
}

public struct Modifiers: OptionSet {
    public let rawValue: Int32

    public init(rawValue: Int32) { self.rawValue = rawValue }
    public static let publicModifier = Modifiers(rawValue: Int32(1) << 0)
    public static let internalModifier = Modifiers(rawValue: Int32(1) << 1)
    public static let privateModifier = Modifiers(rawValue: Int32(1) << 2)
    public static let protectedModifier = Modifiers(rawValue: Int32(1) << 3)
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
}

public enum Decl {
    case classDecl(ClassDecl)
    case funDecl(FunDecl)
    case propertyDecl(PropertyDecl)
    case typeAliasDecl(TypeAliasDecl)
    case objectDecl(ObjectDecl)
    case enumEntry(EnumEntryDecl)
}

public struct ASTFile {
    public let fileID: FileID
    public let packageFQName: [InternedString]
    public let imports: [ImportDecl]
    public let topLevelDecls: [DeclID]
}

public struct ClassDecl {
    public let range: SourceRange
    public let name: InternedString
    public let modifiers: Modifiers
    public let typeParams: [TypeParamDecl]
    public let primaryConstructorParams: [ValueParamDecl]
}

public struct ObjectDecl {
    public let range: SourceRange
    public let name: InternedString
    public let modifiers: Modifiers
}

public struct FunDecl {
    public let range: SourceRange
    public let name: InternedString
    public let modifiers: Modifiers
    public let typeParams: [TypeParamDecl]
    public let receiverType: TypeRefID?
    public let valueParams: [ValueParamDecl]
    public let returnType: TypeRefID?
    public let body: FunctionBody
    public let isSuspend: Bool
    public let isInline: Bool

    public init(
        range: SourceRange,
        name: InternedString,
        modifiers: Modifiers,
        typeParams: [TypeParamDecl] = [],
        receiverType: TypeRefID? = nil,
        valueParams: [ValueParamDecl] = [],
        returnType: TypeRefID? = nil,
        body: FunctionBody = .unit,
        isSuspend: Bool = false,
        isInline: Bool = false
    ) {
        self.range = range
        self.name = name
        self.modifiers = modifiers
        self.typeParams = typeParams
        self.receiverType = receiverType
        self.valueParams = valueParams
        self.returnType = returnType
        self.body = body
        self.isSuspend = isSuspend
        self.isInline = isInline
    }
}

public enum FunctionBody: Equatable {
    case block([ExprID], SourceRange)
    case expr(ExprID, SourceRange)
    case unit
}

public struct PropertyDecl {
    public let range: SourceRange
    public let name: InternedString
    public let modifiers: Modifiers
    public let type: TypeRefID?
}

public struct TypeAliasDecl {
    public let range: SourceRange
    public let name: InternedString
    public let modifiers: Modifiers
}

public struct EnumEntryDecl {
    public let range: SourceRange
    public let name: InternedString
}

public struct ImportDecl {
    public let range: SourceRange
    public let path: [InternedString]
}

public struct TypeParamDecl {
    public let name: InternedString
}

public struct ValueParamDecl {
    public let name: InternedString
    public let type: TypeRefID?
}

public enum BinaryOp: Equatable {
    case add
    case subtract
    case multiply
    case divide
    case equal
}

public struct WhenBranch: Equatable {
    public let condition: ExprID?
    public let body: ExprID
    public let range: SourceRange

    public init(condition: ExprID?, body: ExprID, range: SourceRange) {
        self.condition = condition
        self.body = body
        self.range = range
    }
}

public enum Expr: Equatable {
    case intLiteral(Int64, SourceRange)
    case boolLiteral(Bool, SourceRange)
    case stringLiteral(InternedString, SourceRange)
    case nameRef(InternedString, SourceRange)
    case call(callee: ExprID, args: [ExprID], range: SourceRange)
    case binary(op: BinaryOp, lhs: ExprID, rhs: ExprID, range: SourceRange)
    case whenExpr(subject: ExprID, branches: [WhenBranch], elseExpr: ExprID?, range: SourceRange)
}

public final class ASTArena {
    public private(set) var decls: [Decl] = []
    public private(set) var exprs: [Expr] = []

    public init() {}

    public func appendDecl(_ decl: Decl) -> DeclID {
        let id = Int32(decls.count)
        decls.append(decl)
        return DeclID(rawValue: id)
    }

    public func decl(_ id: DeclID) -> Decl? {
        let index = Int(id.rawValue)
        if index < 0 || index >= decls.count {
            return nil
        }
        return decls[index]
    }

    public func declarations() -> [Decl] {
        return decls
    }

    public func appendExpr(_ expr: Expr) -> ExprID {
        let id = ExprID(rawValue: Int32(exprs.count))
        exprs.append(expr)
        return id
    }

    public func expr(_ id: ExprID) -> Expr? {
        let index = Int(id.rawValue)
        if index < 0 || index >= exprs.count {
            return nil
        }
        return exprs[index]
    }

    public func exprRange(_ id: ExprID) -> SourceRange? {
        guard let expr = expr(id) else {
            return nil
        }
        switch expr {
        case .intLiteral(_, let range),
             .boolLiteral(_, let range),
             .stringLiteral(_, let range),
             .nameRef(_, let range),
             .call(_, _, let range),
             .binary(_, _, _, let range),
             .whenExpr(_, _, _, let range):
            return range
        }
    }
}

public final class ASTModule {
    public let files: [ASTFile]
    public let arena: ASTArena
    public let declarationCount: Int
    public let tokenCount: Int

    public init(files: [ASTFile], arena: ASTArena, declarationCount: Int, tokenCount: Int) {
        self.files = files
        self.arena = arena
        self.declarationCount = declarationCount
        self.tokenCount = tokenCount
    }

    public convenience init(declarationCount: Int, tokenCount: Int) {
        self.init(files: [], arena: ASTArena(), declarationCount: declarationCount, tokenCount: tokenCount)
    }
}
