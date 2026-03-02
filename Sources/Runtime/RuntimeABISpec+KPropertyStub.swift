// KProperty stub ABI specs (PROP-007)

extension RuntimeABISpec {
    /// KProperty stub functions used by the provideDelegate operator.
    public static let kPropertyStubFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_kproperty_stub_create",
            parameters: [
                RuntimeABIParameter(name: "nameStr", type: .intptr),
                RuntimeABIParameter(name: "returnTypeStr", type: .intptr),
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
    ]
}
