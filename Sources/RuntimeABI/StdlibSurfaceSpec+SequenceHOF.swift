// MARK: - Sequence higher-order function surface
//
// Split from `StdlibSurfaceSpec.swift` so that parallel branches adding
// `kotlin.sequences.Sequence` member entries do not collide on the same
// central array. New `sequence(...)` entries go here.

extension StdlibSurfaceSpec {
    static let sequenceHOFMembers: [StdlibSurfaceSpec] = [
        sequence("map", 1, "kk_sequence_map", returnStrategy: .sequence, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .any)),
        sequence("filter", 1, "kk_sequence_filter", returnStrategy: .sequence, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .boolean)),
        sequence("filterNot", 1, "kk_sequence_filterNot", returnStrategy: .sequence, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .boolean)),
        sequence("mapNotNull", 1, "kk_sequence_mapNotNull", returnStrategy: .sequence, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .nullableAny)),
        sequence("flatMap", 1, "kk_sequence_flatMap", returnStrategy: .sequence, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .any)),
        sequence("flatMapIndexed", 1, "kk_sequence_flatMapIndexed", returnStrategy: .sequence, lambdaExpectation: .indexedReceiverElement(argumentIndex: 0, returnStrategy: .any)),
        sequence("plus", 1, "kk_sequence_plus", returnStrategy: .sequence, lambdaExpectation: .none),
        sequence("random", 0, "kk_sequence_random", returnStrategy: .receiverElement, lambdaExpectation: .none),
        sequence("randomOrNull", 0, "kk_sequence_randomOrNull", returnStrategy: .nullableReceiverElement, lambdaExpectation: .none),
        sequence("plusElement", 1, "kk_sequence_plus_element", returnStrategy: .sequence, lambdaExpectation: .none),
        sequence("contains", 1, "kk_sequence_contains", returnStrategy: .boolean, lambdaExpectation: .none),
        sequence("indexOf", 1, "kk_sequence_indexOf", returnStrategy: .int, lambdaExpectation: .none),
        sequence("constrainOnce", 0, "kk_sequence_constrainOnce", returnStrategy: .sequence, lambdaExpectation: .none),
        sequence("count", 0, "kk_sequence_count", returnStrategy: .int, lambdaExpectation: .none),
        sequence("elementAt", 1, "kk_sequence_elementAt", returnStrategy: .receiver, lambdaExpectation: .none),
        sequence("elementAtOrElse", 2, "kk_sequence_elementAtOrElse", returnStrategy: .receiver, lambdaExpectation: .none),
        sequence("shuffled", 0, "kk_sequence_shuffled", returnStrategy: .sequence, lambdaExpectation: .none),
        sequence("shuffled", 1, "kk_sequence_shuffled_random", returnStrategy: .sequence, lambdaExpectation: .none),
        sequence("elementAtOrNull", 1, "kk_sequence_elementAtOrNull", returnStrategy: .nullableAny, lambdaExpectation: .none),
        sequence("max", 0, "kk_sequence_max", returnStrategy: .receiverElement, lambdaExpectation: .none),
        sequence("maxOrNull", 0, "kk_sequence_maxOrNull", returnStrategy: .nullableAny, lambdaExpectation: .none),
        sequence("minOrNull", 0, "kk_sequence_minOrNull", returnStrategy: .nullableAny, lambdaExpectation: .none),
        sequence("none", 0, "kk_sequence_none", returnStrategy: .boolean, lambdaExpectation: .none),
        sequence("none", 1, "kk_sequence_none", returnStrategy: .boolean, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .boolean)),
        sequence("first", 0, "kk_sequence_first", returnStrategy: .receiverElement, lambdaExpectation: .none),
        sequence("firstOrNull", 0, "kk_sequence_firstOrNull", returnStrategy: .nullableReceiverElement, lambdaExpectation: .none),
        sequence("firstNotNullOf", 1, "kk_sequence_firstNotNullOf", returnStrategy: .any, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .nullableAny)),
        sequence("firstNotNullOfOrNull", 1, "kk_sequence_firstNotNullOfOrNull", returnStrategy: .nullableAny, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .nullableAny)),
        sequence("indexOfLast", 1, "kk_sequence_indexOfLast", returnStrategy: .int, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .boolean)),
        sequence("intersect", 1, "kk_sequence_intersect", returnStrategy: .set, lambdaExpectation: .none),
        sequence("indexOfFirst", 1, "kk_sequence_indexOfFirst", returnStrategy: .int, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .boolean)),
        sequence("min", 0, "kk_sequence_min", returnStrategy: .any, lambdaExpectation: .none),
        sequence("onEach", 1, "kk_sequence_onEach", returnStrategy: .sequence, lambdaExpectation: .receiverElement(argumentIndex: 0, returnStrategy: .unit)),
        sequence("onEachIndexed", 1, "kk_sequence_onEachIndexed", returnStrategy: .sequence, lambdaExpectation: .indexedReceiverElement(argumentIndex: 0, returnStrategy: .unit)),
        sequence("mapIndexed", 1, "kk_sequence_mapIndexed", returnStrategy: .sequence, lambdaExpectation: .indexedReceiverElement(argumentIndex: 0, returnStrategy: .any)),
        sequence("mapIndexedNotNull", 1, "kk_sequence_mapIndexedNotNull", returnStrategy: .sequence, lambdaExpectation: .indexedReceiverElement(argumentIndex: 0, returnStrategy: .nullableAny)),
        sequence("reversed", 0, "kk_sequence_reversed", returnStrategy: .sequence, lambdaExpectation: .none),
        sequence("filterIndexed", 1, "kk_sequence_filterIndexed", returnStrategy: .sequence, lambdaExpectation: .indexedReceiverElement(argumentIndex: 0, returnStrategy: .boolean)),
        sequence("filterNotNull", 0, "kk_sequence_filterNotNull", returnStrategy: .sequence, lambdaExpectation: .none),
        sequence("requireNoNulls", 0, "kk_sequence_requireNoNulls", returnStrategy: .sequence, lambdaExpectation: .none),
        sequence("minus", 1, "kk_sequence_minus", returnStrategy: .sequence, lambdaExpectation: .none),
    ]
}
