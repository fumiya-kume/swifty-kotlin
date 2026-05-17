// swiftlint:disable file_length

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

private extension StdlibSurfaceSpec {
    static func list(
        _ memberName: String,
        _ arity: Int,
        _ runtimeLinkName: String,
        returnStrategy: StdlibSurfaceReturnStrategy,
        lambdaExpectation: StdlibSurfaceLambdaExpectation
    ) -> StdlibSurfaceSpec {
        StdlibSurfaceSpec(
            package: .kotlinCollections,
            ownerKind: .list,
            memberName: memberName,
            arity: StdlibSurfaceArity(arity),
            runtimeLinkName: runtimeLinkName,
            returnStrategy: returnStrategy,
            lambdaExpectation: lambdaExpectation,
            loweringCategory: .collectionHOF
        )
    }

    static func set(
        _ memberName: String,
        _ arity: Int,
        _ runtimeLinkName: String,
        returnStrategy: StdlibSurfaceReturnStrategy,
        lambdaExpectation: StdlibSurfaceLambdaExpectation
    ) -> StdlibSurfaceSpec {
        StdlibSurfaceSpec(
            package: .kotlinCollections,
            ownerKind: .set,
            memberName: memberName,
            arity: StdlibSurfaceArity(arity),
            runtimeLinkName: runtimeLinkName,
            returnStrategy: returnStrategy,
            lambdaExpectation: lambdaExpectation,
            loweringCategory: .setHOF
        )
    }

    static func map(
        _ memberName: String,
        _ arity: Int,
        _ runtimeLinkName: String,
        returnStrategy: StdlibSurfaceReturnStrategy,
        lambdaExpectation: StdlibSurfaceLambdaExpectation
    ) -> StdlibSurfaceSpec {
        StdlibSurfaceSpec(
            package: .kotlinCollections,
            ownerKind: .map,
            memberName: memberName,
            arity: StdlibSurfaceArity(arity),
            runtimeLinkName: runtimeLinkName,
            returnStrategy: returnStrategy,
            lambdaExpectation: lambdaExpectation,
            loweringCategory: .mapHOF
        )
    }

    static func sequence(
        _ memberName: String,
        _ arity: Int,
        _ runtimeLinkName: String,
        returnStrategy: StdlibSurfaceReturnStrategy,
        lambdaExpectation: StdlibSurfaceLambdaExpectation
    ) -> StdlibSurfaceSpec {
        StdlibSurfaceSpec(
            package: .kotlinSequences,
            ownerKind: .sequence,
            memberName: memberName,
            arity: StdlibSurfaceArity(arity),
            runtimeLinkName: runtimeLinkName,
            returnStrategy: returnStrategy,
            lambdaExpectation: lambdaExpectation,
            loweringCategory: .sequenceHOF
        )
    }

