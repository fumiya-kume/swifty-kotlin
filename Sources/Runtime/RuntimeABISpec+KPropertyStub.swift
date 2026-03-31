// KProperty stub ABI specs (PROP-007, STDLIB-REFLECT-062)

public extension RuntimeABISpec {
    /// KProperty stub functions used by the provideDelegate operator and KProperty reflection.
    static let kPropertyStubFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_kproperty_stub_create",
            parameters: [
                RuntimeABIParameter(name: "nameStr", type: .intptr),
                RuntimeABIParameter(name: "returnTypeStr", type: .intptr),
            ],
            returnType: .intptr,
            section: "Delegate"
        ),
        // STDLIB-REFLECT-062: full create with visibility/isLateinit/isConst
        RuntimeABIFunctionSpec(
            name: "kk_kproperty_stub_create_full",
            parameters: [
                RuntimeABIParameter(name: "nameStr", type: .intptr),
                RuntimeABIParameter(name: "returnTypeStr", type: .intptr),
                RuntimeABIParameter(name: "visibilityStr", type: .intptr),
                RuntimeABIParameter(name: "isLateinit", type: .intptr),
                RuntimeABIParameter(name: "isConst", type: .intptr),
            ],
            returnType: .intptr,
            section: "Delegate"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kproperty_stub_name",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Delegate"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kproperty_stub_return_type",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Delegate"
        ),
        // STDLIB-REFLECT-062: visibility, isLateinit, isConst
        RuntimeABIFunctionSpec(
            name: "kk_kproperty_stub_visibility",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Delegate"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kproperty_stub_is_lateinit",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Delegate"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kproperty_stub_is_const",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Delegate"
        ),
        // STDLIB-REFLECT-062: getter/setter registration
        RuntimeABIFunctionSpec(
            name: "kk_kproperty_stub_set_getter",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "receiver", type: .intptr),
            ],
            returnType: .intptr,
            section: "Delegate"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kproperty_stub_set_setter",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
            ],
            returnType: .intptr,
            section: "Delegate"
        ),
        // STDLIB-REFLECT-062: getter/setter handle accessors
        RuntimeABIFunctionSpec(
            name: "kk_kproperty_stub_getter",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Delegate"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kproperty_stub_setter",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Delegate"
        ),
        // STDLIB-REFLECT-062: get()/set() value via stored accessor
        RuntimeABIFunctionSpec(
            name: "kk_kproperty_stub_get_value",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Delegate"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kproperty_stub_set_value",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Delegate"
        ),
    ]
}
