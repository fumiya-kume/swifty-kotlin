public extension RuntimeABISpec {
    static let resultFunctions: [RuntimeABIFunctionSpec] = [
        // STDLIB-280: runCatching
        RuntimeABIFunctionSpec(
            name: "kk_runCatching",
            parameters: [
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Result"
        ),
        // STDLIB-281: Result properties
        RuntimeABIFunctionSpec(
            name: "kk_result_isSuccess",
            parameters: [
                RuntimeABIParameter(name: "resultRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Result"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_result_isFailure",
            parameters: [
                RuntimeABIParameter(name: "resultRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Result"
        ),
        // STDLIB-282: Result member functions
        RuntimeABIFunctionSpec(
            name: "kk_result_getOrNull",
            parameters: [
                RuntimeABIParameter(name: "resultRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Result"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_result_getOrDefault",
            parameters: [
                RuntimeABIParameter(name: "resultRaw", type: .intptr),
                RuntimeABIParameter(name: "defaultValue", type: .intptr),
            ],
            returnType: .intptr,
            section: "Result"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_result_getOrElse",
            parameters: [
                RuntimeABIParameter(name: "resultRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Result"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_result_getOrThrow",
            parameters: [
                RuntimeABIParameter(name: "resultRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Result"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_result_exceptionOrNull",
            parameters: [
                RuntimeABIParameter(name: "resultRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Result"
        ),
        // STDLIB-283: Result HOF functions
        RuntimeABIFunctionSpec(
            name: "kk_result_map",
            parameters: [
                RuntimeABIParameter(name: "resultRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Result"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_result_fold",
            parameters: [
                RuntimeABIParameter(name: "resultRaw", type: .intptr),
                RuntimeABIParameter(name: "onSuccessFnPtr", type: .intptr),
                RuntimeABIParameter(name: "onSuccessClosureRaw", type: .intptr),
                RuntimeABIParameter(name: "onFailureFnPtr", type: .intptr),
                RuntimeABIParameter(name: "onFailureClosureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Result"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_result_onSuccess",
            parameters: [
                RuntimeABIParameter(name: "resultRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Result"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_result_onFailure",
            parameters: [
                RuntimeABIParameter(name: "resultRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Result"
        ),
    ]
}
