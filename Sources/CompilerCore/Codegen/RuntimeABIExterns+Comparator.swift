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

    static let kk_comparator_then_by = ExternDecl(
        name: "kk_comparator_then_by",
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

    static let comparatorExterns: [ExternDecl] = [
        kk_comparator_from_selector,
        kk_comparator_from_selector_descending,
        kk_comparator_from_selector_trampoline,
        kk_comparator_from_selector_descending_trampoline,
        kk_comparator_then_by,
        kk_comparator_then_by_trampoline,
        kk_comparator_then_by_descending_trampoline,
        kk_comparator_reversed,
        kk_comparator_reversed_trampoline,
        kk_comparator_natural_order_trampoline,
        kk_comparator_reverse_order_trampoline,
        kk_comparator_natural_order,
        kk_comparator_reverse_order,
    ]
}
