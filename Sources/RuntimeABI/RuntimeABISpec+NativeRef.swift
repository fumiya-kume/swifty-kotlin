public extension RuntimeABISpec {
    static let nativeRefFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_weak_ref_create",
            parameters: [
                RuntimeABIParameter(name: "objectRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "NativeRef"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_weak_ref_get",
            parameters: [
                RuntimeABIParameter(name: "weakRefRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "NativeRef"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_weak_ref_clear",
            parameters: [
                RuntimeABIParameter(name: "weakRefRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "NativeRef"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_cleaner_create",
            parameters: [
                RuntimeABIParameter(name: "valueRaw", type: .intptr),
                RuntimeABIParameter(name: "blockRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "NativeRef"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_cleaner_clean",
            parameters: [
                RuntimeABIParameter(name: "cleanerRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "NativeRef"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_cleaner_dispose",
            parameters: [
                RuntimeABIParameter(name: "cleanerRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "NativeRef"
        ),
    ]
}
