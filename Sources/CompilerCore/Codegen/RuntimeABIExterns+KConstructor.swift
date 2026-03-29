// KConstructor reflection extern declarations (STDLIB-REFLECT-064)
//
// These runtime functions create and query `kotlin.reflect.KConstructor` objects
// with full reflection metadata: parameters, valueParameters, visibility, isPrimary,
// and direct call() dispatch for primary and secondary constructors.

public extension RuntimeABIExterns {
    /// Creates a KConstructor runtime box.
    /// Signature: kk_kconstructor_create(kclassRaw, fnPtr, parameterCount, visibilityOrdinal, isPrimary) -> handle
    static let kk_kconstructor_create = ExternDecl(
        name: "kk_kconstructor_create",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    /// Returns the parameters list as a runtime List of KParameter handles.
    /// Signature: kk_kconstructor_get_parameters(handle) -> list_handle
    static let kk_kconstructor_get_parameters = ExternDecl(
        name: "kk_kconstructor_get_parameters",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    /// Returns the value-parameters list (alias for parameters, excluding receivers).
    /// Signature: kk_kconstructor_get_value_parameters(handle) -> list_handle
    static let kk_kconstructor_get_value_parameters = ExternDecl(
        name: "kk_kconstructor_get_value_parameters",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    /// Returns the visibility ordinal (0=public, 1=protected, 2=internal, 3=private).
    /// Signature: kk_kconstructor_get_visibility(handle) -> intptr_t
    static let kk_kconstructor_get_visibility = ExternDecl(
        name: "kk_kconstructor_get_visibility",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    /// Returns 1 if this is the primary constructor, 0 for secondary.
    /// Signature: kk_kconstructor_is_primary(handle) -> intptr_t
    static let kk_kconstructor_is_primary = ExternDecl(
        name: "kk_kconstructor_is_primary",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    /// Invokes the KConstructor with zero arguments.
    /// Signature: kk_kconstructor_call_0(handle, outThrown*) -> intptr_t
    static let kk_kconstructor_call_0 = ExternDecl(
        name: "kk_kconstructor_call_0",
        parameterTypes: ["intptr_t", "intptr_t*"],
        returnType: "intptr_t"
    )

    /// Invokes the KConstructor with one argument.
    /// Signature: kk_kconstructor_call_1(handle, arg, outThrown*) -> intptr_t
    static let kk_kconstructor_call_1 = ExternDecl(
        name: "kk_kconstructor_call_1",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t*"],
        returnType: "intptr_t"
    )

    /// Invokes the KConstructor with two arguments.
    /// Signature: kk_kconstructor_call_2(handle, arg1, arg2, outThrown*) -> intptr_t
    static let kk_kconstructor_call_2 = ExternDecl(
        name: "kk_kconstructor_call_2",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t*"],
        returnType: "intptr_t"
    )

    /// Creates a KParameter descriptor box.
    /// Signature: kk_kparameter_create(index, nameRaw, hasDefault) -> handle
    static let kk_kparameter_create = ExternDecl(
        name: "kk_kparameter_create",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    /// Returns the 0-based index of a KParameter.
    /// Signature: kk_kparameter_get_index(handle) -> intptr_t
    static let kk_kparameter_get_index = ExternDecl(
        name: "kk_kparameter_get_index",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    /// Returns the name of a KParameter as a KKString raw pointer, or null sentinel if unnamed.
    /// Signature: kk_kparameter_get_name(handle) -> name_string
    static let kk_kparameter_get_name = ExternDecl(
        name: "kk_kparameter_get_name",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    /// Returns 1 if the KParameter has a default value, 0 otherwise.
    /// Signature: kk_kparameter_has_default(handle) -> intptr_t
    static let kk_kparameter_has_default = ExternDecl(
        name: "kk_kparameter_has_default",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    /// Combined array for use in `allExterns` concatenation.
    static let kConstructorExterns: [ExternDecl] = [
        kk_kconstructor_create,
        kk_kconstructor_get_parameters,
        kk_kconstructor_get_value_parameters,
        kk_kconstructor_get_visibility,
        kk_kconstructor_is_primary,
        kk_kconstructor_call_0,
        kk_kconstructor_call_1,
        kk_kconstructor_call_2,
        kk_kparameter_create,
        kk_kparameter_get_index,
        kk_kparameter_get_name,
        kk_kparameter_has_default,
    ]
}
