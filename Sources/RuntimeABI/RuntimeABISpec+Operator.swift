// swiftlint:disable file_length

/// `RuntimeABISpec.operatorFunctions` extracted from `RuntimeABISpec.swift`.
public extension RuntimeABISpec {

    static let operatorFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_type_register_super",
            parameters: [
                RuntimeABIParameter(name: "childTypeId", type: .intptr),
                RuntimeABIParameter(name: "superTypeId", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_type_register_iface",
            parameters: [
                RuntimeABIParameter(name: "childTypeId", type: .intptr),
                RuntimeABIParameter(name: "ifaceTypeId", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_object_register_itable_iface",
            parameters: [
                RuntimeABIParameter(name: "objectRaw", type: .intptr),
                RuntimeABIParameter(name: "ifaceTypeId", type: .intptr),
                RuntimeABIParameter(name: "ifaceSlot", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_object_register_itable_method",
            parameters: [
                RuntimeABIParameter(name: "objectRaw", type: .intptr),
                RuntimeABIParameter(name: "ifaceSlot", type: .intptr),
                RuntimeABIParameter(name: "methodSlot", type: .intptr),
                RuntimeABIParameter(name: "functionRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_object_register_vtable_method",
            parameters: [
                RuntimeABIParameter(name: "objectRaw", type: .intptr),
                RuntimeABIParameter(name: "methodSlot", type: .intptr),
                RuntimeABIParameter(name: "functionRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_object_register_equals_override",
            parameters: [
                RuntimeABIParameter(name: "objectRaw", type: .intptr),
                RuntimeABIParameter(name: "functionRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_type_token_simple_name",
            parameters: [
                RuntimeABIParameter(name: "typeToken", type: .intptr),
                RuntimeABIParameter(name: "nameHint", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_type_token_qualified_name",
            parameters: [
                RuntimeABIParameter(name: "typeToken", type: .intptr),
                RuntimeABIParameter(name: "nameHint", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kclass_create",
            parameters: [
                RuntimeABIParameter(name: "typeToken", type: .intptr),
                RuntimeABIParameter(name: "nameHint", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck",
            isThrowing: false
        ),
        // KSP-496: KClass-handle-based simpleName/qualifiedName bridges (used by
        // Sources/CompilerCore/Stdlib/kotlin/reflect/KClassBasicAPI.kt).
        RuntimeABIFunctionSpec(
            name: "__kk_kclass_simple_name",
            parameters: [
                RuntimeABIParameter(name: "kclassRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kclass_qualified_name",
            parameters: [
                RuntimeABIParameter(name: "kclassRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck"
        ),
        // REFL-004: KClass binary metadata registration and accessors
        RuntimeABIFunctionSpec(
            name: "__kk_kclass_register_metadata",
            parameters: [
                RuntimeABIParameter(name: "typeToken", type: .intptr),
                RuntimeABIParameter(name: "qualifiedNameRaw", type: .intptr),
                RuntimeABIParameter(name: "simpleNameRaw", type: .intptr),
                RuntimeABIParameter(name: "supertypeNameRaw", type: .intptr),
                RuntimeABIParameter(name: "flags", type: .intptr),
                RuntimeABIParameter(name: "fieldCount", type: .intptr),
                RuntimeABIParameter(name: "memberCount", type: .intptr),
                RuntimeABIParameter(name: "constructorCount", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kclass_is_data",
            parameters: [
                RuntimeABIParameter(name: "kclassRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kclass_is_sealed",
            parameters: [
                RuntimeABIParameter(name: "kclassRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kclass_is_value",
            parameters: [
                RuntimeABIParameter(name: "kclassRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kclass_is_interface",
            parameters: [
                RuntimeABIParameter(name: "kclassRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kclass_is_object",
            parameters: [
                RuntimeABIParameter(name: "kclassRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kclass_is_enum",
            parameters: [
                RuntimeABIParameter(name: "kclassRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kclass_is_abstract",
            parameters: [
                RuntimeABIParameter(name: "kclassRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck",
            isThrowing: false
        ),
        // STDLIB-REFLECT-067: KClass type-kind introspection
        RuntimeABIFunctionSpec(
            name: "__kk_kclass_is_inner",
            parameters: [
                RuntimeABIParameter(name: "kclassRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kclass_is_companion",
            parameters: [
                RuntimeABIParameter(name: "kclassRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kclass_is_fun",
            parameters: [
                RuntimeABIParameter(name: "kclassRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck",
            isThrowing: false
        ),
        // STDLIB-REFLECT-065: Annotation reflection
        RuntimeABIFunctionSpec(
            name: "__kk_kclass_get_annotations",
            parameters: [
                RuntimeABIParameter(name: "kclassRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Reflection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kclass_find_annotation",
            parameters: [
                RuntimeABIParameter(name: "kclassRaw", type: .intptr),
                RuntimeABIParameter(name: "nameRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Reflection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kclass_find_associated_object",
            parameters: [
                RuntimeABIParameter(name: "kclassRaw", type: .intptr),
                RuntimeABIParameter(name: "keyNameRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Reflection",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kclass_register_single_annotation",
            parameters: [
                RuntimeABIParameter(name: "typeToken", type: .intptr),
                RuntimeABIParameter(name: "fqNameRaw", type: .intptr),
                RuntimeABIParameter(name: "argsEncodedRaw", type: .intptr),
                RuntimeABIParameter(name: "argCount", type: .intptr),
            ],
            returnType: .intptr,
            section: "Reflection",
            isThrowing: false
        ),
        // REFL-005: KClass.isInstance, members, constructors
        RuntimeABIFunctionSpec(
            name: "__kk_kclass_isInstance",
            parameters: [
                RuntimeABIParameter(name: "kclassRaw", type: .intptr),
                RuntimeABIParameter(name: "valueRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kclass_cast",
            parameters: [
                RuntimeABIParameter(name: "kclassRaw", type: .intptr),
                RuntimeABIParameter(name: "valueRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "TypeCheck"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kclass_safeCast",
            parameters: [
                RuntimeABIParameter(name: "kclassRaw", type: .intptr),
                RuntimeABIParameter(name: "valueRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kclass_members",
            parameters: [
                RuntimeABIParameter(name: "kclassRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kclass_constructors",
            parameters: [
                RuntimeABIParameter(name: "kclassRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck"
        ),
        // MIGRATION-REFLECT-002: KClass.nestedClasses
        RuntimeABIFunctionSpec(
            name: "__kk_kclass_nested_classes",
            parameters: [
                RuntimeABIParameter(name: "kclassRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck"
        ),
        // STDLIB-REFLECT-064: KClass.primaryConstructor
        RuntimeABIFunctionSpec(
            name: "__kk_kclass_primary_constructor",
            parameters: [
                RuntimeABIParameter(name: "kclassRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck"
        ),

        // STDLIB-REFLECT-061: KClass member access
        RuntimeABIFunctionSpec(
            name: "__kk_kclass_properties",
            parameters: [
                RuntimeABIParameter(name: "kclassRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kclass_member_properties",
            parameters: [
                RuntimeABIParameter(name: "kclassRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kclass_declared_member_properties",
            parameters: [
                RuntimeABIParameter(name: "kclassRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kclass_functions",
            parameters: [
                RuntimeABIParameter(name: "kclassRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kclass_member_functions",
            parameters: [
                RuntimeABIParameter(name: "kclassRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kclass_declared_member_functions",
            parameters: [
                RuntimeABIParameter(name: "kclassRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck"
        ),
        // REFL-005: KType and typeOf<T>()
        RuntimeABIFunctionSpec(
            name: "__kk_ktype_classifier",
            parameters: [
                RuntimeABIParameter(name: "ktypeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_ktype_arguments",
            parameters: [
                RuntimeABIParameter(name: "ktypeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_ktype_isMarkedNullable",
            parameters: [
                RuntimeABIParameter(name: "ktypeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_ktypeprojection_create",
            parameters: [
                RuntimeABIParameter(name: "typeRaw", type: .intptr),
                RuntimeABIParameter(name: "varianceOrdinal", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_ktypeprojection_create_checked",
            parameters: [
                RuntimeABIParameter(name: "varianceOrdinal", type: .intptr),
                RuntimeABIParameter(name: "typeRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "TypeCheck",
            isThrowing: true
        ),
        RuntimeABIFunctionSpec(
            name: "kk_typeof",
            parameters: [
                RuntimeABIParameter(name: "typeToken", type: .intptr),
                RuntimeABIParameter(name: "nameHint", type: .intptr),
                RuntimeABIParameter(name: "argsRaw", type: .intptr),
                RuntimeABIParameter(name: "isNullable", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_op_is",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "typeToken", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_op_cast",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "typeToken", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "TypeCheck"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_op_safe_cast",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "typeToken", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_op_contains",
            parameters: [
                RuntimeABIParameter(name: "container", type: .intptr),
                RuntimeABIParameter(name: "element", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck",
            isThrowing: false
        ),
    ]

    /// Stdlib Delegate Functions (P5-80)
}
