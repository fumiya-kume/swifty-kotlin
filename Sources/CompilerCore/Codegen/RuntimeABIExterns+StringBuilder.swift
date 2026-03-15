/// StringBuilder extern declarations (STDLIB-255/256/257)
public extension RuntimeABIExterns {
    static let stringBuilderExterns: [ExternDecl] = [
        kk_string_builder_new,
        kk_string_builder_new_from_string,
        kk_string_builder_append_obj,
        kk_string_builder_toString,
        kk_string_builder_length_prop,
        kk_string_builder_appendLine_obj,
        kk_string_builder_appendLine_noarg_obj,
        kk_string_builder_insert_obj,
        kk_string_builder_delete_obj,
        kk_string_builder_clear,
        kk_string_builder_reverse,
        kk_string_builder_deleteCharAt,
        kk_string_builder_get,
    ]

    static let kk_string_builder_new = ExternDecl(
        name: "kk_string_builder_new",
        parameterTypes: [],
        returnType: "intptr_t"
    )

    static let kk_string_builder_new_from_string = ExternDecl(
        name: "kk_string_builder_new_from_string",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_string_builder_append_obj = ExternDecl(
        name: "kk_string_builder_append_obj",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_string_builder_toString = ExternDecl(
        name: "kk_string_builder_toString",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_string_builder_length_prop = ExternDecl(
        name: "kk_string_builder_length_prop",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_string_builder_appendLine_obj = ExternDecl(
        name: "kk_string_builder_appendLine_obj",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_string_builder_appendLine_noarg_obj = ExternDecl(
        name: "kk_string_builder_appendLine_noarg_obj",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_string_builder_insert_obj = ExternDecl(
        name: "kk_string_builder_insert_obj",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_string_builder_delete_obj = ExternDecl(
        name: "kk_string_builder_delete_obj",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_string_builder_clear = ExternDecl(
        name: "kk_string_builder_clear",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_string_builder_reverse = ExternDecl(
        name: "kk_string_builder_reverse",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_string_builder_deleteCharAt = ExternDecl(
        name: "kk_string_builder_deleteCharAt",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_string_builder_get = ExternDecl(
        name: "kk_string_builder_get",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )
}
