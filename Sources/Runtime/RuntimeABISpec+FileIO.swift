public extension RuntimeABISpec {
    /// File I/O (STDLIB-320)
    static let fileIOFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_file_new",
            parameters: [
                RuntimeABIParameter(name: "pathRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_file_readText",
            parameters: [
                RuntimeABIParameter(name: "fileRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_file_writeText",
            parameters: [
                RuntimeABIParameter(name: "fileRaw", type: .intptr),
                RuntimeABIParameter(name: "textRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_file_readLines",
            parameters: [
                RuntimeABIParameter(name: "fileRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
    ]
}
