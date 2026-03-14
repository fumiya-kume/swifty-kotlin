public struct CallBinding {
    public let chosenCallee: SymbolID
    public let substitutedTypeArguments: [TypeID]
    public let parameterMapping: [Int: Int]

    public init(chosenCallee: SymbolID, substitutedTypeArguments: [TypeID], parameterMapping: [Int: Int]) {
        self.chosenCallee = chosenCallee
        self.substitutedTypeArguments = substitutedTypeArguments
        self.parameterMapping = parameterMapping
    }
}

public enum CallableTarget: Equatable {
    case symbol(SymbolID)
    case localValue(SymbolID)
}

public struct CallableValueCallBinding {
    public let target: CallableTarget?
    public let functionType: TypeID
    public let parameterMapping: [Int: Int]

    public init(target: CallableTarget?, functionType: TypeID, parameterMapping: [Int: Int]) {
        self.target = target
        self.functionType = functionType
        self.parameterMapping = parameterMapping
    }
}

/// Identifies the kind of builder DSL function (STDLIB-002).
public enum BuilderDSLKind: Equatable {
    case buildString
    case buildList
    case buildSet
    case buildMap
}

/// Identifies the kind of scope function (STDLIB-004).
public enum ScopeFunctionKind: Equatable {
    case scopeLet
    case scopeRun
    case scopeWith
    case scopeApply
    case scopeAlso
}

/// Identifies takeIf / takeUnless extension calls (STDLIB-160).
public enum TakeIfTakeUnlessKind: Equatable {
    case takeIf
    case takeUnless
}

/// Identifies special stdlib calls that need dedicated lowering.
public enum StdlibSpecialCallKind: Equatable {
    case repeatLoop
    case maxOfInt
    case minOfInt
    case arrayConstructor
    case measureTimeMillis
    case enumValues
    case enumValueOf
}

public struct CatchClauseBinding: Equatable {
    public let parameterSymbol: SymbolID
    public let parameterType: TypeID

    public init(parameterSymbol: SymbolID = .invalid, parameterType: TypeID) {
        self.parameterSymbol = parameterSymbol
        self.parameterType = parameterType
    }
}
