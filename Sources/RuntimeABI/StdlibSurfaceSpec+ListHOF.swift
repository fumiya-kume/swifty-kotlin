// MARK: - List higher-order function surface
//
// Split from `StdlibSurfaceSpec.swift` so that parallel branches adding
// `kotlin.collections.List` member entries do not collide on the same
// central array. New `list(...)` entries go here.

extension StdlibSurfaceSpec {
    static let listHOFMembers: [StdlibSurfaceSpec] = [
        list("map", 1, "kk_list_map", returnStrategy: .list, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .any)),
        list("filter", 1, "kk_list_filter", returnStrategy: .list, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .boolean)),
        list("filterNot", 1, "kk_list_filterNot", returnStrategy: .list, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .boolean)),
        list("mapNotNull", 1, "kk_list_mapNotNull", returnStrategy: .list, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .nullableAny)),
        list("flatMap", 1, "kk_list_flatMap", returnStrategy: .list, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .any)),
        list("flatMapIndexed", 1, "kk_list_flatMapIndexed", returnStrategy: .list, lambdaExpectation: .indexedReceiverElement(argumentIndex: 0, returnStrategy: .any)),
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
}
