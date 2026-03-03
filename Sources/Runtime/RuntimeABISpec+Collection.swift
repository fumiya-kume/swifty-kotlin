// Collection ABI specs (STDLIB-001)
// swiftlint:disable trailing_comma

public extension RuntimeABISpec {
    /// Collection functions for List, Map, and Array operations.
    static let collectionFunctions: [RuntimeABIFunctionSpec] = [
        // List
        RuntimeABIFunctionSpec(
            name: "kk_list_of",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
                RuntimeABIParameter(name: "count", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_size",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_get",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
                RuntimeABIParameter(name: "index", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_contains",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
                RuntimeABIParameter(name: "element", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_is_empty",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_iterator",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_iterator_hasNext",
            parameters: [
                RuntimeABIParameter(name: "iterRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_iterator_next",
            parameters: [
                RuntimeABIParameter(name: "iterRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_list_to_string",
            parameters: [
                RuntimeABIParameter(name: "listRaw", type: .intptr),
            ],
            returnType: .opaquePointer,
            section: "Collection"
        ),
        // Map
        RuntimeABIFunctionSpec(
            name: "kk_map_of",
            parameters: [
                RuntimeABIParameter(name: "keysArrayRaw", type: .intptr),
                RuntimeABIParameter(name: "valuesArrayRaw", type: .intptr),
                RuntimeABIParameter(name: "count", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_map_size",
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_map_get",
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
                RuntimeABIParameter(name: "key", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_map_contains_key",
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
                RuntimeABIParameter(name: "key", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_map_is_empty",
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_map_to_string",
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
            ],
            returnType: .opaquePointer,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_map_iterator",
            parameters: [
                RuntimeABIParameter(name: "mapRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_map_iterator_hasNext",
            parameters: [
                RuntimeABIParameter(name: "iterRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_map_iterator_next",
            parameters: [
                RuntimeABIParameter(name: "iterRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        // Array
        RuntimeABIFunctionSpec(
            name: "kk_array_of",
            parameters: [
                RuntimeABIParameter(name: "elements", type: .intptr),
                RuntimeABIParameter(name: "count", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_array_size",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        // Builder DSL (STDLIB-002)
        RuntimeABIFunctionSpec(
            name: "kk_build_string",
            parameters: [
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_build_list",
            parameters: [
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_build_map",
            parameters: [
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_builder_append",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_mutable_list_add",
            parameters: [
                RuntimeABIParameter(name: "elem", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_mutable_map_put",
            parameters: [
                RuntimeABIParameter(name: "key", type: .intptr),
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collection"
        ),
    ]
}

// swiftlint:enable trailing_comma
