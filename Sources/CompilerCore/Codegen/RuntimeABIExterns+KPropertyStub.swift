// KProperty stub extern declarations (PROP-007, STDLIB-REFLECT-062)

public extension RuntimeABIExterns {
    static let kk_kproperty_stub_create = ExternDecl(
        name: "kk_kproperty_stub_create",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    // STDLIB-REFLECT-062: full create with visibility/isLateinit/isConst
    static let kk_kproperty_stub_create_full = ExternDecl(
        name: "kk_kproperty_stub_create_full",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_kproperty_stub_name = ExternDecl(
        name: "kk_kproperty_stub_name",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_kproperty_stub_return_type = ExternDecl(
        name: "kk_kproperty_stub_return_type",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    // STDLIB-REFLECT-062: visibility, isLateinit, isConst
    static let kk_kproperty_stub_visibility = ExternDecl(
        name: "kk_kproperty_stub_visibility",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_kproperty_stub_is_lateinit = ExternDecl(
        name: "kk_kproperty_stub_is_lateinit",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_kproperty_stub_is_const = ExternDecl(
        name: "kk_kproperty_stub_is_const",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    // STDLIB-REFLECT-062: getter/setter registration
    static let kk_kproperty_stub_set_getter = ExternDecl(
        name: "kk_kproperty_stub_set_getter",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_kproperty_stub_set_setter = ExternDecl(
        name: "kk_kproperty_stub_set_setter",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    // STDLIB-REFLECT-062: getter/setter handle accessors
    static let kk_kproperty_stub_getter = ExternDecl(
        name: "kk_kproperty_stub_getter",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_kproperty_stub_setter = ExternDecl(
        name: "kk_kproperty_stub_setter",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    // STDLIB-REFLECT-062: get()/set() value via stored accessor
    static let kk_kproperty_stub_get_value = ExternDecl(
        name: "kk_kproperty_stub_get_value",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_kproperty_stub_set_value = ExternDecl(
        name: "kk_kproperty_stub_set_value",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    /// Combined array for use in `allExterns` concatenation.
    static let kPropertyStubExterns: [ExternDecl] = [
        kk_kproperty_stub_create,
        kk_kproperty_stub_create_full,
        kk_kproperty_stub_name,
        kk_kproperty_stub_return_type,
        // STDLIB-REFLECT-062
        kk_kproperty_stub_visibility,
        kk_kproperty_stub_is_lateinit,
        kk_kproperty_stub_is_const,
        kk_kproperty_stub_set_getter,
        kk_kproperty_stub_set_setter,
        kk_kproperty_stub_getter,
        kk_kproperty_stub_setter,
        kk_kproperty_stub_get_value,
        kk_kproperty_stub_set_value,
    ]
}
