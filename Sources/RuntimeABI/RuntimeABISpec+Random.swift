// Random functions (STDLIB-165, STDLIB-514, STDLIB-515, STDLIB-653, STDLIB-654, STDLIB-655).

public extension RuntimeABISpec {
    static let randomFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_random_default",
            parameters: [],
            returnType: .intptr,
            section: "Random"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_random_create_seeded",
            parameters: [
                RuntimeABIParameter(name: "seed", type: .intptr),
            ],
            returnType: .intptr,
            section: "Random"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_random_asJavaRandom",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
            ],
            returnType: .intptr,
            section: "Random"
        ),
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
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
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
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Random"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_random_nextInt_rangeObject",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "range", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Random"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_random_nextLong",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
            ],
            returnType: .intptr,
            section: "Random"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_random_nextLong_until",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "until", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Random"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_random_nextLong_range",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "from", type: .intptr),
                RuntimeABIParameter(name: "until", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Random"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_random_nextLong_rangeObject",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "range", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Random"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_random_nextULong",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
            ],
            returnType: .intptr,
            section: "Random"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_random_nextULong_until",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "until", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Random"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_random_nextULong_range",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "from", type: .intptr),
                RuntimeABIParameter(name: "until", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Random"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_random_nextULong_ulongRange",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "range", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Random"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_random_nextUInt",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
            ],
            returnType: .intptr,
            section: "Random"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_random_nextUInt_until",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "until", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Random"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_random_nextUInt_range",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "from", type: .intptr),
                RuntimeABIParameter(name: "until", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Random"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_random_nextUInt_uintRange",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "range", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Random"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_random_nextFloat",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
            ],
            returnType: .intptr,
            section: "Random"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_random_nextFloat_until",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "until", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Random"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_random_nextFloat_range",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "from", type: .intptr),
                RuntimeABIParameter(name: "until", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Random"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_random_nextBytes",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "array", type: .intptr),
            ],
            returnType: .intptr,
            section: "Random"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_random_nextBytes_size",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "size", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Random"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_random_nextBytes_range",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "array", type: .intptr),
                RuntimeABIParameter(name: "fromIndex", type: .intptr),
                RuntimeABIParameter(name: "toIndex", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Random"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_random_nextUBytes_size",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "size", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Random"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_random_nextUBytes",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "array", type: .intptr),
            ],
            returnType: .intptr,
            section: "Random"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_random_nextUBytes_range",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "array", type: .intptr),
                RuntimeABIParameter(name: "fromIndex", type: .intptr),
                RuntimeABIParameter(name: "toIndex", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
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
            name: "kk_random_nextDouble_until",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "until", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Random"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_random_nextDouble_range",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "from", type: .intptr),
                RuntimeABIParameter(name: "until", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
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
        RuntimeABIFunctionSpec(
            name: "kk_random_nextBits",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "bitCount", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Random"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_secure_random_get_instance",
            parameters: [],
            returnType: .intptr,
            section: "Random"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_secure_random_set_seed",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "seed", type: .intptr),
            ],
            returnType: .intptr,
            section: "Random"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_secure_random_generate_seed",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "size", type: .intptr),
            ],
            returnType: .intptr,
            section: "Random"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_secure_random_next_bytes",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "array", type: .intptr),
            ],
            returnType: .intptr,
            section: "Random"
        ),
    ]
}
