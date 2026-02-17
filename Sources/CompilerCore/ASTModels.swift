public struct ASTNodeID: Hashable {
    public let rawValue: Int32

    public static let invalid = ASTNodeID(rawValue: -1)

    public init(rawValue: Int32 = -1) {
        self.rawValue = rawValue
    }
}

public struct ExprID: Hashable {
    public let rawValue: Int32

    public static let invalid = ExprID(rawValue: -1)

    public init(rawValue: Int32 = -1) {
        self.rawValue = rawValue
    }
}

public struct TypeRefID: Hashable {
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

public struct Modifiers: OptionSet {
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

public struct ASTFile {
    public let fileID: FileID
    public let packageFQName: [InternedString]
    public let imports: [ImportDecl]
    public let topLevelDecls: [DeclID]
    public let scriptBody: [ExprID]
}

public enum ConstructorDelegationKind: Equatable {
    case this
    case super_
}

public struct ConstructorDelegationCall: Equatable {
    public let kind: ConstructorDelegationKind
    public let args: [CallArgument]
    public let range: SourceRange

    public init(kind: ConstructorDelegationKind, args: [CallArgument], range: SourceRange) {
        self.kind = kind
        self.args = args
        self.range = range
    }
}

public struct ConstructorDecl {
    public let range: SourceRange
    public let modifiers: Modifiers
    public let valueParams: [ValueParamDecl]
    public let delegationCall: ConstructorDelegationCall?
    public let body: FunctionBody

    public init(
        range: SourceRange,
        modifiers: Modifiers = [],
        valueParams: [ValueParamDecl] = [],
        delegationCall: ConstructorDelegationCall? = nil,
        body: FunctionBody = .unit
    ) {
        self.range = range
        self.modifiers = modifiers
        self.valueParams = valueParams
        self.delegationCall = delegationCall
        self.body = body
    }
}

public struct ClassDecl {
    public let range: SourceRange
    public let name: InternedString
    public let modifiers: Modifiers
    public let typeParams: [TypeParamDecl]
    public let primaryConstructorParams: [ValueParamDecl]
    public let superTypes: [TypeRefID]
    public let nestedTypeAliases: [TypeAliasDecl]
    public let enumEntries: [EnumEntryDecl]
    public let initBlocks: [FunctionBody]
    public let secondaryConstructors: [ConstructorDecl]
    public let memberFunctions: [DeclID]
    public let memberProperties: [DeclID]
    public let nestedClasses: [DeclID]
    public let nestedObjects: [DeclID]

    public init(
        range: SourceRange,
        name: InternedString,
        modifiers: Modifiers,
        typeParams: [TypeParamDecl] = [],
        primaryConstructorParams: [ValueParamDecl] = [],
        superTypes: [TypeRefID] = [],
        nestedTypeAliases: [TypeAliasDecl] = [],
        enumEntries: [EnumEntryDecl] = [],
        initBlocks: [FunctionBody] = [],
        secondaryConstructors: [ConstructorDecl] = [],
        memberFunctions: [DeclID] = [],
        memberProperties: [DeclID] = [],
        nestedClasses: [DeclID] = [],
        nestedObjects: [DeclID] = []
    ) {
        self.range = range
        self.name = name
        self.modifiers = modifiers
        self.typeParams = typeParams
        self.primaryConstructorParams = primaryConstructorParams
        self.superTypes = superTypes
        self.nestedTypeAliases = nestedTypeAliases
        self.enumEntries = enumEntries
        self.initBlocks = initBlocks
        self.secondaryConstructors = secondaryConstructors
        self.memberFunctions = memberFunctions
        self.memberProperties = memberProperties
        self.nestedClasses = nestedClasses
        self.nestedObjects = nestedObjects
    }
}

public struct InterfaceDecl {
    public let range: SourceRange
    public let name: InternedString
    public let modifiers: Modifiers
    public let typeParams: [TypeParamDecl]
    public let superTypes: [TypeRefID]
    public let nestedTypeAliases: [TypeAliasDecl]

