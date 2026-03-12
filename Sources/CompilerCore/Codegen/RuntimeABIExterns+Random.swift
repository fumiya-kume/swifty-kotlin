// MARK: - Random (STDLIB-165)

public extension RuntimeABIExterns {
    static let randomExterns: [ExternDecl] = [
        kk_random_nextInt,
        kk_random_nextInt_until,
        kk_random_nextInt_range,
        kk_random_nextDouble,
        kk_random_nextBoolean,
    ]

    static let kk_random_nextInt = ExternDecl(
        name: "kk_random_nextInt",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_random_nextInt_until = ExternDecl(
        name: "kk_random_nextInt_until",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_random_nextInt_range = ExternDecl(
        name: "kk_random_nextInt_range",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_random_nextDouble = ExternDecl(
        name: "kk_random_nextDouble",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_random_nextBoolean = ExternDecl(
        name: "kk_random_nextBoolean",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )
}
