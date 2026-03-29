// KFunction reflection extern declarations (STDLIB-REFLECT-063)
//
// These runtime functions create and query `kotlin.reflect.KFunction` objects
// with full reflection metadata: name, arity, returnType, parameters,
// isSuspend, and direct call() dispatch.

public extension RuntimeABIExterns {
    /// Creates a KFunction runtime box.
    /// Signature: kk_kfunction_create(name, arity, returnType, isSuspend, fnPtr, closureRaw) -> handle
    static let kk_kfunction_create = ExternDecl(
        name: "kk_kfunction_create",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t", "intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    /// Returns the function name as a KKString raw pointer.
    /// Signature: kk_kfunction_get_name(handle) -> name_string
    static let kk_kfunction_get_name = ExternDecl(
        name: "kk_kfunction_get_name",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    /// Returns the arity (number of value parameters).
    /// Signature: kk_kfunction_get_arity(handle) -> intptr_t
    static let kk_kfunction_get_arity = ExternDecl(
        name: "kk_kfunction_get_arity",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    /// Returns the return type descriptor as a KKString raw pointer.
    /// Signature: kk_kfunction_get_return_type(handle) -> type_string
    static let kk_kfunction_get_return_type = ExternDecl(
        name: "kk_kfunction_get_return_type",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    /// Returns 1 if the function is declared suspend, 0 otherwise.
    /// Signature: kk_kfunction_is_suspend(handle) -> intptr_t
    static let kk_kfunction_is_suspend = ExternDecl(
        name: "kk_kfunction_is_suspend",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    /// Returns the value-parameter list as a runtime List of descriptor strings.
    /// Signature: kk_kfunction_get_parameters(handle) -> list_handle
    static let kk_kfunction_get_parameters = ExternDecl(
        name: "kk_kfunction_get_parameters",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    /// Invokes the KFunction with zero arguments.
    /// Signature: kk_kfunction_call_0(handle, outThrown*) -> intptr_t
    static let kk_kfunction_call_0 = ExternDecl(
        name: "kk_kfunction_call_0",
        parameterTypes: ["intptr_t", "intptr_t*"],
        returnType: "intptr_t"
    )

    /// Invokes the KFunction with one argument.
    /// Signature: kk_kfunction_call_1(handle, arg, outThrown*) -> intptr_t
    static let kk_kfunction_call_1 = ExternDecl(
        name: "kk_kfunction_call_1",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t*"],
        returnType: "intptr_t"
    )

    /// Invokes the KFunction with two arguments.
    /// Signature: kk_kfunction_call_2(handle, arg1, arg2, outThrown*) -> intptr_t
    static let kk_kfunction_call_2 = ExternDecl(
        name: "kk_kfunction_call_2",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t*"],
        returnType: "intptr_t"
    )

    /// Combined array for use in `allExterns` concatenation.
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
    ]
}
