public extension RuntimeABISpec {
    /// StringBuilder (STDLIB-255/256/257)
    static let stringBuilderFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_string_builder_new",
            parameters: [],
            returnType: .intptr,
            section: "StringBuilder"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_builder_new_from_string",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "StringBuilder"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_builder_append_obj",
            parameters: [
                RuntimeABIParameter(name: "sbRaw", type: .intptr),
                RuntimeABIParameter(name: "valueRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "StringBuilder"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_builder_toString",
            parameters: [
                RuntimeABIParameter(name: "sbRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "StringBuilder"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_builder_length_prop",
            parameters: [
                RuntimeABIParameter(name: "sbRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "StringBuilder"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_builder_appendLine_obj",
            parameters: [
                RuntimeABIParameter(name: "sbRaw", type: .intptr),
                RuntimeABIParameter(name: "valueRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "StringBuilder"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_builder_appendLine_noarg_obj",
            parameters: [
                RuntimeABIParameter(name: "sbRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "StringBuilder"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_builder_insert_obj",
            parameters: [
                RuntimeABIParameter(name: "sbRaw", type: .intptr),
                RuntimeABIParameter(name: "index", type: .intptr),
                RuntimeABIParameter(name: "valueRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "StringBuilder"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_builder_delete_obj",
            parameters: [
                RuntimeABIParameter(name: "sbRaw", type: .intptr),
                RuntimeABIParameter(name: "start", type: .intptr),
                RuntimeABIParameter(name: "end", type: .intptr),
            ],
            returnType: .intptr,
            section: "StringBuilder"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_builder_clear",
            parameters: [
                RuntimeABIParameter(name: "sbRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "StringBuilder"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_builder_reverse",
            parameters: [
                RuntimeABIParameter(name: "sbRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "StringBuilder"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_builder_deleteCharAt",
            parameters: [
                RuntimeABIParameter(name: "sbRaw", type: .intptr),
                RuntimeABIParameter(name: "index", type: .intptr),
            ],
            returnType: .intptr,
            section: "StringBuilder"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_builder_get",
            parameters: [
                RuntimeABIParameter(name: "sbRaw", type: .intptr),
                RuntimeABIParameter(name: "index", type: .intptr),
            ],
            returnType: .intptr,
            section: "StringBuilder"
        ),
    ]
}