    public init(
        range: SourceRange,
        name: InternedString,
        modifiers: Modifiers,
        typeParams: [TypeParamDecl] = [],
        superTypes: [TypeRefID] = [],
        nestedTypeAliases: [TypeAliasDecl] = []
    ) {
        self.range = range
        self.name = name
        self.modifiers = modifiers
        self.typeParams = typeParams
        self.superTypes = superTypes
        self.nestedTypeAliases = nestedTypeAliases
    }
}

public struct ObjectDecl {
    public let range: SourceRange
    public let name: InternedString
    public let modifiers: Modifiers
    public let superTypes: [TypeRefID]
    public let nestedTypeAliases: [TypeAliasDecl]
    public let initBlocks: [FunctionBody]
    public let memberFunctions: [DeclID]
    public let memberProperties: [DeclID]
    public let nestedClasses: [DeclID]
    public let nestedObjects: [DeclID]

    public init(
        range: SourceRange,
        name: InternedString,
        modifiers: Modifiers,
        superTypes: [TypeRefID] = [],
        nestedTypeAliases: [TypeAliasDecl] = [],
        initBlocks: [FunctionBody] = [],
        memberFunctions: [DeclID] = [],
        memberProperties: [DeclID] = [],
        nestedClasses: [DeclID] = [],
        nestedObjects: [DeclID] = []
    ) {
        self.range = range
        self.name = name
        self.modifiers = modifiers
        self.superTypes = superTypes
        self.nestedTypeAliases = nestedTypeAliases
        self.initBlocks = initBlocks
        self.memberFunctions = memberFunctions
        self.memberProperties = memberProperties
        self.nestedClasses = nestedClasses
        self.nestedObjects = nestedObjects
    }
}

/// AST-layer type names mirror Kotlin syntax keywords (e.g. `fun`),
/// while semantic/KIR layers use full English names (e.g. `Function`).
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

public enum PropertyAccessorKind: Equatable {
    case getter
    case setter
}

public struct PropertyAccessorDecl: Equatable {
    public let range: SourceRange
    public let kind: PropertyAccessorKind
    public let parameterName: InternedString?
    public let body: FunctionBody

    public init(
        range: SourceRange,
        kind: PropertyAccessorKind,
        parameterName: InternedString? = nil,
        body: FunctionBody = .unit
    ) {
        self.range = range
        self.kind = kind
        self.parameterName = parameterName
        self.body = body
    }
}

public struct PropertyDecl {
    public let range: SourceRange
    public let name: InternedString
    public let modifiers: Modifiers
    public let type: TypeRefID?
    public let isVar: Bool
    public let initializer: ExprID?
    public let getter: PropertyAccessorDecl?
    public let setter: PropertyAccessorDecl?
    public let delegateExpression: ExprID?

    public init(
        range: SourceRange,
        name: InternedString,
        modifiers: Modifiers,
        type: TypeRefID?,
        isVar: Bool = false,
        initializer: ExprID? = nil,
        getter: PropertyAccessorDecl? = nil,
        setter: PropertyAccessorDecl? = nil,
        delegateExpression: ExprID? = nil
    ) {
        self.range = range
        self.name = name
        self.modifiers = modifiers
        self.type = type
        self.isVar = isVar
        self.initializer = initializer
        self.getter = getter
        self.setter = setter
        self.delegateExpression = delegateExpression
    }
}

public struct TypeAliasDecl {
    public let range: SourceRange
    public let name: InternedString
    public let modifiers: Modifiers
    public let typeParams: [TypeParamDecl]
    public let underlyingType: TypeRefID?

    public init(
        range: SourceRange,
        name: InternedString,
        modifiers: Modifiers,
        typeParams: [TypeParamDecl] = [],
        underlyingType: TypeRefID? = nil
    ) {
        self.range = range
        self.name = name
        self.modifiers = modifiers
        self.typeParams = typeParams
        self.underlyingType = underlyingType
    }
}

public struct EnumEntryDecl {
    public let range: SourceRange
    public let name: InternedString
}

public struct ImportDecl {
    public let range: SourceRange
    public let path: [InternedString]
    public let alias: InternedString?
}

public struct TypeParamDecl {
    public let name: InternedString
    public let variance: TypeVariance
    public let isReified: Bool
    public let upperBound: TypeRefID?

