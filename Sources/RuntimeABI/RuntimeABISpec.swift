public enum RuntimeABICType: String, Equatable, Sendable {
    case void
    case uint32 = "uint32_t"
    case uint64 = "uint64_t"
    case int32 = "int32_t"
    case intptr = "intptr_t"
    case opaquePointer = "void *"
    case nullableOpaquePointer = "void * _Nullable"
    case constUInt8Pointer = "const uint8_t *"
    case nullableConstUInt8Pointer = "const uint8_t * _Nullable"
    case nullableUInt8Pointer = "uint8_t * _Nullable"
    case constTypeInfoPointer = "const KTypeInfo *"
    case nullableRawPointerPointer = "void ** _Nullable"
    case int64 = "int64_t"
    case constRawPointer = "const void *"
    case nullableConstRawPointer = "const void * _Nullable"
    case nullableIntptrPointer = "intptr_t * _Nullable"
    case float = "float"
    case double = "double"
    case noreturn = "_Noreturn void"
}

public struct RuntimeABIParameter: Equatable, Sendable {
    public let name: String
    public let type: RuntimeABICType

    public init(name: String, type: RuntimeABICType) {
        self.name = name
        self.type = type
    }
}

public struct RuntimeABIFunctionSpec: Equatable, Sendable {
    public let name: String
    public let parameters: [RuntimeABIParameter]
    public let returnType: RuntimeABICType
    public let section: String
    /// Whether the runtime callee may throw (Kotlin exception propagation via `outThrown`).
    /// Defaults to `true`; non-throwing callees omit the `outThrown` ABI lowering path.
    public let isThrowing: Bool

    public init(
        name: String,
        parameters: [RuntimeABIParameter],
        returnType: RuntimeABICType,
        section: String,
        isThrowing: Bool = true
    ) {
        self.name = name
        self.parameters = parameters
        self.returnType = returnType
        self.section = section
        self.isThrowing = isThrowing
    }

    public var cDeclaration: String {
        let params: String = if parameters.isEmpty {
            "void"
        } else {
            parameters.map { "\($0.type.rawValue) \($0.name)" }.joined(separator: ", ")
        }
        return "\(returnType.rawValue) \(name)(\(params));"
    }

    /// Parameter types only (no names), for ABI reconciliation with `RuntimeABIExterns`.
    public var parameterTypeStrings: [String] {
        parameters.map(\.type.rawValue)
    }

    /// Return type as a raw C string, for ABI reconciliation.
    public var returnTypeString: String {
        returnType.rawValue
    }
}

public enum RuntimeABISpec {
    /// SHA-256 hex of the canonical serialization of `allFunctions`.
    /// Computed at first access so parallel PRs no longer need to update a hardcoded hash line.
    public static let specVersion: String = {
        let canonical = allFunctions.map { spec in
            let params = spec.parameters.map { "\($0.name):\($0.type.rawValue)" }.joined(separator: ",")
            return "\(spec.name)|\(spec.returnType.rawValue)|\(params)|\(spec.section)|\(spec.isThrowing)"
        }.joined(separator: "\n")
        return SHA256.hex(Array(canonical.utf8))
    }()
    /// Concatenation of every sub-array of `RuntimeABIFunctionSpec` defined in this module.
    ///
    /// The sub-arrays are listed in alphabetical order, one entry per line, so that
    /// parallel branches adding a new category insert their entry at a unique
    /// alphabetic position instead of appending to the same trailing line.
    ///
    /// When adding a new sub-array, insert its name in alphabetical position.
    /// Do NOT append at the end — that re-introduces the trailing-line conflict pattern.
    public static let allFunctions: [RuntimeABIFunctionSpec] = ([
        abiParityFunctions,
        arrayFunctions,
        atomicFunctions,
        base64Functions,
        bitwiseFunctions,
        booleanFunctions,
        boxingFunctions,
        callableRefFunctions,
        charFunctions,
        collectionBridgeFunctions,
        collectionFunctions,
        comparatorFunctions,
        consolePrintFunctions,
        coroutineFunctions,
        deepRecursiveFunctions,
        delegateFunctions,
        dispatchBridgeFunctions,
        durationFunctions,
        exceptionFunctions,
        fileIOFunctions,
        fileSystemExceptionFunctions,
        gcFunctions,
        i18nFunctions,
        ioFunctions,
        kFunctionFunctions,
        kParameterFunctions,
        kPropertyStubFunctions,
        kotlinVersionFunctions,
        localeFunctions,
        mathFunctions,
        memoryFunctions,
        nativeConcurrentFunctions,
        nativeRefFunctions,
        networkFunctions,
        numericRuntimeBridgeFunctions,
        operatorFunctions,
        pathFunctions,
        primitiveNumericConversionFunctions,
        randomFunctions,
        rangeFunctions,
        regexFunctions,
        resultFunctions,
        runtimeOnlyBridgeFunctions,
        sequenceFunctions,
        stringBridgeFunctions,
        stringBuilderFunctions,
        stringFunctions,
        stringParsingFunctions,
        stringSearchFunctions,
        systemFunctions,
        threadLocalFunctions,
        timeAndPathBridgeFunctions,
        uuidFunctions,
    ] as [[RuntimeABIFunctionSpec]]).flatMap { $0 }
}
