// MARK: - Map higher-order function surface
//
// Split from `StdlibSurfaceSpec.swift` so that parallel branches adding
// `kotlin.collections.Map` member entries do not collide on the same
// central array. New `map(...)` entries go here.

extension StdlibSurfaceSpec {
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
}
