// Callable reference type identity extern declarations (REFL-003)
//
// These runtime functions tag callable reference values with KFunction /
// KProperty type identity so that reflection APIs (`is KFunction<*>`,
// `is KProperty<*>`) work correctly.
//
// Each function takes the callable value (intptr_t) plus a name string
// and an arity, and returns the tagged callable value.

public extension RuntimeABIExterns {
    /// Tags a callable value as a KFunction reference.
    /// Signature: kk_callable_ref_tag_kfunction(callable, name, arity) -> tagged
    static let kk_callable_ref_tag_kfunction = ExternDecl(
        name: "kk_callable_ref_tag_kfunction",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t"],
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

    /// Combined array for use in `allExterns` concatenation.
    static let callableRefExterns: [ExternDecl] = [
        kk_callable_ref_tag_kfunction,
        kk_callable_ref_tag_kproperty,
        kk_callable_ref_name,
    ]
}