    public init(
        name: InternedString,
        variance: TypeVariance = .invariant,
        isReified: Bool = false,
        upperBound: TypeRefID? = nil
    ) {
        self.name = name
        self.variance = variance
        self.isReified = isReified
        self.upperBound = upperBound
    }
}

public struct ValueParamDecl: Equatable {
    public let name: InternedString
    public let type: TypeRefID?
    public let hasDefaultValue: Bool
    public let isVararg: Bool
    public let defaultValue: ExprID?

    public init(
        name: InternedString,
        type: TypeRefID?,
        hasDefaultValue: Bool = false,
        isVararg: Bool = false,
        defaultValue: ExprID? = nil
    ) {
        self.name = name
        self.type = type
        self.hasDefaultValue = hasDefaultValue
        self.isVararg = isVararg
        self.defaultValue = defaultValue
    }
}

public enum TypeArgRef: Equatable {
    case invariant(TypeRefID)
    case out(TypeRefID)
    case `in`(TypeRefID)
    case star
}

public enum TypeRef: Equatable {
    case named(path: [InternedString], args: [TypeArgRef], nullable: Bool)
    case functionType(params: [TypeRefID], returnType: TypeRefID, isSuspend: Bool, nullable: Bool)
}

public enum BinaryOp: Equatable {
    case add
    case subtract
    case multiply
    case divide
    case modulo
    case equal
    case notEqual
    case lessThan
    case lessOrEqual
    case greaterThan
    case greaterOrEqual
    case logicalAnd
    case logicalOr
    case elvis
    case rangeTo
}

public enum UnaryOp: Equatable {
    case not
    case unaryPlus
    case unaryMinus
}

public enum CompoundAssignOp: Equatable {
    case plusAssign
    case minusAssign
    case timesAssign
    case divAssign
    case modAssign
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

public struct CallArgument: Equatable {
    public let label: InternedString?
    public let isSpread: Bool
    public let expr: ExprID

    public init(label: InternedString? = nil, isSpread: Bool = false, expr: ExprID) {
        self.label = label
        self.isSpread = isSpread
        self.expr = expr
    }
}

public struct CatchClause: Equatable {
    public let paramName: InternedString?
    public let paramTypeName: InternedString?
    public let body: ExprID
    public let range: SourceRange

