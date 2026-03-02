// KProperty stub extern declarations (PROP-007)

public extension RuntimeABIExterns {
    // swiftlint:disable:next identifier_name
    static let kk_kproperty_stub_create = ExternDecl(
        name: "kk_kproperty_stub_create",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    // swiftlint:disable:next identifier_name
    static let kk_kproperty_stub_name = ExternDecl(
        name: "kk_kproperty_stub_name",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    // swiftlint:disable:next identifier_name
    static let kk_kproperty_stub_return_type = ExternDecl(
        name: "kk_kproperty_stub_return_type",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    /// Combined array for use in `allExterns` concatenation.
    static let kPropertyStubExterns: [ExternDecl] = [
        kk_kproperty_stub_create,
        kk_kproperty_stub_name,
        kk_kproperty_stub_return_type,
    ]
}
