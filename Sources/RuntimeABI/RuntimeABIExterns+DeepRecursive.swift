public extension RuntimeABIExterns {
    static let deepRecursiveExterns: [ExternDecl] = [
        kk_deep_recursive_function_new,
        kk_deep_recursive_function_invoke,
        kk_deep_recursive_scope_callRecursive,
        kk_deep_recursive_function_callRecursive,
    ]

    static let kk_deep_recursive_function_new = ExternDecl(
        name: "kk_deep_recursive_function_new",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_deep_recursive_function_invoke = ExternDecl(
        name: "kk_deep_recursive_function_invoke",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_deep_recursive_scope_callRecursive = ExternDecl(
        name: "kk_deep_recursive_scope_callRecursive",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_deep_recursive_function_callRecursive = ExternDecl(
        name: "kk_deep_recursive_function_callRecursive",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )
}
