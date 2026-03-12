// Random functions (STDLIB-165).

public extension RuntimeABISpec {
    static let randomFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_random_nextInt",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
            ],
            returnType: .intptr,
            section: "Random"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_random_nextInt_until",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "until", type: .intptr),
            ],
            returnType: .intptr,
            section: "Random"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_random_nextInt_range",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "from", type: .intptr),
                RuntimeABIParameter(name: "until", type: .intptr),
            ],
            returnType: .intptr,
            section: "Random"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_random_nextDouble",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
            ],
            returnType: .intptr,
            section: "Random"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_random_nextBoolean",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
            ],
            returnType: .intptr,
            section: "Random"
        ),
    ]
}