    public init(paramName: InternedString? = nil, paramTypeName: InternedString? = nil, body: ExprID, range: SourceRange) {
        self.paramName = paramName
        self.paramTypeName = paramTypeName
        self.body = body
        self.range = range
    }
}

public enum StringTemplatePart: Equatable {
    case literal(InternedString)
    case expression(ExprID)
}

public enum Expr: Equatable {
    case intLiteral(Int64, SourceRange)
    case longLiteral(Int64, SourceRange)
    case floatLiteral(Double, SourceRange)
    case doubleLiteral(Double, SourceRange)
    case charLiteral(UInt32, SourceRange)
    case boolLiteral(Bool, SourceRange)
    case stringLiteral(InternedString, SourceRange)
    case stringTemplate(parts: [StringTemplatePart], range: SourceRange)
    case nameRef(InternedString, SourceRange)
    case forExpr(loopVariable: InternedString?, iterable: ExprID, body: ExprID, range: SourceRange)
    case whileExpr(condition: ExprID, body: ExprID, range: SourceRange)
    case doWhileExpr(body: ExprID, condition: ExprID, range: SourceRange)
    case breakExpr(range: SourceRange)
    case continueExpr(range: SourceRange)
    case localDecl(name: InternedString, isMutable: Bool, typeAnnotation: TypeRefID?, initializer: ExprID?, range: SourceRange)
    case localAssign(name: InternedString, value: ExprID, range: SourceRange)
    case arrayAssign(array: ExprID, index: ExprID, value: ExprID, range: SourceRange)
    case call(callee: ExprID, typeArgs: [TypeRefID], args: [CallArgument], range: SourceRange)
    case memberCall(receiver: ExprID, callee: InternedString, typeArgs: [TypeRefID], args: [CallArgument], range: SourceRange)
    case arrayAccess(array: ExprID, index: ExprID, range: SourceRange)
    case binary(op: BinaryOp, lhs: ExprID, rhs: ExprID, range: SourceRange)
    case whenExpr(subject: ExprID, branches: [WhenBranch], elseExpr: ExprID?, range: SourceRange)
    case returnExpr(value: ExprID?, range: SourceRange)
    case ifExpr(condition: ExprID, thenExpr: ExprID, elseExpr: ExprID?, range: SourceRange)
    case tryExpr(body: ExprID, catchClauses: [CatchClause], finallyExpr: ExprID?, range: SourceRange)
    case unaryExpr(op: UnaryOp, operand: ExprID, range: SourceRange)
    case isCheck(expr: ExprID, type: TypeRefID, negated: Bool, range: SourceRange)
    case asCast(expr: ExprID, type: TypeRefID, isSafe: Bool, range: SourceRange)
    case nullAssert(expr: ExprID, range: SourceRange)
    case safeMemberCall(receiver: ExprID, callee: InternedString, typeArgs: [TypeRefID], args: [CallArgument], range: SourceRange)
    case compoundAssign(op: CompoundAssignOp, name: InternedString, value: ExprID, range: SourceRange)
    case throwExpr(value: ExprID, range: SourceRange)
    case localFunDecl(name: InternedString, valueParams: [ValueParamDecl], returnType: TypeRefID?, body: FunctionBody, range: SourceRange)
    case blockExpr(statements: [ExprID], trailingExpr: ExprID?, range: SourceRange)
}

public final class ASTArena {
    public private(set) var decls: [Decl] = []
    public private(set) var exprs: [Expr] = []
    public private(set) var typeRefs: [TypeRef] = []

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
             .longLiteral(_, let range),
             .floatLiteral(_, let range),
             .doubleLiteral(_, let range),
             .charLiteral(_, let range),
             .boolLiteral(_, let range),
             .stringLiteral(_, let range),
             .nameRef(_, let range),
             .forExpr(_, _, _, let range),
             .whileExpr(_, _, let range),
             .doWhileExpr(_, _, let range),
             .breakExpr(let range),
             .continueExpr(let range),
             .localDecl(_, _, _, _, let range),
             .localAssign(_, _, let range),
             .arrayAssign(_, _, _, let range),
             .call(_, _, _, let range),
             .memberCall(_, _, _, _, let range),
             .arrayAccess(_, _, let range),
             .binary(_, _, _, let range),
             .whenExpr(_, _, _, let range),
             .returnExpr(_, let range),
             .ifExpr(_, _, _, let range),
             .tryExpr(_, _, _, let range),
             .unaryExpr(_, _, let range),
             .isCheck(_, _, _, let range),
             .asCast(_, _, _, let range),
             .nullAssert(_, let range),
             .safeMemberCall(_, _, _, _, let range),
             .compoundAssign(_, _, _, let range),
             .stringTemplate(_, let range),
             .throwExpr(_, let range),
             .localFunDecl(_, _, _, _, let range),
             .blockExpr(_, _, let range):
            return range
        }
    }

    public func appendTypeRef(_ typeRef: TypeRef) -> TypeRefID {
        let id = TypeRefID(rawValue: Int32(typeRefs.count))
        typeRefs.append(typeRef)
        return id
    }

    public func typeRef(_ id: TypeRefID) -> TypeRef? {
        let index = Int(id.rawValue)
        if index < 0 || index >= typeRefs.count {
            return nil
        }
        return typeRefs[index]
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

extension ASTModule {
    var sortedFiles: [ASTFile] {
        files.sorted(by: { $0.fileID.rawValue < $1.fileID.rawValue })
    }
}
