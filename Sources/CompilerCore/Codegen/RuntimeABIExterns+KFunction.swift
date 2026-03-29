// MARK: - KFunction / KProperty / KConstructor dynamic call (STDLIB-REFLECT-067)

public extension RuntimeABIExterns {
    static let kFunctionExterns: [ExternDecl] = [
        kk_kfunction_create,
        kk_kfunction_get_name,
        kk_kfunction_get_arity,
        kk_kfunction_get_return_type,
        kk_kfunction_is_suspend,
        kk_kfunction_get_parameters,
        kk_kfunction_call_0,
        kk_kfunction_call_1,
        kk_kfunction_call_2,
        kk_kfunction_call_3,
        kk_kfunction_call_vararg,
        kk_kproperty_get,
        kk_kproperty_set,
        kk_kconstructor_call_0,
        kk_kconstructor_call_1,
        kk_kconstructor_call_vararg,
    ]

    // MARK: - KFunction factory

    static let kk_kfunction_create = ExternDecl(
        name: "kk_kfunction_create",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t", "intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    // MARK: - KFunction accessors

    static let kk_kfunction_get_name = ExternDecl(
        name: "kk_kfunction_get_name",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_kfunction_get_arity = ExternDecl(
        name: "kk_kfunction_get_arity",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_kfunction_get_return_type = ExternDecl(
        name: "kk_kfunction_get_return_type",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_kfunction_is_suspend = ExternDecl(
        name: "kk_kfunction_is_suspend",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    static let kk_kfunction_get_parameters = ExternDecl(
        name: "kk_kfunction_get_parameters",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    // MARK: - KFunction.call() overloads

    /// KFunction.call() with 0 arguments.
    /// Signature: (kfunctionRaw: intptr_t, outThrown: intptr_t*) -> intptr_t
    static let kk_kfunction_call_0 = ExternDecl(
        name: "kk_kfunction_call_0",
        parameterTypes: ["intptr_t", "intptr_t*"],
        returnType: "intptr_t"
    )

    /// KFunction.call(arg) with 1 argument.
    static let kk_kfunction_call_1 = ExternDecl(
        name: "kk_kfunction_call_1",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t*"],
        returnType: "intptr_t"
    )

    /// KFunction.call(arg1, arg2) with 2 arguments.
    static let kk_kfunction_call_2 = ExternDecl(
        name: "kk_kfunction_call_2",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t*"],
        returnType: "intptr_t"
    )

    /// KFunction.call(arg1, arg2, arg3) with 3 arguments.
    static let kk_kfunction_call_3 = ExternDecl(
        name: "kk_kfunction_call_3",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t", "intptr_t*"],
        returnType: "intptr_t"
    )

    /// KFunction.call(vararg args) — dispatch via runtime List.
    static let kk_kfunction_call_vararg = ExternDecl(
        name: "kk_kfunction_call_vararg",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t*"],
        returnType: "intptr_t"
    )

    // MARK: - KProperty.get / KProperty.set

    static let kk_kproperty_get = ExternDecl(
        name: "kk_kproperty_get",
        parameterTypes: ["intptr_t", "intptr_t*"],
        returnType: "intptr_t"
    )

    static let kk_kproperty_set = ExternDecl(
        name: "kk_kproperty_set",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t*"],
        returnType: "intptr_t"
    )

    // MARK: - KConstructor.call() overloads

    static let kk_kconstructor_call_0 = ExternDecl(
        name: "kk_kconstructor_call_0",
        parameterTypes: ["intptr_t", "intptr_t*"],
        returnType: "intptr_t"
    )

    static let kk_kconstructor_call_1 = ExternDecl(
        name: "kk_kconstructor_call_1",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t*"],
        returnType: "intptr_t"
    )

    static let kk_kconstructor_call_vararg = ExternDecl(
        name: "kk_kconstructor_call_vararg",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t*"],
        returnType: "intptr_t"
    )
}
