public extension RuntimeABISpec {
    static let deepRecursiveFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_deep_recursive_function_new",
            parameters: [
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "DeepRecursive"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_deep_recursive_function_invoke",
            parameters: [
                RuntimeABIParameter(name: "functionRaw", type: .intptr),
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "DeepRecursive"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_deep_recursive_scope_callRecursive",
            parameters: [
                RuntimeABIParameter(name: "scopeRaw", type: .intptr),
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "DeepRecursive"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_deep_recursive_function_callRecursive",
            parameters: [
                RuntimeABIParameter(name: "functionRaw", type: .intptr),
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "DeepRecursive"
        ),
    ]
}
