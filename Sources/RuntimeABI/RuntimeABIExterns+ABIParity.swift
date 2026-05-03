// Auto-generated ABI parity externs to reconcile RuntimeABIExterns with RuntimeABISpec.

public extension RuntimeABIExterns {
    static let kk_int_coerceIn_range = ExternDecl(
        name: "kk_int_coerceIn_range",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_int_coerceAtLeast_range = ExternDecl(
        name: "kk_int_coerceAtLeast_range",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_int_coerceAtMost_range = ExternDecl(
        name: "kk_int_coerceAtMost_range",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_long_coerceIn_range = ExternDecl(
        name: "kk_long_coerceIn_range",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_long_coerceAtLeast_range = ExternDecl(
        name: "kk_long_coerceAtLeast_range",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_long_coerceAtMost_range = ExternDecl(
        name: "kk_long_coerceAtMost_range",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_double_coerceIn_range = ExternDecl(
        name: "kk_double_coerceIn_range",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_double_coerceAtLeast_range = ExternDecl(
        name: "kk_double_coerceAtLeast_range",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_double_coerceAtMost_range = ExternDecl(
        name: "kk_double_coerceAtMost_range",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_float_coerceIn_range = ExternDecl(
        name: "kk_float_coerceIn_range",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_float_coerceAtLeast_range = ExternDecl(
        name: "kk_float_coerceAtLeast_range",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_float_coerceAtMost_range = ExternDecl(
        name: "kk_float_coerceAtMost_range",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_string_builder_replace_obj = ExternDecl(
        name: "kk_string_builder_replace_obj",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_string_builder_setCharAt = ExternDecl(
        name: "kk_string_builder_setCharAt",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_string_builder_capacity = ExternDecl(
        name: "kk_string_builder_capacity",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_string_builder_ensureCapacity = ExternDecl(
        name: "kk_string_builder_ensureCapacity",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_string_builder_trimToSize = ExternDecl(
        name: "kk_string_builder_trimToSize",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_string_mapIndexed = ExternDecl(
        name: "kk_string_mapIndexed",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_string_mapNotNull = ExternDecl(
        name: "kk_string_mapNotNull",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_string_filterIndexed = ExternDecl(
        name: "kk_string_filterIndexed",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_string_filterNot = ExternDecl(
        name: "kk_string_filterNot",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_string_takeWhile = ExternDecl(
        name: "kk_string_takeWhile",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_string_dropWhile = ExternDecl(
        name: "kk_string_dropWhile",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_string_splitToSequence = ExternDecl(
        name: "kk_string_splitToSequence",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_string_joinToString = ExternDecl(
        name: "kk_string_joinToString",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_string_find = ExternDecl(
        name: "kk_string_find",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_string_findLast = ExternDecl(
        name: "kk_string_findLast",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_coroutine_scope_is_active = ExternDecl(
        name: "kk_coroutine_scope_is_active",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_coroutine_scope_is_cancelled = ExternDecl(
        name: "kk_coroutine_scope_is_cancelled",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_coroutine_scope_get_parent = ExternDecl(
        name: "kk_coroutine_scope_get_parent",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_coroutine_scope_cancel_propagate = ExternDecl(
        name: "kk_coroutine_scope_cancel_propagate",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_op_eq = ExternDecl(
        name: "kk_op_eq",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_op_ne = ExternDecl(
        name: "kk_op_ne",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_op_lt = ExternDecl(
        name: "kk_op_lt",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_op_le = ExternDecl(
        name: "kk_op_le",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_op_gt = ExternDecl(
        name: "kk_op_gt",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_op_ge = ExternDecl(
        name: "kk_op_ge",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_op_floor_div = ExternDecl(
        name: "kk_op_floor_div",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_op_lfloor_div = ExternDecl(
        name: "kk_op_lfloor_div",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_op_mod = ExternDecl(
        name: "kk_op_mod",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_op_lmod = ExternDecl(
        name: "kk_op_lmod",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_op_floor_mod = ExternDecl(
        name: "kk_op_floor_mod",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_op_lfloor_mod = ExternDecl(
        name: "kk_op_lfloor_mod",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_logical_and = ExternDecl(
        name: "kk_logical_and",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_logical_or = ExternDecl(
        name: "kk_logical_or",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_char_minus = ExternDecl(
        name: "kk_char_minus",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_char_plus = ExternDecl(
        name: "kk_char_plus",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "void *"
    )

    static let kk_char_get = ExternDecl(
        name: "kk_char_get",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_char_rangeTo = ExternDecl(
        name: "kk_char_rangeTo",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "void *"
    )

    static let abiParityExternsPart1: [ExternDecl] = [
        kk_int_coerceIn_range,
        kk_int_coerceAtLeast_range,
        kk_int_coerceAtMost_range,
        kk_long_coerceIn_range,
        kk_long_coerceAtLeast_range,
        kk_long_coerceAtMost_range,
        kk_double_coerceIn_range,
        kk_double_coerceAtLeast_range,
        kk_double_coerceAtMost_range,
        kk_float_coerceIn_range,
        kk_float_coerceAtLeast_range,
        kk_float_coerceAtMost_range,
        kk_string_builder_replace_obj,
        kk_string_builder_setCharAt,
        kk_string_builder_capacity,
        kk_string_builder_ensureCapacity,
        kk_string_builder_trimToSize,
        kk_string_mapIndexed,
        kk_string_mapNotNull,
        kk_string_filterIndexed,
        kk_string_filterNot,
        kk_string_takeWhile,
        kk_string_dropWhile,
        kk_string_splitToSequence,
        kk_string_joinToString,
        kk_string_find,
        kk_string_findLast,
        kk_coroutine_scope_is_active,
        kk_coroutine_scope_is_cancelled,
        kk_coroutine_scope_get_parent,
    ]

    static let abiParityExternsPart2: [ExternDecl] = [
        kk_coroutine_scope_cancel_propagate,
        kk_op_eq,
        kk_op_ne,
        kk_op_lt,
        kk_op_le,
        kk_op_gt,
        kk_op_ge,
        kk_op_floor_div,
        kk_op_lfloor_div,
        kk_op_mod,
        kk_op_lmod,
        kk_op_floor_mod,
        kk_op_lfloor_mod,
        kk_logical_and,
        kk_logical_or,
        kk_char_minus,
        kk_char_plus,
        kk_char_get,
        kk_char_rangeTo,
    ]

    static let abiParityExternsPart3: [ExternDecl] = []

    static let abiParityExternsPart4: [ExternDecl] = []

    static let abiParityExternsPart5: [ExternDecl] = []

    static let abiParityExterns: [ExternDecl] = abiParityExternsPart1 + abiParityExternsPart2 + abiParityExternsPart3 + abiParityExternsPart4 + abiParityExternsPart5
}
