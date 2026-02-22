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
    public let memberFunctions: [DeclID]
    public let memberProperties: [DeclID]
    public let nestedClasses: [DeclID]
    public let nestedObjects: [DeclID]

    public init(
        range: SourceRange,
        name: InternedString,
        modifiers: Modifiers,
        typeParams: [TypeParamDecl] = [],
        superTypes: [TypeRefID] = [],
        nestedTypeAliases: [TypeAliasDecl] = [],
        memberFunctions: [DeclID] = [],
        memberProperties: [DeclID] = [],
        nestedClasses: [DeclID] = [],
        nestedObjects: [DeclID] = []
    ) {
        self.range = range
        self.name = name
        self.modifiers = modifiers
        self.typeParams = typeParams
        self.superTypes = superTypes
        self.nestedTypeAliases = nestedTypeAliases
        self.memberFunctions = memberFunctions
        self.memberProperties = memberProperties
        self.nestedClasses = nestedClasses
        self.nestedObjects = nestedObjects
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
