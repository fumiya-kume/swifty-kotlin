// MARK: - Per-ownerKind constructor helpers
//
// These factories were originally `private` inside `StdlibSurfaceSpec.swift`.
// They are promoted to `internal` so that the per-ownerKind member tables
// (`+ListHOF.swift`, `+SetHOF.swift`, `+MapHOF.swift`, `+SequenceHOF.swift`)
// can be split into separate files without colliding on the same single
// source file when parallel branches add new members. Visibility is still
// confined to the RuntimeABI module.

extension StdlibSurfaceSpec {
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
}
