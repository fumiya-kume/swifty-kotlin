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
    ]
}
