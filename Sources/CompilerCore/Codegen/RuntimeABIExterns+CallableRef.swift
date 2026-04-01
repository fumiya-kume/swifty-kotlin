// Callable reference type identity extern declarations (REFL-003)
//
// These runtime functions tag callable reference values with KFunction /
// KProperty type identity so that reflection APIs (`is KFunction<*>`,
// `is KProperty<*>`) work correctly.
//
// Each function takes the callable value (intptr_t) plus a name string
// and an arity, and returns the tagged callable value.

public extension RuntimeABIExterns {
    /// Tags a callable value as a KFunction reference, recording whether it is suspend.
    /// Signature: kk_callable_ref_tag_kfunction(callable, name, arity, isSuspend) -> tagged
    static let kk_callable_ref_tag_kfunction = ExternDecl(
        name: "kk_callable_ref_tag_kfunction",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    /// Tags a callable value as a KProperty reference.
    /// Signature: kk_callable_ref_tag_kproperty(callable, name, arity) -> tagged
    static let kk_callable_ref_tag_kproperty = ExternDecl(
        name: "kk_callable_ref_tag_kproperty",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    /// Queries the `name` property of a KFunction/KProperty reference.
    /// Signature: kk_callable_ref_name(tagged) -> name_string
    static let kk_callable_ref_name = ExternDecl(
        name: "kk_callable_ref_name",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    /// Returns the arity (number of value parameters) of the callable ref (STDLIB-REFLECT-063).
    /// Signature: kk_callable_ref_arity(tagged) -> intptr_t
    static let kk_callable_ref_arity = ExternDecl(
        name: "kk_callable_ref_arity",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    /// Returns 1 if the callable ref is a suspend function, 0 otherwise (STDLIB-REFLECT-063).
    /// Signature: kk_callable_ref_is_suspend(tagged) -> intptr_t
    static let kk_callable_ref_is_suspend = ExternDecl(
        name: "kk_callable_ref_is_suspend",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    /// Returns the value-parameter list as a runtime List (STDLIB-REFLECT-063).
    /// Signature: kk_callable_ref_parameters(tagged) -> list_handle
    static let kk_callable_ref_parameters = ExternDecl(
        name: "kk_callable_ref_parameters",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    /// Invokes a callable ref with zero arguments (STDLIB-REFLECT-063).
    /// Signature: kk_callable_ref_call_0(tagged, outThrown) -> result
    static let kk_callable_ref_call_0 = ExternDecl(
        name: "kk_callable_ref_call_0",
        parameterTypes: ["intptr_t", "intptr_t*"],
        returnType: "intptr_t"
    )

    /// Invokes a callable ref with one argument (STDLIB-REFLECT-063).
    /// Signature: kk_callable_ref_call_1(tagged, arg, outThrown) -> result
    static let kk_callable_ref_call_1 = ExternDecl(
        name: "kk_callable_ref_call_1",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t*"],
        returnType: "intptr_t"
    )

    /// Invokes a callable ref with two arguments (STDLIB-REFLECT-063).
    /// Signature: kk_callable_ref_call_2(tagged, arg1, arg2, outThrown) -> result
    static let kk_callable_ref_call_2 = ExternDecl(
        name: "kk_callable_ref_call_2",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t*"],
        returnType: "intptr_t"
    )

    /// Invokes a callable ref with three arguments (STDLIB-REFLECT-063).
    /// Signature: kk_callable_ref_call_3(tagged, arg1, arg2, arg3, outThrown) -> result
    static let kk_callable_ref_call_3 = ExternDecl(
        name: "kk_callable_ref_call_3",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t", "intptr_t*"],
        returnType: "intptr_t"
    )

    /// Combined array for use in `allExterns` concatenation.
    static let callableRefExterns: [ExternDecl] = [
        kk_callable_ref_tag_kfunction,
        kk_callable_ref_tag_kproperty,
        kk_callable_ref_name,
        kk_callable_ref_arity,
        kk_callable_ref_is_suspend,
        kk_callable_ref_parameters,
        kk_callable_ref_call_0,
        kk_callable_ref_call_1,
        kk_callable_ref_call_2,
        kk_callable_ref_call_3,
    ]
}
