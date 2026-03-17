public extension RuntimeABISpec {
    /// File I/O (STDLIB-320/321/322/323)
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
        RuntimeABIFunctionSpec(
            name: "kk_file_exists",
            parameters: [
                RuntimeABIParameter(name: "fileRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_file_isFile",
            parameters: [
                RuntimeABIParameter(name: "fileRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_file_isDirectory",
            parameters: [
                RuntimeABIParameter(name: "fileRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_file_name",
            parameters: [
                RuntimeABIParameter(name: "fileRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_file_path",
            parameters: [
                RuntimeABIParameter(name: "fileRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_file_forEachLine",
            parameters: [
                RuntimeABIParameter(name: "fileRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_file_delete",
            parameters: [
                RuntimeABIParameter(name: "fileRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_file_mkdirs",
            parameters: [
                RuntimeABIParameter(name: "fileRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_file_listFiles",
            parameters: [
                RuntimeABIParameter(name: "fileRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_file_walk",
            parameters: [
                RuntimeABIParameter(name: "fileRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
    ]
}
