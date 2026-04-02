public extension RuntimeABIExterns {
    static let kk_comparator_from_selector = ExternDecl(
        name: "kk_comparator_from_selector",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_comparator_from_selector_descending = ExternDecl(
        name: "kk_comparator_from_selector_descending",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_comparator_from_selector_trampoline = ExternDecl(
        name: "kk_comparator_from_selector_trampoline",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_comparator_from_selector_descending_trampoline = ExternDecl(
        name: "kk_comparator_from_selector_descending_trampoline",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_comparator_from_multi_selectors = ExternDecl(
        name: "kk_comparator_from_multi_selectors",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_comparator_from_multi_selectors3 = ExternDecl(
        name: "kk_comparator_from_multi_selectors3",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t", "intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_comparator_from_multi_selectors_trampoline = ExternDecl(
        name: "kk_comparator_from_multi_selectors_trampoline",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_comparator_then_by = ExternDecl(
        name: "kk_comparator_then_by",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_comparator_then_by_descending = ExternDecl(
        name: "kk_comparator_then_by_descending",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_comparator_then_comparator = ExternDecl(
        name: "kk_comparator_then_comparator",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_comparator_then_by_trampoline = ExternDecl(
        name: "kk_comparator_then_by_trampoline",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_comparator_then_by_descending_trampoline = ExternDecl(
        name: "kk_comparator_then_by_descending_trampoline",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_comparator_then_comparator_trampoline = ExternDecl(
        name: "kk_comparator_then_comparator_trampoline",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_comparator_nulls_first = ExternDecl(
        name: "kk_comparator_nulls_first",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_comparator_nulls_first_trampoline = ExternDecl(
        name: "kk_comparator_nulls_first_trampoline",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_comparator_nulls_last = ExternDecl(
        name: "kk_comparator_nulls_last",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_comparator_nulls_last_trampoline = ExternDecl(
        name: "kk_comparator_nulls_last_trampoline",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_comparator_reversed = ExternDecl(
        name: "kk_comparator_reversed",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_comparator_reversed_trampoline = ExternDecl(
        name: "kk_comparator_reversed_trampoline",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_comparator_natural_order_trampoline = ExternDecl(
        name: "kk_comparator_natural_order_trampoline",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_comparator_reverse_order_trampoline = ExternDecl(
        name: "kk_comparator_reverse_order_trampoline",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_comparator_natural_order = ExternDecl(
        name: "kk_comparator_natural_order",
        parameterTypes: [],
        returnType: "intptr_t"
    )

    static let kk_comparator_reverse_order = ExternDecl(
        name: "kk_comparator_reverse_order",
        parameterTypes: [],
        returnType: "intptr_t"
    )

    static let kk_compareValues = ExternDecl(
        name: "kk_compareValues",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_compareValuesBy1 = ExternDecl(
        name: "kk_compareValuesBy1",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_compareValuesBy = ExternDecl(
        name: "kk_compareValuesBy",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let kk_compareValuesBy3 = ExternDecl(
        name: "kk_compareValuesBy3",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t", "intptr_t", "intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    static let comparatorExterns: [ExternDecl] = [
        kk_comparator_from_selector,
        kk_comparator_from_selector_descending,
        kk_comparator_from_selector_trampoline,
        kk_comparator_from_selector_descending_trampoline,
        kk_comparator_from_multi_selectors,
        kk_comparator_from_multi_selectors3,
        kk_comparator_from_multi_selectors_trampoline,
        kk_comparator_then_by,
        kk_comparator_then_by_descending,
        kk_comparator_then_comparator,
        kk_comparator_then_by_trampoline,
        kk_comparator_then_by_descending_trampoline,
        kk_comparator_then_comparator_trampoline,
        kk_comparator_nulls_first,
        kk_comparator_nulls_first_trampoline,
        kk_comparator_nulls_last,
        kk_comparator_nulls_last_trampoline,
        kk_comparator_reversed,
        kk_comparator_reversed_trampoline,
        kk_comparator_natural_order_trampoline,
        kk_comparator_reverse_order_trampoline,
        kk_comparator_natural_order,
        kk_comparator_reverse_order,
        kk_compareValues,
        kk_compareValuesBy1,
        kk_compareValuesBy,
        kk_compareValuesBy3,
    ]
}
