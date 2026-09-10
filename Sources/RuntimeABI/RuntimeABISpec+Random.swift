// Random functions (STDLIB-165, STDLIB-514, STDLIB-515).
//
// KSP-466: kotlin.random.Random's core API (nextInt/nextLong/nextFloat/
// nextDouble/nextBoolean/nextBits/nextBytes, Random.Default, Random(seed)) is
// now Kotlin source (Sources/CompilerCore/Stdlib/kotlin/random/Random.kt) with
// no native ABI surface beyond __kk_random_seed_entropy. asKotlinRandom/
// asJavaRandom/java.util.Random are also real Kotlin source now (JavaUtilRandom.kt/
// PlatformRandom.kt) — a raw pointer passthrough between the two Random
// representations stopped being safe once kotlin.random.Random became a genuine
// compiled object instead of sharing java.util.Random's native SeededRandomBox.
// The entries below are what remains native: the IntRange/LongRange/UIntRange/
// Range-object overloads (KSP-457), and SecureRandom (KSP-467).

public extension RuntimeABISpec {
    static let randomFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "__kk_random_seed_entropy",
            parameters: [],
            returnType: .intptr,
            section: "Random",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_random_nextInt_rangeObject",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "range", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Random"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_random_nextLong_rangeObject",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "range", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Random"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_random_nextULong_ulongRange",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "range", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Random"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_random_nextUInt_uintRange",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "range", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Random"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_secure_random_get_instance",
            parameters: [],
            returnType: .intptr,
            section: "Random",
            isThrowing: false,
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_secure_random_set_seed",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "seed", type: .intptr),
            ],
            returnType: .intptr,
            section: "Random",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_secure_random_generate_seed",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "size", type: .intptr),
            ],
            returnType: .intptr,
            section: "Random",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_secure_random_next_bytes",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
                RuntimeABIParameter(name: "array", type: .intptr),
            ],
            returnType: .intptr,
            section: "Random",
            isThrowing: false
        ),
    ]
}
