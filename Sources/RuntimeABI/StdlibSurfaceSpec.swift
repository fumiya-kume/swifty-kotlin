public enum StdlibSurfacePackage: String, Equatable, Hashable, Sendable {
    case kotlinCollections = "kotlin.collections"
    case kotlinSequences = "kotlin.sequences"
}

public enum StdlibSurfaceOwnerKind: String, CaseIterable, Equatable, Hashable, Sendable {
    case list
    case set
    case map
    case sequence
}

public struct StdlibSurfaceArity: Equatable, Hashable, Sendable {
    public let minimum: Int
    public let maximum: Int

    public init(_ exact: Int) {
        self.minimum = exact
        self.maximum = exact
    }

    public init(_ range: ClosedRange<Int>) {
        self.minimum = range.lowerBound
        self.maximum = range.upperBound
    }

    public func accepts(_ count: Int) -> Bool {
        count >= minimum && count <= maximum
    }
}

public enum StdlibSurfaceReturnStrategy: String, Equatable, Hashable, Sendable {
    case any
    case nullableAny
    case receiver
    case receiverElement
    case nullableReceiverElement
    case destinationArgument
    case unit
    case boolean
    case int
    case double
    case list
    case set
    case map
    case sequence
}

public enum StdlibSurfaceLambdaReturnStrategy: String, Equatable, Hashable, Sendable {
    case any
    case nullableAny
    case boolean
    case int
    case double
    case unit
    case destinationElement
    case destinationMapKey
    case destinationMapValue
    case collectionOfDestinationElement
    case pairOfDestinationKeyValue
}

public enum StdlibSurfaceLambdaExpectation: Equatable, Hashable, Sendable {
    case none
    case receiverElement(argumentIndex: Int, returnStrategy: StdlibSurfaceLambdaReturnStrategy)
    case indexedReceiverElement(argumentIndex: Int, returnStrategy: StdlibSurfaceLambdaReturnStrategy)
    case destinationElement(argumentIndex: Int, returnStrategy: StdlibSurfaceLambdaReturnStrategy)
    case indexedDestinationElement(argumentIndex: Int, returnStrategy: StdlibSurfaceLambdaReturnStrategy)
    case mapKey(argumentIndex: Int, returnStrategy: StdlibSurfaceLambdaReturnStrategy)
    case mapValue(argumentIndex: Int, returnStrategy: StdlibSurfaceLambdaReturnStrategy)
}

public enum StdlibSurfaceLoweringCategory: String, Equatable, Hashable, Sendable {
    case collectionHOF
    case setHOF
    case mapHOF
    case sequenceHOF
    case futureUse
}

public struct StdlibSurfaceSpec: Equatable, Hashable, Sendable {
    public let package: StdlibSurfacePackage
    public let ownerKind: StdlibSurfaceOwnerKind
    public let memberName: String
    public let arity: StdlibSurfaceArity
    public let runtimeLinkName: String
    public let returnStrategy: StdlibSurfaceReturnStrategy
    public let lambdaExpectation: StdlibSurfaceLambdaExpectation
    public let loweringCategory: StdlibSurfaceLoweringCategory

    /// All HOF surface members across owner kinds.
    ///
    /// The per-ownerKind sub-arrays live in dedicated files
    /// (`StdlibSurfaceSpec+ListHOF.swift`, `+SetHOF.swift`,
    /// `+MapHOF.swift`, `+SequenceHOF.swift`) so that parallel branches
    /// adding new entries do not collide on the same central file.
    public static let collectionHOFMembers: [StdlibSurfaceSpec] =
        listHOFMembers + setHOFMembers + mapHOFMembers + sequenceHOFMembers

    public static func collectionHOFSpecs(
        ownerKind: StdlibSurfaceOwnerKind,
        memberName: String
    ) -> [StdlibSurfaceSpec] {
        collectionHOFMembers.filter {
            $0.ownerKind == ownerKind && $0.memberName == memberName
        }
    }

    public static func collectionHOFMember(
        ownerKind: StdlibSurfaceOwnerKind,
        memberName: String,
        arity: Int
    ) -> StdlibSurfaceSpec? {
        collectionHOFSpecs(ownerKind: ownerKind, memberName: memberName)
            .first { $0.arity.accepts(arity) }
    }

    public static func collectionHOFRuntimeLinkName(
        ownerKind: StdlibSurfaceOwnerKind,
        memberName: String,
        arity: Int,
        fallback: String
    ) -> String {
        collectionHOFMember(ownerKind: ownerKind, memberName: memberName, arity: arity)?.runtimeLinkName ?? fallback
    }

    public static func collectionHOFRuntimeLinkNames(ownerKind: StdlibSurfaceOwnerKind) -> Set<String> {
        Set(collectionHOFMembers.lazy.filter { $0.ownerKind == ownerKind }.map(\.runtimeLinkName))
    }
}
