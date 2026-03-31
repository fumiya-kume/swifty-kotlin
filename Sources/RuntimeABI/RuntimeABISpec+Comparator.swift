public extension RuntimeABISpec {
    static let comparatorFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_comparator_from_selector",
            parameters: [
                RuntimeABIParameter(name: "selectorFn", type: .intptr),
                RuntimeABIParameter(name: "selectorClosure", type: .intptr),
            ],
            returnType: .intptr,
            section: "Comparator"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_comparator_from_selector_descending",
            parameters: [
                RuntimeABIParameter(name: "selectorFn", type: .intptr),
                RuntimeABIParameter(name: "selectorClosure", type: .intptr),
            ],
            returnType: .intptr,
            section: "Comparator"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_comparator_from_selector_trampoline",
            parameters: [
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "a", type: .intptr),
                RuntimeABIParameter(name: "b", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Comparator"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_comparator_from_selector_descending_trampoline",
            parameters: [
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "a", type: .intptr),
                RuntimeABIParameter(name: "b", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Comparator"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_comparator_from_multi_selectors",
            parameters: [
                RuntimeABIParameter(name: "sel1Fn", type: .intptr),
                RuntimeABIParameter(name: "sel1Closure", type: .intptr),
                RuntimeABIParameter(name: "sel2Fn", type: .intptr),
                RuntimeABIParameter(name: "sel2Closure", type: .intptr),
            ],
            returnType: .intptr,
            section: "Comparator"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_comparator_from_multi_selectors3",
            parameters: [
                RuntimeABIParameter(name: "sel1Fn", type: .intptr),
                RuntimeABIParameter(name: "sel1Closure", type: .intptr),
                RuntimeABIParameter(name: "sel2Fn", type: .intptr),
                RuntimeABIParameter(name: "sel2Closure", type: .intptr),
                RuntimeABIParameter(name: "sel3Fn", type: .intptr),
                RuntimeABIParameter(name: "sel3Closure", type: .intptr),
            ],
            returnType: .intptr,
            section: "Comparator"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_comparator_from_multi_selectors_trampoline",
            parameters: [
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "a", type: .intptr),
                RuntimeABIParameter(name: "b", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Comparator"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_comparator_then_by",
            parameters: [
                RuntimeABIParameter(name: "c1Fn", type: .intptr),
                RuntimeABIParameter(name: "c1Closure", type: .intptr),
                RuntimeABIParameter(name: "selectorFn", type: .intptr),
                RuntimeABIParameter(name: "selectorClosure", type: .intptr),
            ],
            returnType: .intptr,
            section: "Comparator"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_comparator_then_by_descending",
            parameters: [
                RuntimeABIParameter(name: "c1Fn", type: .intptr),
                RuntimeABIParameter(name: "c1Closure", type: .intptr),
                RuntimeABIParameter(name: "selectorFn", type: .intptr),
                RuntimeABIParameter(name: "selectorClosure", type: .intptr),
            ],
            returnType: .intptr,
            section: "Comparator"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_comparator_then_by_trampoline",
            parameters: [
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "a", type: .intptr),
                RuntimeABIParameter(name: "b", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Comparator"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_comparator_then_by_descending_trampoline",
            parameters: [
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "a", type: .intptr),
                RuntimeABIParameter(name: "b", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Comparator"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_comparator_nulls_first",
            parameters: [
                RuntimeABIParameter(name: "cFn", type: .intptr),
                RuntimeABIParameter(name: "cClosure", type: .intptr),
            ],
            returnType: .intptr,
            section: "Comparator"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_comparator_nulls_first_trampoline",
            parameters: [
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "a", type: .intptr),
                RuntimeABIParameter(name: "b", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Comparator"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_comparator_nulls_last",
            parameters: [
                RuntimeABIParameter(name: "cFn", type: .intptr),
                RuntimeABIParameter(name: "cClosure", type: .intptr),
            ],
            returnType: .intptr,
            section: "Comparator"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_comparator_nulls_last_trampoline",
            parameters: [
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "a", type: .intptr),
                RuntimeABIParameter(name: "b", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Comparator"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_comparator_reversed",
            parameters: [
                RuntimeABIParameter(name: "cFn", type: .intptr),
                RuntimeABIParameter(name: "cClosure", type: .intptr),
            ],
            returnType: .intptr,
            section: "Comparator"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_comparator_reversed_trampoline",
            parameters: [
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "a", type: .intptr),
                RuntimeABIParameter(name: "b", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Comparator"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_comparator_natural_order_trampoline",
            parameters: [
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "a", type: .intptr),
                RuntimeABIParameter(name: "b", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Comparator"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_comparator_reverse_order_trampoline",
            parameters: [
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "a", type: .intptr),
                RuntimeABIParameter(name: "b", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Comparator"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_comparator_natural_order",
            parameters: [],
            returnType: .intptr,
            section: "Comparator"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_comparator_reverse_order",
            parameters: [],
            returnType: .intptr,
            section: "Comparator"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_compareValues",
            parameters: [
                RuntimeABIParameter(name: "a", type: .intptr),
                RuntimeABIParameter(name: "b", type: .intptr),
            ],
            returnType: .intptr,
            section: "Comparator"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_compareValuesBy1",
            parameters: [
                RuntimeABIParameter(name: "a", type: .intptr),
                RuntimeABIParameter(name: "b", type: .intptr),
                RuntimeABIParameter(name: "selectorFn", type: .intptr),
                RuntimeABIParameter(name: "selectorClosure", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Comparator"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_compareValuesBy",
            parameters: [
                RuntimeABIParameter(name: "a", type: .intptr),
                RuntimeABIParameter(name: "b", type: .intptr),
                RuntimeABIParameter(name: "sel1Fn", type: .intptr),
                RuntimeABIParameter(name: "sel1Closure", type: .intptr),
                RuntimeABIParameter(name: "sel2Fn", type: .intptr),
                RuntimeABIParameter(name: "sel2Closure", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Comparator"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_compareValuesBy3",
            parameters: [
                RuntimeABIParameter(name: "a", type: .intptr),
                RuntimeABIParameter(name: "b", type: .intptr),
                RuntimeABIParameter(name: "sel1Fn", type: .intptr),
                RuntimeABIParameter(name: "sel1Closure", type: .intptr),
                RuntimeABIParameter(name: "sel2Fn", type: .intptr),
                RuntimeABIParameter(name: "sel2Closure", type: .intptr),
                RuntimeABIParameter(name: "sel3Fn", type: .intptr),
                RuntimeABIParameter(name: "sel3Closure", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Comparator"
        ),
    ]
}
