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

public struct LoopIterationBinding {
    public let iteratorCall: CallBinding
    public let hasNextCall: CallBinding
    public let nextCall: CallBinding
    public let iteratorType: TypeID
    public let elementType: TypeID

    public init(
        iteratorCall: CallBinding,
        hasNextCall: CallBinding,
        nextCall: CallBinding,
        iteratorType: TypeID,
        elementType: TypeID
    ) {
        self.iteratorCall = iteratorCall
        self.hasNextCall = hasNextCall
        self.nextCall = nextCall
        self.iteratorType = iteratorType
        self.elementType = elementType
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
    case scopeContext
    case scopeApply
    case scopeAlso
    case scopeTopLevelRun
    /// Closeable.use { } (STDLIB-520): like `let`, but wraps in try-finally calling close().
    case scopeUse
}

/// Identifies takeIf / takeUnless extension calls (STDLIB-160).
public enum TakeIfTakeUnlessKind: Equatable {
    case takeIf
    case takeUnless
}

/// Identifies special stdlib calls that need dedicated lowering.
public enum StdlibSpecialCallKind: Equatable {
    case repeatLoop
    case typeOf
    case maxOfInt
    case minOfInt
    case maxOfLong
    case minOfLong
    case maxOfDouble
    case minOfDouble
    case maxOfFloat
    case minOfFloat
    case maxOfInt3
    case minOfInt3
    case maxOfLong3
    case minOfLong3
    case maxOfDouble3
    case minOfDouble3
    case maxOfFloat3
    case minOfFloat3
    case arrayConstructor
    case atomicIntArrayFactory
    case measureTimeMillis
    case measureTimeMicros
    case measureNanoTime
    case measureTime
    case measureTimedValue
    case suspendCoroutineUninterceptedOrReturn
    case enumValues
    case enumValueOf
    case enumEntries
}

/// Identifies whether a callable reference (`::foo`) refers to a function
/// or a property, so that KIR lowering can emit the correct KFunction /
/// KProperty type identity metadata (REFL-003).
public enum CallableRefKind: Equatable {
    /// `::functionName` — produces a KFunction reference.
    case functionRef
    /// `::propertyName` — produces a KProperty reference.
    case propertyRef
}

public struct CatchClauseBinding: Equatable {
    public let parameterSymbol: SymbolID
    public let parameterType: TypeID

    public init(parameterSymbol: SymbolID = .invalid, parameterType: TypeID) {
        self.parameterSymbol = parameterSymbol
        self.parameterType = parameterType
    }
}