    static let listHOFMembers: [StdlibSurfaceSpec] = [
        list("map", 1, "kk_list_map", returnStrategy: .list, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .any)),
        list("filter", 1, "kk_list_filter", returnStrategy: .list, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .boolean)),
        list("filterNot", 1, "kk_list_filterNot", returnStrategy: .list, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .boolean)),
        list("mapNotNull", 1, "kk_list_mapNotNull", returnStrategy: .list, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .nullableAny)),
        list("flatMap", 1, "kk_list_flatMap", returnStrategy: .list, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .any)),
        list("forEach", 1, "kk_list_forEach", returnStrategy: .unit, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .unit)),
        list("groupBy", 1, "kk_list_groupBy", returnStrategy: .map, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .any)),
        list("groupingBy", 1, "kk_list_groupingBy", returnStrategy: .any, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .any)),
        list("associateBy", 1, "kk_list_associateBy", returnStrategy: .map, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .any)),
        list("associateWith", 1, "kk_list_associateWith", returnStrategy: .map, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .any)),
        list("associate", 1, "kk_list_associate", returnStrategy: .map, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .any)),
        list("sumOf", 1, "kk_list_sumOf", returnStrategy: .int, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .int)),
        list("sumBy", 1, "kk_list_sumBy", returnStrategy: .int, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .int)),
        list("sumByDouble", 1, "kk_list_sumByDouble", returnStrategy: .double, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .double)),
        list("firstNotNullOf", 1, "kk_iterable_firstNotNullOf", returnStrategy: .any, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .nullableAny)),
        list("firstNotNullOfOrNull", 1, "kk_iterable_firstNotNullOfOrNull", returnStrategy: .nullableAny, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .nullableAny)),
        list("forEachIndexed", 1, "kk_list_forEachIndexed", returnStrategy: .unit, lambdaExpectation: .indexedReceiverElement(argumentIndex: 0, returnStrategy: .unit)),
        list("onEach", 1, "kk_list_onEach", returnStrategy: .list, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .unit)),
        list("onEachIndexed", 1, "kk_list_onEachIndexed", returnStrategy: .list, lambdaExpectation: .indexedReceiverElement(argumentIndex: 0, returnStrategy: .unit)),
        list("mapIndexed", 1, "kk_list_mapIndexed", returnStrategy: .list, lambdaExpectation: .indexedReceiverElement(argumentIndex: 0, returnStrategy: .any)),
        list("filterIndexed", 1, "kk_list_filterIndexed", returnStrategy: .list, lambdaExpectation: .indexedReceiverElement(argumentIndex: 0, returnStrategy: .boolean)),
        list("takeWhile", 1, "kk_list_takeWhile", returnStrategy: .list, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .boolean)),
        list("dropWhile", 1, "kk_list_dropWhile", returnStrategy: .list, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .boolean)),
        list("takeLastWhile", 1, "kk_list_takeLastWhile", returnStrategy: .list, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .boolean)),
        list("dropLastWhile", 1, "kk_list_dropLastWhile", returnStrategy: .list, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .boolean)),
        list("filterTo", 2, "kk_list_filterTo", returnStrategy: .destinationArgument, lambdaExpectation: .destinationElement(argumentIndex: 1, returnStrategy: .boolean)),
        list("filterNotTo", 2, "kk_list_filterNotTo", returnStrategy: .destinationArgument, lambdaExpectation: .destinationElement(argumentIndex: 1, returnStrategy: .boolean)),
        list("mapTo", 2, "kk_list_mapTo", returnStrategy: .destinationArgument, lambdaExpectation: .destinationElement(argumentIndex: 1, returnStrategy: .destinationElement)),
        list("flatMapTo", 2, "kk_list_flatMapTo", returnStrategy: .destinationArgument, lambdaExpectation: .destinationElement(argumentIndex: 1, returnStrategy: .collectionOfDestinationElement)),
        list("mapNotNullTo", 2, "kk_list_mapNotNullTo", returnStrategy: .destinationArgument, lambdaExpectation: .destinationElement(argumentIndex: 1, returnStrategy: .nullableAny)),
        list("mapIndexedTo", 2, "kk_list_mapIndexedTo", returnStrategy: .destinationArgument, lambdaExpectation: .indexedDestinationElement(argumentIndex: 1, returnStrategy: .destinationElement)),
        list("mapIndexedNotNullTo", 2, "kk_list_mapIndexedNotNullTo", returnStrategy: .destinationArgument, lambdaExpectation: .indexedDestinationElement(argumentIndex: 1, returnStrategy: .nullableAny)),
        list("flatMapIndexedTo", 2, "kk_list_flatMapIndexedTo", returnStrategy: .destinationArgument, lambdaExpectation: .indexedDestinationElement(argumentIndex: 1, returnStrategy: .collectionOfDestinationElement)),
        list("filterIndexedTo", 2, "kk_list_filterIndexedTo", returnStrategy: .destinationArgument, lambdaExpectation: .indexedDestinationElement(argumentIndex: 1, returnStrategy: .boolean)),
        list("associateTo", 2, "kk_list_associateTo", returnStrategy: .destinationArgument, lambdaExpectation: .destinationElement(argumentIndex: 1, returnStrategy: .pairOfDestinationKeyValue)),
        list("associateByTo", 2, "kk_list_associateByTo", returnStrategy: .destinationArgument, lambdaExpectation: .destinationElement(argumentIndex: 1, returnStrategy: .any)),
        list("associateWithTo", 2, "kk_list_associateWithTo", returnStrategy: .destinationArgument, lambdaExpectation: .destinationElement(argumentIndex: 1, returnStrategy: .any)),
        list("groupByTo", 2, "kk_list_groupByTo", returnStrategy: .destinationArgument, lambdaExpectation: .destinationElement(argumentIndex: 1, returnStrategy: .any)),
    ]

    static let setHOFMembers: [StdlibSurfaceSpec] = [
        set("map", 1, "kk_set_map", returnStrategy: .list, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .any)),
        set("filter", 1, "kk_set_filter", returnStrategy: .list, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .boolean)),
        set("forEach", 1, "kk_set_forEach", returnStrategy: .unit, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .unit)),
        set("filterNot", 1, "kk_set_filterNot", returnStrategy: .list, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .boolean)),
        set("mapNotNull", 1, "kk_set_mapNotNull", returnStrategy: .list, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .nullableAny)),
        set("flatMap", 1, "kk_set_flatMap", returnStrategy: .list, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .any)),
        set("any", 1, "kk_set_any", returnStrategy: .boolean, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .boolean)),
        set("none", 1, "kk_set_none", returnStrategy: .boolean, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .boolean)),
        set("all", 1, "kk_set_all", returnStrategy: .boolean, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .boolean)),
        set("count", 1, "kk_set_count_predicate", returnStrategy: .int, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .boolean)),
    ]

    static let mapHOFMembers: [StdlibSurfaceSpec] = [
        map("forEach", 1, "kk_map_forEach", returnStrategy: .unit, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .unit)),
        map("map", 1, "kk_map_map", returnStrategy: .list, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .any)),
        map("mapNotNull", 1, "kk_map_mapNotNull", returnStrategy: .list, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .nullableAny)),
        map("filter", 1, "kk_map_filter", returnStrategy: .receiver, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .boolean)),
        map("filterNot", 1, "kk_map_filterNot", returnStrategy: .receiver, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .boolean)),
        map("count", 1, "kk_map_count", returnStrategy: .int, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .boolean)),
        map("any", 1, "kk_map_any", returnStrategy: .boolean, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .boolean)),
        map("all", 1, "kk_map_all", returnStrategy: .boolean, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .boolean)),
        map("none", 1, "kk_map_none", returnStrategy: .boolean, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .boolean)),
        map("mapValues", 1, "kk_map_mapValues", returnStrategy: .map, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .any)),
        map("mapKeys", 1, "kk_map_mapKeys", returnStrategy: .map, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .any)),
        map("mapValuesTo", 2, "kk_map_mapValuesTo", returnStrategy: .destinationArgument, lambdaExpectation: .destinationElement(argumentIndex: 1, returnStrategy: .destinationMapValue)),
        map("mapKeysTo", 2, "kk_map_mapKeysTo", returnStrategy: .destinationArgument, lambdaExpectation: .destinationElement(argumentIndex: 1, returnStrategy: .destinationMapKey)),
        map("filterKeys", 1, "kk_map_filterKeys", returnStrategy: .map, lambdaExpectation: .mapKey(argumentIndex: 0, returnStrategy: .boolean)),
        map("filterValues", 1, "kk_map_filterValues", returnStrategy: .map, lambdaExpectation: .mapValue(argumentIndex: 0, returnStrategy: .boolean)),
    ]

    static let sequenceHOFMembers: [StdlibSurfaceSpec] = [
        sequence("map", 1, "kk_sequence_map", returnStrategy: .sequence, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .any)),
        sequence("filter", 1, "kk_sequence_filter", returnStrategy: .sequence, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .boolean)),
        sequence("filterNot", 1, "kk_sequence_filterNot", returnStrategy: .sequence, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .boolean)),
        sequence("mapNotNull", 1, "kk_sequence_mapNotNull", returnStrategy: .sequence, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .nullableAny)),
        sequence("flatMap", 1, "kk_sequence_flatMap", returnStrategy: .sequence, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .any)),
        sequence("flatMapIndexed", 1, "kk_sequence_flatMapIndexed", returnStrategy: .sequence, lambdaExpectation: .indexedReceiverElement(argumentIndex: 0, returnStrategy: .any)),
        sequence("forEach", 1, "kk_sequence_forEach", returnStrategy: .unit, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .unit)),
        sequence("groupBy", 1, "kk_sequence_groupBy", returnStrategy: .map, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .any)),
        sequence("associate", 1, "kk_sequence_associate", returnStrategy: .map, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .any)),
        sequence("associateBy", 1, "kk_sequence_associateBy", returnStrategy: .map, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .any)),
        sequence("associateWith", 1, "kk_sequence_associateWith", returnStrategy: .map, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .any)),
        sequence("chunked", 1, "kk_sequence_chunked", returnStrategy: .sequence, lambdaExpectation: .none),
        sequence("sumOf", 1, "kk_sequence_sumOf", returnStrategy: .int, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .int)),
        sequence("sumBy", 1, "kk_sequence_sumBy", returnStrategy: .int, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .int)),
        sequence("sumByDouble", 1, "kk_sequence_sumByDouble", returnStrategy: .double, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .double)),
        sequence("maxOfOrNull", 1, "kk_sequence_maxOfOrNull", returnStrategy: .nullableAny, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .any)),
        sequence("firstNotNullOf", 1, "kk_sequence_firstNotNullOf", returnStrategy: .any, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .nullableAny)),
        sequence("firstNotNullOfOrNull", 1, "kk_sequence_firstNotNullOfOrNull", returnStrategy: .nullableAny, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .nullableAny)),
        sequence("forEachIndexed", 1, "kk_sequence_forEachIndexed", returnStrategy: .unit, lambdaExpectation: .indexedReceiverElement(argumentIndex: 0, returnStrategy: .unit)),
        sequence("onEach", 1, "kk_sequence_onEach", returnStrategy: .sequence, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .unit)),
        sequence("onEachIndexed", 1, "kk_sequence_onEachIndexed", returnStrategy: .sequence, lambdaExpectation: .indexedReceiverElement(argumentIndex: 0, returnStrategy: .unit)),
        sequence("mapIndexed", 1, "kk_sequence_mapIndexed", returnStrategy: .sequence, lambdaExpectation: .indexedReceiverElement(argumentIndex: 0, returnStrategy: .any)),
        sequence("filterTo", 2, "kk_sequence_filterTo", returnStrategy: .destinationArgument, lambdaExpectation: .destinationElement(argumentIndex: 1, returnStrategy: .boolean)),
        sequence("filterNotTo", 2, "kk_sequence_filterNotTo", returnStrategy: .destinationArgument, lambdaExpectation: .destinationElement(argumentIndex: 1, returnStrategy: .boolean)),
        sequence("mapTo", 2, "kk_sequence_mapTo", returnStrategy: .destinationArgument, lambdaExpectation: .destinationElement(argumentIndex: 1, returnStrategy: .destinationElement)),
        sequence("mapIndexedNotNullTo", 2, "kk_sequence_mapIndexedNotNullTo", returnStrategy: .destinationArgument, lambdaExpectation: .indexedDestinationElement(argumentIndex: 1, returnStrategy: .nullableAny)),
        sequence("filterIndexedTo", 2, "kk_sequence_filterIndexedTo", returnStrategy: .destinationArgument, lambdaExpectation: .indexedDestinationElement(argumentIndex: 1, returnStrategy: .boolean)),
        sequence("filterNotNullTo", 1, "kk_sequence_filterNotNullTo", returnStrategy: .destinationArgument, lambdaExpectation: .none),
        sequence("filterIsInstance", 0, "kk_sequence_filterIsInstance", returnStrategy: .sequence, lambdaExpectation: .none),
        sequence("filterIsInstanceTo", 1, "kk_sequence_filterIsInstanceTo", returnStrategy: .destinationArgument, lambdaExpectation: .none),
        sequence("associateTo", 2, "kk_sequence_associateTo", returnStrategy: .destinationArgument, lambdaExpectation: .destinationElement(argumentIndex: 1, returnStrategy: .pairOfDestinationKeyValue)),
        sequence("associateByTo", 2, "kk_sequence_associateByTo", returnStrategy: .destinationArgument, lambdaExpectation: .destinationElement(argumentIndex: 1, returnStrategy: .any)),
        sequence("associateWithTo", 2, "kk_sequence_associateWithTo", returnStrategy: .destinationArgument, lambdaExpectation: .destinationElement(argumentIndex: 1, returnStrategy: .any)),
        sequence("groupByTo", 2, "kk_sequence_groupByTo", returnStrategy: .destinationArgument, lambdaExpectation: .destinationElement(argumentIndex: 1, returnStrategy: .any)),
    ]
}
