// KFunction / KProperty / KConstructor / KParameter / CallableRef ABI specs
// (STDLIB-REFLECT-063 / STDLIB-REFLECT-067 / REFL-003)

public extension RuntimeABISpec {
    /// KParameter reflection runtime functions (STDLIB-REFLECT-063).
    static let kParameterFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_kparameter_create",
            parameters: [
                RuntimeABIParameter(name: "index", type: .intptr),
                RuntimeABIParameter(name: "nameRaw", type: .intptr),
                RuntimeABIParameter(name: "typeRaw", type: .intptr),
                RuntimeABIParameter(name: "isOptional", type: .intptr),
                RuntimeABIParameter(name: "kind", type: .intptr),
            ],
            returnType: .intptr,
            section: "Reflection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kparameter_get_index",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Reflection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kparameter_get_name",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Reflection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kparameter_get_type",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Reflection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kparameter_is_optional",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Reflection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kparameter_get_kind",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Reflection"
        ),
    ]

    /// KFunction, KProperty, and KConstructor reflection runtime functions.
    static let kFunctionFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_kfunction_create",
            parameters: [
                RuntimeABIParameter(name: "nameRaw", type: .intptr),
                RuntimeABIParameter(name: "arity", type: .intptr),
                RuntimeABIParameter(name: "returnTypeRaw", type: .intptr),
                RuntimeABIParameter(name: "isSuspend", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Reflection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kfunction_create_full",
            parameters: [
                RuntimeABIParameter(name: "nameRaw", type: .intptr),
                RuntimeABIParameter(name: "arity", type: .intptr),
                RuntimeABIParameter(name: "returnTypeRaw", type: .intptr),
                RuntimeABIParameter(name: "isSuspend", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "paramListRaw", type: .intptr),
                RuntimeABIParameter(name: "typeStringRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Reflection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kfunction_get_name",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Reflection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kfunction_get_arity",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Reflection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kfunction_get_return_type",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Reflection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kfunction_is_suspend",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Reflection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kfunction_get_parameters",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Reflection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kfunction_get_value_parameters",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Reflection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kfunction_get_type",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Reflection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kfunction_call_0",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Reflection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kfunction_call_1",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
                RuntimeABIParameter(name: "arg", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Reflection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kfunction_call_2",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
                RuntimeABIParameter(name: "arg1", type: .intptr),
                RuntimeABIParameter(name: "arg2", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Reflection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kfunction_call_3",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
                RuntimeABIParameter(name: "arg1", type: .intptr),
                RuntimeABIParameter(name: "arg2", type: .intptr),
                RuntimeABIParameter(name: "arg3", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Reflection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kfunction_call_vararg",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
                RuntimeABIParameter(name: "argsListRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Reflection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kproperty_get",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Reflection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kproperty_set",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Reflection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kconstructor_create",
            parameters: [
                RuntimeABIParameter(name: "nameRaw", type: .intptr),
                RuntimeABIParameter(name: "arity", type: .intptr),
                RuntimeABIParameter(name: "returnTypeRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "isPrimary", type: .intptr),
                RuntimeABIParameter(name: "visibilityRaw", type: .intptr),
                RuntimeABIParameter(name: "declaringClassRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Reflection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kconstructor_get_name",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Reflection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kconstructor_get_arity",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Reflection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kconstructor_get_return_type",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Reflection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kconstructor_is_primary",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Reflection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kconstructor_get_visibility",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Reflection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kconstructor_get_parameters",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Reflection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kconstructor_get_value_parameters",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Reflection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kconstructor_call_0",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Reflection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kconstructor_call_1",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
                RuntimeABIParameter(name: "arg0", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Reflection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kconstructor_call_2",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
                RuntimeABIParameter(name: "arg0", type: .intptr),
                RuntimeABIParameter(name: "arg1", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Reflection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kconstructor_call_3",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
                RuntimeABIParameter(name: "arg0", type: .intptr),
                RuntimeABIParameter(name: "arg1", type: .intptr),
                RuntimeABIParameter(name: "arg2", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Reflection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kconstructor_call_vararg",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
                RuntimeABIParameter(name: "argsList", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Reflection"
        ),
    ]

    /// Callable reference type identity functions (REFL-003).
    static let callableRefFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_callable_ref_tag_kfunction",
            parameters: [
                RuntimeABIParameter(name: "callable", type: .intptr),
                RuntimeABIParameter(name: "name", type: .intptr),
                RuntimeABIParameter(name: "arity", type: .intptr),
                RuntimeABIParameter(name: "isSuspend", type: .intptr),
            ],
            returnType: .intptr,
            section: "Reflection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_callable_ref_tag_kproperty",
            parameters: [
                RuntimeABIParameter(name: "callable", type: .intptr),
                RuntimeABIParameter(name: "name", type: .intptr),
                RuntimeABIParameter(name: "arity", type: .intptr),
            ],
            returnType: .intptr,
            section: "Reflection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_callable_ref_name",
            parameters: [
                RuntimeABIParameter(name: "tagged", type: .intptr),
            ],
            returnType: .intptr,
            section: "Reflection"
        ),
    ]
}
