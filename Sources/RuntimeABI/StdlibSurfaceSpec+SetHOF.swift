// MARK: - Set higher-order function surface
//
// Split from `StdlibSurfaceSpec.swift` so that parallel branches adding
// `kotlin.collections.Set` member entries do not collide on the same
// central array. New `set(...)` entries go here.

extension StdlibSurfaceSpec {
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
}
