// swiftlint:disable file_length
public enum RuntimeABICType: String, Equatable, Sendable {
    case void
    case uint32 = "uint32_t"
    case int32 = "int32_t"
    case intptr = "intptr_t"
    case opaquePointer = "void *"
    case nullableOpaquePointer = "void * _Nullable"
    case constUInt8Pointer = "const uint8_t *"
    case constCCharPointer = "const char *"
    case fieldAddrPointer = "void **"
    case constTypeInfoPointer = "const KTypeInfo *"
    case nullableRawPointerPointer = "void ** _Nullable"
    case int64 = "int64_t"
    case constRawPointer = "const void *"
    case nullableConstRawPointer = "const void * _Nullable"
    case nullableIntptrPointer = "intptr_t * _Nullable"
    case float = "float"
    case double = "double"
    case noreturn = "_Noreturn void"
}

public struct RuntimeABIParameter: Equatable, Sendable {
    public let name: String
    public let type: RuntimeABICType

    public init(name: String, type: RuntimeABICType) {
        self.name = name
        self.type = type
    }
}

public struct RuntimeABIFunctionSpec: Equatable, Sendable {
    public let name: String
    public let parameters: [RuntimeABIParameter]
    public let returnType: RuntimeABICType
    public let section: String

    public init(
        name: String,
        parameters: [RuntimeABIParameter],
        returnType: RuntimeABICType,
        section: String
    ) {
        self.name = name
        self.parameters = parameters
        self.returnType = returnType
        self.section = section
    }

    public var cDeclaration: String {
        let params: String = if parameters.isEmpty {
            "void"
        } else {
            parameters.map { "\($0.type.rawValue) \($0.name)" }.joined(separator: ", ")
        }
        return "\(returnType.rawValue) \(name)(\(params));"
    }

    /// Parameter types only (no names), for ABI reconciliation with `RuntimeABIExterns`.
    public var parameterTypeStrings: [String] {
        parameters.map(\.type.rawValue)
    }

    /// Return type as a raw C string, for ABI reconciliation.
    public var returnTypeString: String {
        returnType.rawValue
    }
}

// swiftlint:disable:next type_body_length
public enum RuntimeABISpec {
    public static let specVersion = "J32"

    public static let memoryFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_alloc",
            parameters: [
                RuntimeABIParameter(name: "size", type: .uint32),
                RuntimeABIParameter(name: "typeInfo", type: .constTypeInfoPointer),
            ],
            returnType: .opaquePointer,
            section: "Memory"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_gc_collect",
            parameters: [],
            returnType: .void,
            section: "Memory"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_write_barrier",
            parameters: [
                RuntimeABIParameter(name: "owner", type: .opaquePointer),
                RuntimeABIParameter(name: "fieldAddr", type: .fieldAddrPointer),
            ],
            returnType: .void,
            section: "Memory"
        ),
    ]

    public static let exceptionFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_throwable_new",
            parameters: [
                RuntimeABIParameter(name: "message", type: .nullableOpaquePointer),
            ],
            returnType: .opaquePointer,
            section: "Exception"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_throwable_new_with_cause",
            parameters: [
                RuntimeABIParameter(name: "message", type: .nullableOpaquePointer),
                RuntimeABIParameter(name: "causeRaw", type: .intptr),
            ],
            returnType: .opaquePointer,
            section: "Exception"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_no_when_branch_matched_exception_new",
            parameters: [],
            returnType: .intptr,
            section: "Exception"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_no_when_branch_matched_exception_new_message",
            parameters: [
                RuntimeABIParameter(name: "messageRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Exception"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_no_when_branch_matched_exception_new_message_cause",
            parameters: [
                RuntimeABIParameter(name: "messageRaw", type: .intptr),
                RuntimeABIParameter(name: "causeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Exception"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_no_when_branch_matched_exception_new_cause",
            parameters: [
                RuntimeABIParameter(name: "causeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Exception"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_concurrent_modification_exception_new",
            parameters: [],
            returnType: .intptr,
            section: "Exception"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_concurrent_modification_exception_new_message",
            parameters: [
                RuntimeABIParameter(name: "messageRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Exception"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_concurrent_modification_exception_new_message_cause",
            parameters: [
                RuntimeABIParameter(name: "messageRaw", type: .intptr),
                RuntimeABIParameter(name: "causeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Exception"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_concurrent_modification_exception_new_cause",
            parameters: [
                RuntimeABIParameter(name: "causeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Exception"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_array_index_out_of_bounds_exception_new",
            parameters: [],
            returnType: .intptr,
            section: "Exception"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_array_index_out_of_bounds_exception_new_message",
            parameters: [
                RuntimeABIParameter(name: "messageRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Exception"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_throwable_is_cancellation",
            parameters: [
                RuntimeABIParameter(name: "throwableRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Exception"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_panic",
            parameters: [
                RuntimeABIParameter(name: "cstr", type: .constCCharPointer),
            ],
            returnType: .noreturn,
            section: "Exception"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_abort_unreachable",
            parameters: [
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Exception"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_require",
            parameters: [
                RuntimeABIParameter(name: "condition", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Exception"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_check",
            parameters: [
                RuntimeABIParameter(name: "condition", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Exception"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_require_lazy",
            parameters: [
                RuntimeABIParameter(name: "condition", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Exception"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_synchronized",
            parameters: [
                RuntimeABIParameter(name: "lock", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Exception"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_reentrant_read_write_lock_read",
            parameters: [
                RuntimeABIParameter(name: "lock", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Exception"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_check_lazy",
            parameters: [
                RuntimeABIParameter(name: "condition", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Exception"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_precondition_assert",
            parameters: [
                RuntimeABIParameter(name: "condition", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Exception"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_precondition_assert_lazy",
            parameters: [
                RuntimeABIParameter(name: "condition", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Exception"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_assertions_enabled",
            parameters: [],
            returnType: .intptr,
            section: "Exception"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_assertions_set_enabled",
            parameters: [
                RuntimeABIParameter(name: "enabled", type: .intptr),
            ],
            returnType: .intptr,
            section: "Exception"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_assertions_reset",
            parameters: [],
            returnType: .intptr,
            section: "Exception"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_error",
            parameters: [
                RuntimeABIParameter(name: "message", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Exception"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_todo",
            parameters: [
                RuntimeABIParameter(name: "reason", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Exception"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_todo_noarg",
            parameters: [
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Exception"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_dispatch_error",
            parameters: [],
            returnType: .intptr,
            section: "Exception"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_throwable_message",
            parameters: [
                RuntimeABIParameter(name: "throwableRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Exception"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_throwable_cause",
            parameters: [
                RuntimeABIParameter(name: "throwableRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Exception"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_throwable_stackTraceToString",
            parameters: [
                RuntimeABIParameter(name: "throwableRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Exception"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_throwable_printStackTrace",
            parameters: [
                RuntimeABIParameter(name: "throwableRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Exception"
        ),
        // STDLIB-EXCEPT-105: Advanced exception handling
        RuntimeABIFunctionSpec(
            name: "kk_throwable_initCause",
            parameters: [
                RuntimeABIParameter(name: "throwableRaw", type: .intptr),
                RuntimeABIParameter(name: "causeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Exception"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_throwable_addSuppressed",
            parameters: [
                RuntimeABIParameter(name: "throwableRaw", type: .intptr),
                RuntimeABIParameter(name: "suppressedRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Exception"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_throwable_getSuppressed",
            parameters: [
                RuntimeABIParameter(name: "throwableRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Exception"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_throwable_suppressedExceptions",
            parameters: [
                RuntimeABIParameter(name: "throwableRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Exception"
        ),
    ]

    public static let testFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_test_assertEquals",
            parameters: [
                RuntimeABIParameter(name: "expected", type: .intptr),
                RuntimeABIParameter(name: "actual", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Test"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_test_assertEquals_message",
            parameters: [
                RuntimeABIParameter(name: "expected", type: .intptr),
                RuntimeABIParameter(name: "actual", type: .intptr),
                RuntimeABIParameter(name: "messageRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Test"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_test_assertTrue",
            parameters: [
                RuntimeABIParameter(name: "condition", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Test"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_test_assertTrue_message",
            parameters: [
                RuntimeABIParameter(name: "condition", type: .intptr),
                RuntimeABIParameter(name: "messageRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Test"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_test_assertNull",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Test"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_test_assertNull_message",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "messageRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Test"
        ),
    ]

    public static let stringFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_string_from_utf8",
            parameters: [
                RuntimeABIParameter(name: "ptr", type: .constUInt8Pointer),
                RuntimeABIParameter(name: "len", type: .int32),
            ],
            returnType: .opaquePointer,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_concat",
            parameters: [
                RuntimeABIParameter(name: "a", type: .nullableOpaquePointer),
                RuntimeABIParameter(name: "b", type: .nullableOpaquePointer),
            ],
            returnType: .opaquePointer,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_compareTo",
            parameters: [
                RuntimeABIParameter(name: "a", type: .nullableOpaquePointer),
                RuntimeABIParameter(name: "b", type: .nullableOpaquePointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_compare_any",
            parameters: [
                RuntimeABIParameter(name: "lhs", type: .intptr),
                RuntimeABIParameter(name: "rhs", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_length",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_trim",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_trim_predicate",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_lowercase",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_uppercase",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_locale_new",
            parameters: [
                RuntimeABIParameter(name: "identifierRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_locale_new_language_country",
            parameters: [
                RuntimeABIParameter(name: "languageRaw", type: .intptr),
                RuntimeABIParameter(name: "countryRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_locale_language",
            parameters: [
                RuntimeABIParameter(name: "localeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_locale_country",
            parameters: [
                RuntimeABIParameter(name: "localeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_locale_variant",
            parameters: [
                RuntimeABIParameter(name: "localeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_locale_displayLanguage",
            parameters: [
                RuntimeABIParameter(name: "localeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_locale_getDefault",
            parameters: [
                RuntimeABIParameter(name: "companionRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_locale_setDefault",
            parameters: [
                RuntimeABIParameter(name: "companionRaw", type: .intptr),
                RuntimeABIParameter(name: "localeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_locale_getAvailableLocales",
            parameters: [
                RuntimeABIParameter(name: "companionRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_locale_hashCode",
            parameters: [
                RuntimeABIParameter(name: "localeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_locale_equals",
            parameters: [
                RuntimeABIParameter(name: "localeRaw", type: .intptr),
                RuntimeABIParameter(name: "otherRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_lowercase_locale",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "localeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_uppercase_locale",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "localeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_compareTo_locale",
            parameters: [
                RuntimeABIParameter(name: "lhsRaw", type: .intptr),
                RuntimeABIParameter(name: "rhsRaw", type: .intptr),
                RuntimeABIParameter(name: "localeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_trimIndent",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_trimMargin_default",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_trimMargin",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "marginPrefixRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_format",
            parameters: [
                RuntimeABIParameter(name: "formatRaw", type: .intptr),
                RuntimeABIParameter(name: "argsArrayRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_format_locale",
            parameters: [
                RuntimeABIParameter(name: "localeRaw", type: .intptr),
                RuntimeABIParameter(name: "formatRaw", type: .intptr),
                RuntimeABIParameter(name: "argsArrayRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_isNullOrEmpty",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_isNullOrBlank",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_startsWith",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "prefixRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_endsWith",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "suffixRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_contains_str",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "otherRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_replace",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "oldRaw", type: .intptr),
                RuntimeABIParameter(name: "newRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_replaceFirst",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "oldRaw", type: .intptr),
                RuntimeABIParameter(name: "newRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_any_to_string",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "tag", type: .intptr),
            ],
            returnType: .opaquePointer,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_any_hashCode",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "tag", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_any_equals",
            parameters: [
                RuntimeABIParameter(name: "lhs", type: .intptr),
                RuntimeABIParameter(name: "lhsTag", type: .intptr),
                RuntimeABIParameter(name: "rhs", type: .intptr),
                RuntimeABIParameter(name: "rhsTag", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_structural_eq",
            parameters: [
                RuntimeABIParameter(name: "lhs", type: .intptr),
                RuntimeABIParameter(name: "rhs", type: .intptr),
            ],
            returnType: .intptr,
            section: "Collections"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_replaceRange",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "replacementRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_removeRange",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "startRaw", type: .intptr),
                RuntimeABIParameter(name: "endRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_removeRange_range",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_substring",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "startRaw", type: .intptr),
                RuntimeABIParameter(name: "endRaw", type: .intptr),
                RuntimeABIParameter(name: "hasEndRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_split",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "delimRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_split_limit",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "delimRaw", type: .intptr),
                RuntimeABIParameter(name: "ignoreCaseRaw", type: .intptr),
                RuntimeABIParameter(name: "limitRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_toInt",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_toInt_radix",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "radix", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_toIntOrNull",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_toIntOrNull_radix",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "radix", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_toDouble",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_toDoubleOrNull",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_toLong",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_toLongOrNull",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_toFloat",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_toFloatOrNull",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_indexOf",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "otherRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_lastIndexOf",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "otherRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        // STDLIB-TEXT-EDGE-003: indexOf / lastIndexOf with ignoreCase
        RuntimeABIFunctionSpec(
            name: "kk_string_indexOf_ignoreCase",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "otherRaw", type: .intptr),
                RuntimeABIParameter(name: "startIndex", type: .intptr),
                RuntimeABIParameter(name: "ignoreCase", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_lastIndexOf_ignoreCase",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "otherRaw", type: .intptr),
                RuntimeABIParameter(name: "startIndex", type: .intptr),
                RuntimeABIParameter(name: "ignoreCase", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_indexOf_from",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "otherRaw", type: .intptr),
                RuntimeABIParameter(name: "startIndex", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_indexOfAny_chars",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "charsRaw", type: .intptr),
                RuntimeABIParameter(name: "startIndex", type: .intptr),
                RuntimeABIParameter(name: "ignoreCase", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_indexOfFirst",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_indexOfLast",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        // STDLIB-140: String.get
        RuntimeABIFunctionSpec(
            name: "kk_string_get",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "indexRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        // STDLIB-141: String.compareTo
        RuntimeABIFunctionSpec(
            name: "kk_string_compareTo_member",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "otherRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_compareToIgnoreCase",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "otherRaw", type: .intptr),
                RuntimeABIParameter(name: "ignoreCaseRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_equals",
            parameters: [
                RuntimeABIParameter(name: "aRaw", type: .intptr),
                RuntimeABIParameter(name: "bRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_enum_valueOf_throw",
            parameters: [
                RuntimeABIParameter(name: "nameRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Exception"
        ),
        // STDLIB-171: enumValues<T>() / T.values() — returns Array<T>
        RuntimeABIFunctionSpec(
            name: "kk_enum_make_values_array",
            parameters: [
                RuntimeABIParameter(name: "valuesRaw", type: .intptr),
                RuntimeABIParameter(name: "count", type: .intptr),
            ],
            returnType: .intptr,
            section: "Enum"
        ),
        // ENUM-002: T.entries — returns EnumEntries<T> (List)
        RuntimeABIFunctionSpec(
            name: "kk_enum_make_entries_list",
            parameters: [
                RuntimeABIParameter(name: "valuesRaw", type: .intptr),
                RuntimeABIParameter(name: "count", type: .intptr),
            ],
            returnType: .intptr,
            section: "Enum"
        ),
        // STDLIB-142: String.toBoolean
        RuntimeABIFunctionSpec(
            name: "kk_string_toBoolean",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_toBooleanStrict",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        // STDLIB-143: String.lines
        RuntimeABIFunctionSpec(
            name: "kk_string_lines",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        // STDLIB-666: String.lineSequence
        RuntimeABIFunctionSpec(
            name: "kk_string_lineSequence",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        // STDLIB-144: String.trimStart/trimEnd
        RuntimeABIFunctionSpec(
            name: "kk_string_trimStart",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_trimStart_predicate",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_trimEnd",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_trimEnd_predicate",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        // STDLIB-145: String.toByteArray
        RuntimeABIFunctionSpec(
            name: "kk_string_toByteArray",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        // STDLIB-581: String.toByteArray(charset: Charset)
        RuntimeABIFunctionSpec(
            name: "kk_string_toByteArray_charset",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "charsetTag", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_charset_utf_8",
            parameters: [],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_charset_iso_8859_1",
            parameters: [],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_charset_us_ascii",
            parameters: [],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_charset_utf_16",
            parameters: [],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_charset_utf_16be",
            parameters: [],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_charset_utf_16le",
            parameters: [],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_charset_utf_32",
            parameters: [],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_charset_utf_32be",
            parameters: [],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_charset_utf_32le",
            parameters: [],
            returnType: .intptr,
            section: "String"
        ),
        // STDLIB-573: String.encodeToByteArray
        RuntimeABIFunctionSpec(
            name: "kk_string_encodeToByteArray",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        // STDLIB-573: String.encodeToByteArray(startIndex, endIndex)
        RuntimeABIFunctionSpec(
            name: "kk_string_encodeToByteArray_range",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "startIndex", type: .intptr),
                RuntimeABIParameter(name: "endIndex", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        // STDLIB-573: String.encodeToByteArray(charset)
        RuntimeABIFunctionSpec(
            name: "kk_string_encodeToByteArray_charset",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "charsetID", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        // STDLIB-574: ByteArray.decodeToString
        RuntimeABIFunctionSpec(
            name: "kk_bytearray_decodeToString",
            parameters: [
                RuntimeABIParameter(name: "arrRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "ByteArray"
        ),
        // STDLIB-574: ByteArray.decodeToString(charset)
        RuntimeABIFunctionSpec(
            name: "kk_bytearray_decodeToString_charset",
            parameters: [
                RuntimeABIParameter(name: "arrRaw", type: .intptr),
                RuntimeABIParameter(name: "charsetId", type: .intptr),
            ],
            returnType: .intptr,
            section: "ByteArray"
        ),
        // STDLIB-TEXT-EDGE-006: ByteArray.decodeToString(startIndex, endIndex, ...)
        RuntimeABIFunctionSpec(
            name: "kk_bytearray_decodeToString_range",
            parameters: [
                RuntimeABIParameter(name: "arrRaw", type: .intptr),
                RuntimeABIParameter(name: "startIndex", type: .intptr),
                RuntimeABIParameter(name: "endIndex", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ByteArray"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_bytearray_decodeToString_range_throw",
            parameters: [
                RuntimeABIParameter(name: "arrRaw", type: .intptr),
                RuntimeABIParameter(name: "startIndex", type: .intptr),
                RuntimeABIParameter(name: "endIndex", type: .intptr),
                RuntimeABIParameter(name: "throwOnInvalidSequence", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "ByteArray"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_char_isDigit",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_char_isLetter",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_char_isLetterOrDigit",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_char_isUpperCase",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_char_isLowerCase",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_char_isWhitespace",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_char_isDefined",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_char_isSupplementaryCodePoint",
            parameters: [
                RuntimeABIParameter(name: "codepoint", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_char_isSurrogatePair",
            parameters: [
                RuntimeABIParameter(name: "high", type: .intptr),
                RuntimeABIParameter(name: "low", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_char_toChars",
            parameters: [
                RuntimeABIParameter(name: "codePoint", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_char_toCodePoint",
            parameters: [
                RuntimeABIParameter(name: "high", type: .intptr),
                RuntimeABIParameter(name: "low", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_char_uppercase",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_char_uppercaseChar",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_char_uppercase_locale",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "localeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_char_lowercase",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_char_lowercaseChar",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_char_lowercase_locale",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "localeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_char_titlecase",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_char_titlecaseChar",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_char_digitToInt",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_char_digitToIntOrNull",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_padStart_default",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "lengthRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_padEnd_default",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "lengthRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_padStart",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "lengthRaw", type: .intptr),
                RuntimeABIParameter(name: "padCharRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_padEnd",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "lengthRaw", type: .intptr),
                RuntimeABIParameter(name: "padCharRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_repeat",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "countRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_reversed",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_toList",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_toCharArray",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        // STDLIB-640: CharArray.concatToString()
        RuntimeABIFunctionSpec(
            name: "kk_chararray_concatToString",
            parameters: [
                RuntimeABIParameter(name: "arrRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        // STDLIB-317: String.asIterable() — lazy Iterable<Char>
        RuntimeABIFunctionSpec(
            name: "kk_string_asIterable",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_iterable_toList",
            parameters: [
                RuntimeABIParameter(name: "iterableRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_iterable_iterator",
            parameters: [
                RuntimeABIParameter(name: "iterableRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_iterator",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_iterator_hasNext",
            parameters: [
                RuntimeABIParameter(name: "iterRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_iterator_next",
            parameters: [
                RuntimeABIParameter(name: "iterRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_filter",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_map",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_count",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_any",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_all",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_none",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_replaceFirstChar",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_take",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "nRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_drop",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "nRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_takeLast",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "nRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_dropLast",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "nRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        // STDLIB-185
        RuntimeABIFunctionSpec(
            name: "kk_string_removePrefix",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "prefixRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_removeSuffix",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "suffixRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_removeSurrounding",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "delimiterRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_removeSurrounding_pair",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "prefixRaw", type: .intptr),
                RuntimeABIParameter(name: "suffixRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        // STDLIB-191
        RuntimeABIFunctionSpec(
            name: "kk_string_prependIndent_default",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_prependIndent",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "indentRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_replaceIndent_default",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_replaceIndent",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "newIndentRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        // STDLIB-192
        RuntimeABIFunctionSpec(
            name: "kk_string_equalsIgnoreCase",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "otherRaw", type: .intptr),
                RuntimeABIParameter(name: "ignoreCaseRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        // STDLIB-190
        RuntimeABIFunctionSpec(
            name: "kk_string_first",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_last",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_single",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_firstOrNull",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_lastOrNull",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        // STDLIB-187
        RuntimeABIFunctionSpec(
            name: "kk_string_isEmpty",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_isNotEmpty",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_isBlank",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_isNotBlank",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_ifBlank",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_ifEmpty",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        // STDLIB-186
        RuntimeABIFunctionSpec(
            name: "kk_string_substringBefore",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "delimiterRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_toBigDecimal",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_bignum_toString",
            parameters: [
                RuntimeABIParameter(name: "numRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        // STDLIB-HOF-023: Advanced String Higher-Order Functions
        RuntimeABIFunctionSpec(
            name: "kk_string_mapIndexed",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_mapNotNull",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_filterIndexed",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_filterNot",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_takeWhile",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_dropWhile",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_splitToSequence",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "delimRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_joinToString",
            parameters: [
                RuntimeABIParameter(name: "strListRaw", type: .intptr),
                RuntimeABIParameter(name: "separatorRaw", type: .intptr),
                RuntimeABIParameter(name: "prefixRaw", type: .intptr),
                RuntimeABIParameter(name: "postfixRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_find",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_findLast",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_substringBeforeLast",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "delimiterRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_substringAfterLast",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "delimiterRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        // STDLIB-534: String?.orEmpty()
        RuntimeABIFunctionSpec(
            name: "kk_string_orEmpty",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
    ]

    public static let consolePrintFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_print_any",
            parameters: [
                RuntimeABIParameter(name: "obj", type: .nullableOpaquePointer),
            ],
            returnType: .void,
            section: "Print"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_println_any",
            parameters: [
                RuntimeABIParameter(name: "obj", type: .nullableOpaquePointer),
            ],
            returnType: .void,
            section: "Print"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_println_bool",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .void,
            section: "Print"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_println_ulong",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .void,
            section: "Print"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_print_noarg",
            parameters: [],
            returnType: .void,
            section: "Print"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_println_newline",
            parameters: [],
            returnType: .void,
            section: "Print"
        ),
    ]

    public static let ioFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_readline",
            parameters: [],
            returnType: .intptr,
            section: "IO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_readln",
            parameters: [
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "IO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_readlnOrNull",
            parameters: [],
            returnType: .intptr,
            section: "IO"
        ),
    ]

    public static let systemFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_system_exitProcess",
            parameters: [
                RuntimeABIParameter(name: "status", type: .intptr),
            ],
            returnType: .noreturn,
            section: "System"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_system_currentTimeMillis",
            parameters: [],
            returnType: .intptr,
            section: "System"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_system_nanoTime",
            parameters: [],
            returnType: .intptr,
            section: "System"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_system_getTimeMicros",
            parameters: [],
            returnType: .intptr,
            section: "System"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_system_getTimeMillis",
            parameters: [],
            returnType: .intptr,
            section: "System"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_system_getTimeNanos",
            parameters: [],
            returnType: .intptr,
            section: "System"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_system_process_start_nanos",
            parameters: [],
            returnType: .intptr,
            section: "System"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_system_measureTimeMillis",
            parameters: [
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "System"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_system_measureTimeMicros",
            parameters: [
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "System"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_system_measureNanoTime",
            parameters: [
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "System"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_platform_canAccessUnaligned",
            parameters: [
                RuntimeABIParameter(name: "platformRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "System"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_platform_isLittleEndian",
            parameters: [
                RuntimeABIParameter(name: "platformRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "System"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_platform_osFamily",
            parameters: [
                RuntimeABIParameter(name: "platformRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "System"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_platform_cpuArchitecture",
            parameters: [
                RuntimeABIParameter(name: "platformRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "System"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_platform_getAvailableProcessors",
            parameters: [
                RuntimeABIParameter(name: "platformRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "System"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_system_gc",
            parameters: [],
            returnType: .void,
            section: "System"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_runtime_getRuntime",
            parameters: [],
            returnType: .intptr,
            section: "System"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_runtime_totalMemory",
            parameters: [],
            returnType: .intptr,
            section: "System"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_runtime_freeMemory",
            parameters: [],
            returnType: .intptr,
            section: "System"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_runtime_maxMemory",
            parameters: [],
            returnType: .intptr,
            section: "System"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_clock_now",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
            ],
            returnType: .intptr,
            section: "System"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_clock_system_now",
            parameters: [],
            returnType: .intptr,
            section: "System"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_instant_to_java_instant",
            parameters: [
                RuntimeABIParameter(name: "instantRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "System"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_java_instant_to_kotlin_instant",
            parameters: [
                RuntimeABIParameter(name: "instantRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "System"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_instant_to_js_date",
            parameters: [
                RuntimeABIParameter(name: "instantRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "System"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_js_date_to_kotlin_instant",
            parameters: [
                RuntimeABIParameter(name: "dateRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "System"
        ),
    ]

    public static let gcFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_register_global_root",
            parameters: [
                RuntimeABIParameter(name: "slot", type: .nullableRawPointerPointer),
            ],
            returnType: .void,
            section: "GC"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_unregister_global_root",
            parameters: [
                RuntimeABIParameter(name: "slot", type: .nullableRawPointerPointer),
            ],
            returnType: .void,
            section: "GC"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_register_frame_map",
            parameters: [
                RuntimeABIParameter(name: "functionID", type: .uint32),
                RuntimeABIParameter(name: "mapPtr", type: .nullableConstRawPointer),
            ],
            returnType: .void,
            section: "GC"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_push_frame",
            parameters: [
                RuntimeABIParameter(name: "functionID", type: .uint32),
                RuntimeABIParameter(name: "frameBase", type: .nullableOpaquePointer),
            ],
            returnType: .void,
            section: "GC"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_pop_frame",
            parameters: [],
            returnType: .void,
            section: "GC"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_register_coroutine_root",
            parameters: [
                RuntimeABIParameter(name: "value", type: .nullableOpaquePointer),
            ],
            returnType: .void,
            section: "GC"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_unregister_coroutine_root",
            parameters: [
                RuntimeABIParameter(name: "value", type: .nullableOpaquePointer),
            ],
            returnType: .void,
            section: "GC"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_runtime_heap_object_count",
            parameters: [],
            returnType: .uint32,
            section: "GC"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_runtime_force_reset",
            parameters: [],
            returnType: .void,
            section: "GC"
        ),
    ]

    public static let coroutineFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_coroutine_suspended",
            parameters: [],
            returnType: .opaquePointer,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_coroutine_continuation_new",
            parameters: [
                RuntimeABIParameter(name: "functionID", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_create_coroutine_unintercepted",
            parameters: [
                RuntimeABIParameter(name: "entryPointRaw", type: .intptr),
                RuntimeABIParameter(name: "completionContinuation", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_start_coroutine_unintercepted_or_return",
            parameters: [
                RuntimeABIParameter(name: "entryPointRaw", type: .intptr),
                RuntimeABIParameter(name: "continuation", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_coroutine_state_enter",
            parameters: [
                RuntimeABIParameter(name: "continuation", type: .intptr),
                RuntimeABIParameter(name: "functionID", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_coroutine_state_set_label",
            parameters: [
                RuntimeABIParameter(name: "continuation", type: .intptr),
                RuntimeABIParameter(name: "label", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_coroutine_state_exit",
            parameters: [
                RuntimeABIParameter(name: "continuation", type: .intptr),
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_coroutine_state_set_spill",
            parameters: [
                RuntimeABIParameter(name: "continuation", type: .intptr),
                RuntimeABIParameter(name: "slot", type: .intptr),
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_coroutine_state_get_spill",
            parameters: [
                RuntimeABIParameter(name: "continuation", type: .intptr),
                RuntimeABIParameter(name: "slot", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_coroutine_state_set_completion",
            parameters: [
                RuntimeABIParameter(name: "continuation", type: .intptr),
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_coroutine_state_get_completion",
            parameters: [
                RuntimeABIParameter(name: "continuation", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_coroutine_state_get_thrown_exception",
            parameters: [
                RuntimeABIParameter(name: "continuation", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kxmini_run_blocking",
            parameters: [
                RuntimeABIParameter(name: "entryPointRaw", type: .intptr),
                RuntimeABIParameter(name: "functionID", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kxmini_launch",
            parameters: [
                RuntimeABIParameter(name: "entryPointRaw", type: .intptr),
                RuntimeABIParameter(name: "functionID", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kxmini_async",
            parameters: [
                RuntimeABIParameter(name: "entryPointRaw", type: .intptr),
                RuntimeABIParameter(name: "functionID", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kxmini_async_await",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kxmini_delay",
            parameters: [
                RuntimeABIParameter(name: "milliseconds", type: .intptr),
                RuntimeABIParameter(name: "continuation", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_coroutine_yield",
            parameters: [
                RuntimeABIParameter(name: "continuation", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_coroutine_launcher_arg_set",
            parameters: [
                RuntimeABIParameter(name: "continuation", type: .intptr),
                RuntimeABIParameter(name: "index", type: .int64),
                RuntimeABIParameter(name: "value", type: .int64),
            ],
            returnType: .int64,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_coroutine_launcher_arg_get",
            parameters: [
                RuntimeABIParameter(name: "continuation", type: .intptr),
                RuntimeABIParameter(name: "index", type: .int64),
            ],
            returnType: .int64,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kxmini_run_blocking_with_cont",
            parameters: [
                RuntimeABIParameter(name: "entryPointRaw", type: .intptr),
                RuntimeABIParameter(name: "continuation", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kxmini_launch_with_cont",
            parameters: [
                RuntimeABIParameter(name: "entryPointRaw", type: .intptr),
                RuntimeABIParameter(name: "continuation", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kxmini_async_with_cont",
            parameters: [
                RuntimeABIParameter(name: "entryPointRaw", type: .intptr),
                RuntimeABIParameter(name: "continuation", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_produce",
            parameters: [
                RuntimeABIParameter(name: "entryPointRaw", type: .intptr),
                RuntimeABIParameter(name: "capture0", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kxmini_produce_with_cont",
            parameters: [
                RuntimeABIParameter(name: "entryPointRaw", type: .intptr),
                RuntimeABIParameter(name: "continuation", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        // CORO-071: async exception handling, cancellation, dispatcher support
        RuntimeABIFunctionSpec(
            name: "kk_kxmini_async_await_throwing",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        // Dispatcher-aware launch (STDLIB-CORO-072)
        RuntimeABIFunctionSpec(
            name: "kk_kxmini_launch_with_dispatcher",
            parameters: [
                RuntimeABIParameter(name: "entryPointRaw", type: .intptr),
                RuntimeABIParameter(name: "functionID", type: .intptr),
                RuntimeABIParameter(name: "dispatcherRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_async_task_cancel",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kxmini_async_with_dispatcher",
            parameters: [
                RuntimeABIParameter(name: "dispatcherTag", type: .intptr),
                RuntimeABIParameter(name: "entryPointRaw", type: .intptr),
                RuntimeABIParameter(name: "continuation", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kxmini_launch_with_dispatcher_and_cont",
            parameters: [
                RuntimeABIParameter(name: "entryPointRaw", type: .intptr),
                RuntimeABIParameter(name: "continuation", type: .intptr),
                RuntimeABIParameter(name: "dispatcherRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        // CoroutineExceptionHandler (STDLIB-CORO-072)
        RuntimeABIFunctionSpec(
            name: "kk_exception_handler_new",
            parameters: [],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kxmini_launch_with_exception_handler",
            parameters: [
                RuntimeABIParameter(name: "entryPointRaw", type: .intptr),
                RuntimeABIParameter(name: "functionID", type: .intptr),
                RuntimeABIParameter(name: "handlerRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        // Flow (P5-88)
        RuntimeABIFunctionSpec(
            name: "kk_flow_create",
            parameters: [
                RuntimeABIParameter(name: "emitterFnPtr", type: .intptr),
                RuntimeABIParameter(name: "continuation", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_flow_emit",
            parameters: [
                RuntimeABIParameter(name: "flowHandle", type: .intptr),
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "tag", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_flow_collect",
            parameters: [
                RuntimeABIParameter(name: "flowHandle", type: .intptr),
                RuntimeABIParameter(name: "collectorFnPtr", type: .intptr),
                RuntimeABIParameter(name: "continuation", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_flow_retain",
            parameters: [
                RuntimeABIParameter(name: "flowHandle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_flow_release",
            parameters: [
                RuntimeABIParameter(name: "flowHandle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        // Flow terminal operators & builders (STDLIB-088 / STDLIB-FLOW-178)
        RuntimeABIFunctionSpec(
            name: "kk_flow_of",
            parameters: [
                RuntimeABIParameter(name: "arrayHandle", type: .intptr),
                RuntimeABIParameter(name: "count", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_flow_empty",
            parameters: [
                RuntimeABIParameter(name: "reserved", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_flow_as_flow",
            parameters: [
                RuntimeABIParameter(name: "sourceHandle", type: .intptr),
                RuntimeABIParameter(name: "reserved", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_flow_to_list",
            parameters: [
                RuntimeABIParameter(name: "flowHandle", type: .intptr),
                RuntimeABIParameter(name: "continuation", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_flow_first",
            parameters: [
                RuntimeABIParameter(name: "flowHandle", type: .intptr),
                RuntimeABIParameter(name: "continuation", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_flow_single",
            parameters: [
                RuntimeABIParameter(name: "flowHandle", type: .intptr),
                RuntimeABIParameter(name: "continuation", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_flow_zip",
            parameters: [
                RuntimeABIParameter(name: "lhsHandle", type: .intptr),
                RuntimeABIParameter(name: "rhsHandle", type: .intptr),
                RuntimeABIParameter(name: "transformFnPtr", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_flow_combine",
            parameters: [
                RuntimeABIParameter(name: "lhsHandle", type: .intptr),
                RuntimeABIParameter(name: "rhsHandle", type: .intptr),
                RuntimeABIParameter(name: "transformFnPtr", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_flow_merge",
            parameters: [
                RuntimeABIParameter(name: "lhsHandle", type: .intptr),
                RuntimeABIParameter(name: "rhsHandle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_flow_flat_map_concat",
            parameters: [
                RuntimeABIParameter(name: "flowHandle", type: .intptr),
                RuntimeABIParameter(name: "transformFnPtr", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_flow_flat_map_merge",
            parameters: [
                RuntimeABIParameter(name: "flowHandle", type: .intptr),
                RuntimeABIParameter(name: "transformFnPtr", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_flow_flat_map_latest",
            parameters: [
                RuntimeABIParameter(name: "flowHandle", type: .intptr),
                RuntimeABIParameter(name: "transformFnPtr", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_flow_count",
            parameters: [
                RuntimeABIParameter(name: "flowHandle", type: .intptr),
                RuntimeABIParameter(name: "continuation", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_flow_fold",
            parameters: [
                RuntimeABIParameter(name: "flowHandle", type: .intptr),
                RuntimeABIParameter(name: "initial", type: .intptr),
                RuntimeABIParameter(name: "operationFnPtr", type: .intptr),
                RuntimeABIParameter(name: "continuation", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_flow_reduce",
            parameters: [
                RuntimeABIParameter(name: "flowHandle", type: .intptr),
                RuntimeABIParameter(name: "operationFnPtr", type: .intptr),
                RuntimeABIParameter(name: "continuation", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        // Dispatchers / withContext (P5-133)
        RuntimeABIFunctionSpec(
            name: "kk_dispatcher_default",
            parameters: [],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_dispatcher_io",
            parameters: [],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_dispatcher_main",
            parameters: [],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_with_context",
            parameters: [
                RuntimeABIParameter(name: "dispatcher", type: .intptr),
                RuntimeABIParameter(name: "blockFnPtr", type: .intptr),
                RuntimeABIParameter(name: "continuation", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        // STDLIB-CORO-077: CoroutineName, CoroutineExceptionHandler, CoroutineContext
        RuntimeABIFunctionSpec(
            name: "kk_coroutine_name_create",
            parameters: [
                RuntimeABIParameter(name: "nameRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_coroutine_name_get",
            parameters: [
                RuntimeABIParameter(name: "handleRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_exception_handler_create",
            parameters: [
                RuntimeABIParameter(name: "handlerFnPtr", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_exception_handler_invoke",
            parameters: [
                RuntimeABIParameter(name: "handlerRaw", type: .intptr),
                RuntimeABIParameter(name: "contextRaw", type: .intptr),
                RuntimeABIParameter(name: "exceptionRaw", type: .intptr),
            ],
            returnType: .void,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_context_plus",
            parameters: [
                RuntimeABIParameter(name: "leftRaw", type: .intptr),
                RuntimeABIParameter(name: "rightRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_context_get",
            parameters: [
                RuntimeABIParameter(name: "contextRaw", type: .intptr),
                RuntimeABIParameter(name: "keyRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_context_fold",
            parameters: [
                RuntimeABIParameter(name: "contextRaw", type: .intptr),
                RuntimeABIParameter(name: "initial", type: .intptr),
                RuntimeABIParameter(name: "operationFnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_context_minusKey",
            parameters: [
                RuntimeABIParameter(name: "contextRaw", type: .intptr),
                RuntimeABIParameter(name: "keyRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_context_get_dispatcher",
            parameters: [
                RuntimeABIParameter(name: "contextRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_continuation_intercepted",
            parameters: [
                RuntimeABIParameter(name: "continuationRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_continuation_interceptor_intercept_continuation",
            parameters: [
                RuntimeABIParameter(name: "interceptorRaw", type: .intptr),
                RuntimeABIParameter(name: "continuationRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_context_get_name",
            parameters: [
                RuntimeABIParameter(name: "contextRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_context_get_exception_handler",
            parameters: [
                RuntimeABIParameter(name: "contextRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_context_release",
            parameters: [
                RuntimeABIParameter(name: "contextRaw", type: .intptr),
            ],
            returnType: .void,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_with_context_full",
            parameters: [
                RuntimeABIParameter(name: "contextRaw", type: .intptr),
                RuntimeABIParameter(name: "blockFnPtr", type: .intptr),
                RuntimeABIParameter(name: "continuation", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        // Channel (CORO-001)
        RuntimeABIFunctionSpec(
            name: "kk_channel_create",
            parameters: [
                RuntimeABIParameter(name: "capacity", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_channel_send",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "continuation", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_channel_receive",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
                RuntimeABIParameter(name: "continuation", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_channel_close",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_channel_is_closed_token",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        // Deferred / awaitAll (P5-135)
        RuntimeABIFunctionSpec(
            name: "kk_await_all",
            parameters: [
                RuntimeABIParameter(name: "handlesArray", type: .intptr),
                RuntimeABIParameter(name: "count", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        // Structured Concurrency (P5-89)
        RuntimeABIFunctionSpec(
            name: "kk_coroutine_scope_new",
            parameters: [],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_coroutine_scope_cancel",
            parameters: [
                RuntimeABIParameter(name: "scopeHandle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_coroutine_scope_wait",
            parameters: [
                RuntimeABIParameter(name: "scopeHandle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_coroutine_scope_register_child",
            parameters: [
                RuntimeABIParameter(name: "scopeHandle", type: .intptr),
                RuntimeABIParameter(name: "childHandle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_job_join",
            parameters: [
                RuntimeABIParameter(name: "jobHandle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_job_await_completion",
            parameters: [
                RuntimeABIParameter(name: "jobHandle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_coroutine_scope_run",
            parameters: [
                RuntimeABIParameter(name: "entryPointRaw", type: .intptr),
                RuntimeABIParameter(name: "functionID", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_coroutine_scope_run_with_cont",
            parameters: [
                RuntimeABIParameter(name: "entryPointRaw", type: .intptr),
                RuntimeABIParameter(name: "continuation", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_supervisor_scope_run",
            parameters: [
                RuntimeABIParameter(name: "entryPointRaw", type: .intptr),
                RuntimeABIParameter(name: "functionID", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_supervisor_scope_run_with_cont",
            parameters: [
                RuntimeABIParameter(name: "entryPointRaw", type: .intptr),
                RuntimeABIParameter(name: "continuation", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        // CoroutineScope hierarchy / lifecycle (STDLIB-CORO-069)
        RuntimeABIFunctionSpec(
            name: "kk_coroutine_scope_is_active",
            parameters: [
                RuntimeABIParameter(name: "scopeHandle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_coroutine_scope_is_cancelled",
            parameters: [
                RuntimeABIParameter(name: "scopeHandle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_coroutine_scope_get_parent",
            parameters: [
                RuntimeABIParameter(name: "scopeHandle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_coroutine_scope_cancel_propagate",
            parameters: [
                RuntimeABIParameter(name: "parentHandle", type: .intptr),
                RuntimeABIParameter(name: "childHandle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        // Cancellation (CORO-002)
        RuntimeABIFunctionSpec(
            name: "kk_coroutine_check_cancellation",
            parameters: [
                RuntimeABIParameter(name: "continuation", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_is_cancellation_exception",
            parameters: [
                RuntimeABIParameter(name: "throwableRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_job_cancel",
            parameters: [
                RuntimeABIParameter(name: "jobHandle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_job_cancel_with_cause",
            parameters: [
                RuntimeABIParameter(name: "jobHandle", type: .intptr),
                RuntimeABIParameter(name: "cause", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_context_cancel",
            parameters: [
                RuntimeABIParameter(name: "contextRaw", type: .intptr),
                RuntimeABIParameter(name: "causeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_context_cancel_no_cause",
            parameters: [
                RuntimeABIParameter(name: "contextRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_job_complete",
            parameters: [
                RuntimeABIParameter(name: "jobHandle", type: .intptr),
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_job_complete_exceptionally",
            parameters: [
                RuntimeABIParameter(name: "jobHandle", type: .intptr),
                RuntimeABIParameter(name: "exception", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        // Job State Queries (STDLIB-CORO-070)
        RuntimeABIFunctionSpec(
            name: "kk_job_is_active",
            parameters: [
                RuntimeABIParameter(name: "jobHandle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_job_is_completed",
            parameters: [
                RuntimeABIParameter(name: "jobHandle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_job_is_cancelled",
            parameters: [
                RuntimeABIParameter(name: "jobHandle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_job_is_failed",
            parameters: [
                RuntimeABIParameter(name: "jobHandle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_coroutine_cancel",
            parameters: [
                RuntimeABIParameter(name: "continuation", type: .intptr),
            ],
            returnType: .void,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_coroutine_cancel_current",
            parameters: [
                RuntimeABIParameter(name: "message", type: .intptr),
                RuntimeABIParameter(name: "causeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        // Mutex / Semaphore (sync primitives)
        RuntimeABIFunctionSpec(
            name: "kk_mutex_create",
            parameters: [],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_reentrant_read_write_lock_new",
            parameters: [],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_mutex_lock",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
                RuntimeABIParameter(name: "continuation", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_mutex_unlock",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_mutex_tryLock",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_mutex_isLocked",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_mutex_withLock",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
                RuntimeABIParameter(name: "actionFnPtr", type: .intptr),
                RuntimeABIParameter(name: "actionEnvPtr", type: .intptr),
                RuntimeABIParameter(name: "continuation", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_lock_withLock",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
                RuntimeABIParameter(name: "actionFnPtr", type: .intptr),
                RuntimeABIParameter(name: "actionEnvPtr", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_read_write_lock_create",
            parameters: [],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_read_write_lock_read",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
                RuntimeABIParameter(name: "actionFnPtr", type: .intptr),
                RuntimeABIParameter(name: "actionEnvPtr", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_read_write_lock_write",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
                RuntimeABIParameter(name: "actionFnPtr", type: .intptr),
                RuntimeABIParameter(name: "actionEnvPtr", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_semaphore_create",
            parameters: [
                RuntimeABIParameter(name: "permits", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_semaphore_acquire",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
                RuntimeABIParameter(name: "continuation", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_semaphore_release",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_semaphore_tryAcquire",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_semaphore_availablePermits",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
    ]

    public static let boxingFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_box_int",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Boxing"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_box_bool",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Boxing"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_lateinit_is_initialized",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Boxing"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_lateinit_get_or_throw",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "propertyName", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Boxing"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_unbox_int",
            parameters: [
                RuntimeABIParameter(name: "obj", type: .intptr),
            ],
            returnType: .intptr,
            section: "Boxing"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_unbox_bool",
            parameters: [
                RuntimeABIParameter(name: "obj", type: .intptr),
            ],
            returnType: .intptr,
            section: "Boxing"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_box_long",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Boxing"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_box_float",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Boxing"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_box_double",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Boxing"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_box_char",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Boxing"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_unbox_long",
            parameters: [
                RuntimeABIParameter(name: "obj", type: .intptr),
            ],
            returnType: .intptr,
            section: "Boxing"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_unbox_float",
            parameters: [
                RuntimeABIParameter(name: "obj", type: .intptr),
            ],
            returnType: .intptr,
            section: "Boxing"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_unbox_double",
            parameters: [
                RuntimeABIParameter(name: "obj", type: .intptr),
            ],
            returnType: .intptr,
            section: "Boxing"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_unbox_char",
            parameters: [
                RuntimeABIParameter(name: "obj", type: .intptr),
            ],
            returnType: .intptr,
            section: "Boxing"
        ),
    ]

    public static let arrayFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_array_new",
            parameters: [
                RuntimeABIParameter(name: "length", type: .intptr),
            ],
            returnType: .intptr,
            section: "Array"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_array_of_nulls",
            parameters: [
                RuntimeABIParameter(name: "length", type: .intptr),
            ],
            returnType: .intptr,
            section: "Array"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_object_new",
            parameters: [
                RuntimeABIParameter(name: "length", type: .intptr),
                RuntimeABIParameter(name: "classId", type: .intptr),
            ],
            returnType: .intptr,
            section: "Array"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_object_type_id",
            parameters: [
                RuntimeABIParameter(name: "objectRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Array"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_array_get",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
                RuntimeABIParameter(name: "index", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Array"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_array_get_inbounds",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
                RuntimeABIParameter(name: "index", type: .intptr),
            ],
            returnType: .intptr,
            section: "Array"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_array_set",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
                RuntimeABIParameter(name: "index", type: .intptr),
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Array"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_array_binarySearch_compare",
            parameters: [
                RuntimeABIParameter(name: "arrayRaw", type: .intptr),
                RuntimeABIParameter(name: "element", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "fromIndex", type: .intptr),
                RuntimeABIParameter(name: "toIndex", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Array"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_vararg_spread_concat",
            parameters: [
                RuntimeABIParameter(name: "pairsArrayRaw", type: .intptr),
                RuntimeABIParameter(name: "pairCount", type: .intptr),
            ],
            returnType: .intptr,
            section: "Array"
        ),
    ]

    public static let operatorFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_type_register_super",
            parameters: [
                RuntimeABIParameter(name: "childTypeId", type: .intptr),
                RuntimeABIParameter(name: "superTypeId", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_type_register_iface",
            parameters: [
                RuntimeABIParameter(name: "childTypeId", type: .intptr),
                RuntimeABIParameter(name: "ifaceTypeId", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck"
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
            section: "TypeCheck"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_type_token_simple_name",
            parameters: [
                RuntimeABIParameter(name: "typeToken", type: .intptr),
                RuntimeABIParameter(name: "nameHint", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_type_token_qualified_name",
            parameters: [
                RuntimeABIParameter(name: "typeToken", type: .intptr),
                RuntimeABIParameter(name: "nameHint", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kclass_create",
            parameters: [
                RuntimeABIParameter(name: "typeToken", type: .intptr),
                RuntimeABIParameter(name: "nameHint", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kclass_simple_name",
            parameters: [
                RuntimeABIParameter(name: "kclassRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kclass_qualified_name",
            parameters: [
                RuntimeABIParameter(name: "kclassRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck"
        ),
        // REFL-004: KClass binary metadata registration and accessors
        RuntimeABIFunctionSpec(
            name: "kk_kclass_register_metadata",
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
            name: "kk_kclass_is_data",
            parameters: [
                RuntimeABIParameter(name: "kclassRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kclass_is_sealed",
            parameters: [
                RuntimeABIParameter(name: "kclassRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kclass_is_value",
            parameters: [
                RuntimeABIParameter(name: "kclassRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kclass_is_interface",
            parameters: [
                RuntimeABIParameter(name: "kclassRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kclass_is_object",
            parameters: [
                RuntimeABIParameter(name: "kclassRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kclass_is_enum",
            parameters: [
                RuntimeABIParameter(name: "kclassRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kclass_is_abstract",
            parameters: [
                RuntimeABIParameter(name: "kclassRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kclass_supertype_name",
            parameters: [
                RuntimeABIParameter(name: "kclassRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kclass_members_count",
            parameters: [
                RuntimeABIParameter(name: "kclassRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck"
        ),
        // STDLIB-REFLECT-065: Annotation reflection
        RuntimeABIFunctionSpec(
            name: "kk_annotation_create",
            parameters: [
                RuntimeABIParameter(name: "fqNameRaw", type: .intptr),
                RuntimeABIParameter(name: "argsListRaw", type: .intptr),
                RuntimeABIParameter(name: "annotationClassRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Reflection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_annotation_get_class",
            parameters: [
                RuntimeABIParameter(name: "annotationRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Reflection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_annotation_get_fqname",
            parameters: [
                RuntimeABIParameter(name: "annotationRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Reflection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_annotation_get_value",
            parameters: [
                RuntimeABIParameter(name: "annotationRaw", type: .intptr),
                RuntimeABIParameter(name: "index", type: .intptr),
            ],
            returnType: .intptr,
            section: "Reflection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_annotation_get_arg_count",
            parameters: [
                RuntimeABIParameter(name: "annotationRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Reflection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_annotation_to_string",
            parameters: [
                RuntimeABIParameter(name: "annotationRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Reflection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kclass_get_annotations",
            parameters: [
                RuntimeABIParameter(name: "kclassRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Reflection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kclass_find_annotation",
            parameters: [
                RuntimeABIParameter(name: "kclassRaw", type: .intptr),
                RuntimeABIParameter(name: "nameRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Reflection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kclass_find_associated_object",
            parameters: [
                RuntimeABIParameter(name: "kclassRaw", type: .intptr),
                RuntimeABIParameter(name: "keyNameRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Reflection"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kclass_register_single_annotation",
            parameters: [
                RuntimeABIParameter(name: "typeToken", type: .intptr),
                RuntimeABIParameter(name: "fqNameRaw", type: .intptr),
                RuntimeABIParameter(name: "argsEncodedRaw", type: .intptr),
                RuntimeABIParameter(name: "argCount", type: .intptr),
            ],
            returnType: .intptr,
            section: "Reflection"
        ),
        // REFL-005: KClass.isInstance, members, constructors
        RuntimeABIFunctionSpec(
            name: "kk_kclass_isInstance",
            parameters: [
                RuntimeABIParameter(name: "kclassRaw", type: .intptr),
                RuntimeABIParameter(name: "valueRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kclass_cast",
            parameters: [
                RuntimeABIParameter(name: "kclassRaw", type: .intptr),
                RuntimeABIParameter(name: "valueRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "TypeCheck"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kclass_safeCast",
            parameters: [
                RuntimeABIParameter(name: "kclassRaw", type: .intptr),
                RuntimeABIParameter(name: "valueRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kclass_members",
            parameters: [
                RuntimeABIParameter(name: "kclassRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kclass_constructors",
            parameters: [
                RuntimeABIParameter(name: "kclassRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck"
        ),
        // STDLIB-REFLECT-064: KClass.primaryConstructor
        RuntimeABIFunctionSpec(
            name: "kk_kclass_primary_constructor",
            parameters: [
                RuntimeABIParameter(name: "kclassRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck"
        ),

        // STDLIB-REFLECT-061: KClass member access
        RuntimeABIFunctionSpec(
            name: "kk_kclass_properties",
            parameters: [
                RuntimeABIParameter(name: "kclassRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kclass_member_properties",
            parameters: [
                RuntimeABIParameter(name: "kclassRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kclass_declared_member_properties",
            parameters: [
                RuntimeABIParameter(name: "kclassRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kclass_functions",
            parameters: [
                RuntimeABIParameter(name: "kclassRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kclass_member_functions",
            parameters: [
                RuntimeABIParameter(name: "kclassRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_kclass_declared_member_functions",
            parameters: [
                RuntimeABIParameter(name: "kclassRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck"
        ),
        // REFL-005: KType and typeOf<T>()
        RuntimeABIFunctionSpec(
            name: "kk_ktype_create",
            parameters: [
                RuntimeABIParameter(name: "classifierRaw", type: .intptr),
                RuntimeABIParameter(name: "argsRaw", type: .intptr),
                RuntimeABIParameter(name: "isNullable", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ktype_classifier",
            parameters: [
                RuntimeABIParameter(name: "ktypeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ktype_arguments",
            parameters: [
                RuntimeABIParameter(name: "ktypeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ktype_isMarkedNullable",
            parameters: [
                RuntimeABIParameter(name: "ktypeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck"
        ),
        // STDLIB-REFLECT-066: KType.toString()
        RuntimeABIFunctionSpec(
            name: "kk_ktype_to_string",
            parameters: [
                RuntimeABIParameter(name: "ktypeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ktypeprojection_create",
            parameters: [
                RuntimeABIParameter(name: "typeRaw", type: .intptr),
                RuntimeABIParameter(name: "varianceOrdinal", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ktypeprojection_type",
            parameters: [
                RuntimeABIParameter(name: "projRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ktypeprojection_variance",
            parameters: [
                RuntimeABIParameter(name: "projRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck"
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
            section: "TypeCheck"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_op_is",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "typeToken", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck"
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
            section: "TypeCheck"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_op_contains",
            parameters: [
                RuntimeABIParameter(name: "container", type: .intptr),
                RuntimeABIParameter(name: "element", type: .intptr),
            ],
            returnType: .intptr,
            section: "TypeCheck"
        ),
    ]

    /// Range/Progression (P5-68)
    public static let rangeFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_op_rangeTo",
            parameters: [
                RuntimeABIParameter(name: "a", type: .intptr),
                RuntimeABIParameter(name: "b", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_op_rangeUntil",
            parameters: [
                RuntimeABIParameter(name: "a", type: .intptr),
                RuntimeABIParameter(name: "b", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_op_ulong_rangeUntil",
            parameters: [
                RuntimeABIParameter(name: "a", type: .intptr),
                RuntimeABIParameter(name: "b", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_op_downTo",
            parameters: [
                RuntimeABIParameter(name: "a", type: .intptr),
                RuntimeABIParameter(name: "b", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_op_step",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "stepVal", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_range_first",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_range_start",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_range_last",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_range_endExclusive",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_range_count",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_range_isEmpty",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_range_sum",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_range_toList",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_range_toList",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        // ULongRange count, iterator, forEach, map (STDLIB-RANGE-037)
        RuntimeABIFunctionSpec(
            name: "kk_ulong_range_count",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_range_iterator",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_range_hasNext",
            parameters: [
                RuntimeABIParameter(name: "iterRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_range_next",
            parameters: [
                RuntimeABIParameter(name: "iterRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_range_forEach",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_range_map",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_range_forEach",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_range_map",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_range_step",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        // Range HOFs (STDLIB-RANGE-038)
        RuntimeABIFunctionSpec(
            name: "kk_range_mapIndexed",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_range_mapNotNull",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_range_filter",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_range_filterIndexed",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_range_filterNot",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_range_reduce",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_range_reduceIndexed",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_range_fold",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "initialValue", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_range_foldIndexed",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "initialValue", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_range_find",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_range_findLast",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_range_first_predicate",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_range_firstOrNull_predicate",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_range_last_predicate",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_range_lastOrNull_predicate",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_range_any",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_range_all",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_range_none",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_range_chunked",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "size", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_range_windowed",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "size", type: .intptr),
                RuntimeABIParameter(name: "step", type: .intptr),
                RuntimeABIParameter(name: "partialWindows", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_range_reversed",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_range_toIntArray",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        // Progression fromClosedRange (STDLIB-RANGE-039)
        RuntimeABIFunctionSpec(
            name: "kk_int_progression_fromClosedRange",
            parameters: [
                RuntimeABIParameter(name: "receiverRaw", type: .intptr),
                RuntimeABIParameter(name: "rangeStart", type: .intptr),
                RuntimeABIParameter(name: "rangeEnd", type: .intptr),
                RuntimeABIParameter(name: "step", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_long_progression_fromClosedRange",
            parameters: [
                RuntimeABIParameter(name: "receiverRaw", type: .intptr),
                RuntimeABIParameter(name: "rangeStart", type: .intptr),
                RuntimeABIParameter(name: "rangeEnd", type: .intptr),
                RuntimeABIParameter(name: "step", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_progression_fromClosedRange",
            parameters: [
                RuntimeABIParameter(name: "receiverRaw", type: .intptr),
                RuntimeABIParameter(name: "rangeStart", type: .intptr),
                RuntimeABIParameter(name: "rangeEnd", type: .intptr),
                RuntimeABIParameter(name: "step", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_progression_fromClosedRange",
            parameters: [
                RuntimeABIParameter(name: "receiverRaw", type: .intptr),
                RuntimeABIParameter(name: "rangeStart", type: .intptr),
                RuntimeABIParameter(name: "rangeEnd", type: .intptr),
                RuntimeABIParameter(name: "step", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_char_progression_fromClosedRange",
            parameters: [
                RuntimeABIParameter(name: "receiverRaw", type: .intptr),
                RuntimeABIParameter(name: "rangeStart", type: .intptr),
                RuntimeABIParameter(name: "rangeEnd", type: .intptr),
                RuntimeABIParameter(name: "step", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        // LongRange (STDLIB-RANGE-035)
        RuntimeABIFunctionSpec(
            name: "kk_long_rangeTo",
            parameters: [
                RuntimeABIParameter(name: "lhs", type: .intptr),
                RuntimeABIParameter(name: "rhs", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_long_range_first",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_long_range_last",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_long_range_step",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_long_range_contains",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_long_range_isEmpty",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_long_range_iterator",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_long_range_reversed",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_long_range_toList",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_long_range_toLongArray",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_long_range_count",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_long_range_randomOrNull",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_long_range_randomOrNull_random",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "randomRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_long_range_forEach",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_long_range_map",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_long_range_random",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_long_range_random_random",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "randomRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        // UIntProgression operations (STDLIB-RANGE-039)
        RuntimeABIFunctionSpec(
            name: "kk_uint_rangeTo",
            parameters: [
                RuntimeABIParameter(name: "lhs", type: .intptr),
                RuntimeABIParameter(name: "rhs", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_downTo",
            parameters: [
                RuntimeABIParameter(name: "lhs", type: .intptr),
                RuntimeABIParameter(name: "rhs", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_step",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "stepValue", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_range_reversed",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_range_toList",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_range_iterator",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_range_hasNext",
            parameters: [
                RuntimeABIParameter(name: "iterRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_range_next",
            parameters: [
                RuntimeABIParameter(name: "iterRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        // ULongProgression operations (STDLIB-RANGE-039)
        RuntimeABIFunctionSpec(
            name: "kk_ulong_rangeTo",
            parameters: [
                RuntimeABIParameter(name: "lhs", type: .intptr),
                RuntimeABIParameter(name: "rhs", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_downTo",
            parameters: [
                RuntimeABIParameter(name: "lhs", type: .intptr),
                RuntimeABIParameter(name: "rhs", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_step",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "stepValue", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_range_reversed",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        // CharRange (STDLIB-290)
        RuntimeABIFunctionSpec(
            name: "kk_char_range_isEmpty",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_char_range_step",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "stepVal", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_char_range_toList",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_char_range_forEach",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_char_range_take",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "n", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_char_range_drop",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "n", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_char_range_sorted",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_char_range_randomOrNull",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_char_range_randomOrNull_random",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "randomRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_char_range_random_random",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "randomRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_range_firstOrNull",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_range_lastOrNull",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_range_randomOrNull",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_range_randomOrNull_random",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "randomRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_range_random",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_range_random_random",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "randomRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_range_contains",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_range_first",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_range_last",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_range_step",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_range_isEmpty",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_range_count",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_range_sum",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_range_toUIntArray",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_range_forEach",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_range_map",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_range_mapIndexed",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_range_mapNotNull",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_range_filter",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_range_filterIndexed",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_range_filterNot",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_range_reduce",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_range_reduceIndexed",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_range_fold",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "initialValue", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_range_foldIndexed",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "initialValue", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_range_find",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_range_findLast",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_range_first_predicate",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_range_firstOrNull_predicate",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_range_firstOrNull",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_range_last_predicate",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_range_lastOrNull_predicate",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_range_lastOrNull",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_range_randomOrNull",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_range_randomOrNull_random",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "randomRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_range_random",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_range_random_random",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "randomRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_range_any",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_range_all",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_range_none",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_range_chunked",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "size", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uint_range_windowed",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "size", type: .intptr),
                RuntimeABIParameter(name: "step", type: .intptr),
                RuntimeABIParameter(name: "partialWindows", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_range_contains",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_range_first",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_range_last",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_range_step",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_range_isEmpty",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_range_toULongArray",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_range_mapIndexed",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_range_mapNotNull",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_range_filter",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_range_filterIndexed",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_range_filterNot",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_range_reduce",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_range_reduceIndexed",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_range_fold",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "initialValue", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_range_foldIndexed",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "initialValue", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_range_find",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_range_findLast",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_range_first_predicate",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_range_firstOrNull_predicate",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_range_firstOrNull",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_range_last_predicate",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_range_lastOrNull_predicate",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_range_lastOrNull",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_range_randomOrNull",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_range_randomOrNull_random",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "randomRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_range_random",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_range_random_random",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "randomRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_range_any",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_range_all",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_range_none",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "lambdaRaw", type: .intptr),
                RuntimeABIParameter(name: "captureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_range_chunked",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "size", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_ulong_range_windowed",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
                RuntimeABIParameter(name: "size", type: .intptr),
                RuntimeABIParameter(name: "step", type: .intptr),
                RuntimeABIParameter(name: "partialWindows", type: .intptr),
            ],
            returnType: .intptr,
            section: "Range"
        ),
    ]

    /// Stdlib Delegate Functions (P5-80)
    public static let delegateFunctions: [RuntimeABIFunctionSpec] = [
        // Lazy
        RuntimeABIFunctionSpec(
            name: "kk_lazy_create",
            parameters: [
                RuntimeABIParameter(name: "initFnPtr", type: .intptr),
                RuntimeABIParameter(name: "mode", type: .intptr),
            ],
            returnType: .intptr,
            section: "Delegate"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_lazy_of",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Delegate"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_lazy_get_value",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Delegate"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_lazy_is_initialized",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Delegate"
        ),
        // Observable
        RuntimeABIFunctionSpec(
            name: "kk_observable_create",
            parameters: [
                RuntimeABIParameter(name: "initialValue", type: .intptr),
                RuntimeABIParameter(name: "callbackFnPtr", type: .intptr),
            ],
            returnType: .intptr,
            section: "Delegate"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_observable_get_value",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Delegate"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_observable_set_value",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
                RuntimeABIParameter(name: "newValue", type: .intptr),
            ],
            returnType: .intptr,
            section: "Delegate"
        ),
        // Vetoable
        RuntimeABIFunctionSpec(
            name: "kk_vetoable_create",
            parameters: [
                RuntimeABIParameter(name: "initialValue", type: .intptr),
                RuntimeABIParameter(name: "callbackFnPtr", type: .intptr),
            ],
            returnType: .intptr,
            section: "Delegate"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_vetoable_get_value",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
            ],
            returnType: .intptr,
            section: "Delegate"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_vetoable_set_value",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
                RuntimeABIParameter(name: "newValue", type: .intptr),
            ],
            returnType: .intptr,
            section: "Delegate"
        ),
        // NotNull
        RuntimeABIFunctionSpec(
            name: "kk_notNull_create",
            parameters: [],
            returnType: .intptr,
            section: "Delegate"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_notNull_get_value",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Delegate"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_notNull_set_value",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
                RuntimeABIParameter(name: "newValue", type: .intptr),
            ],
            returnType: .intptr,
            section: "Delegate"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_custom_delegate_create",
            parameters: [
                RuntimeABIParameter(name: "delegateHandle", type: .intptr),
                RuntimeABIParameter(name: "getValueFnPtr", type: .intptr),
                RuntimeABIParameter(name: "setValueFnPtr", type: .intptr),
            ],
            returnType: .intptr,
            section: "Delegate"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_custom_delegate_get_value",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
                RuntimeABIParameter(name: "thisRef", type: .intptr),
                RuntimeABIParameter(name: "property", type: .intptr),
            ],
            returnType: .intptr,
            section: "Delegate"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_custom_delegate_set_value",
            parameters: [
                RuntimeABIParameter(name: "handle", type: .intptr),
                RuntimeABIParameter(name: "thisRef", type: .intptr),
                RuntimeABIParameter(name: "property", type: .intptr),
                RuntimeABIParameter(name: "newValue", type: .intptr),
            ],
            returnType: .intptr,
            section: "Delegate"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_delegate_get_value",
            parameters: [
                RuntimeABIParameter(name: "delegateRaw", type: .intptr),
                RuntimeABIParameter(name: "thisRef", type: .intptr),
                RuntimeABIParameter(name: "property", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Delegate"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_delegate_set_value",
            parameters: [
                RuntimeABIParameter(name: "delegateRaw", type: .intptr),
                RuntimeABIParameter(name: "thisRef", type: .intptr),
                RuntimeABIParameter(name: "property", type: .intptr),
                RuntimeABIParameter(name: "newValue", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Delegate"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_function_invoke",
            parameters: [
                RuntimeABIParameter(name: "functionRaw", type: .intptr),
                RuntimeABIParameter(name: "arg", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Delegate"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_function_invoke_0",
            parameters: [
                RuntimeABIParameter(name: "functionRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Delegate"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_suspend_function_invoke",
            parameters: [
                RuntimeABIParameter(name: "functionRaw", type: .intptr),
                RuntimeABIParameter(name: "arg", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_suspend_function_invoke_0",
            parameters: [
                RuntimeABIParameter(name: "functionRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_function_invoke_2",
            parameters: [
                RuntimeABIParameter(name: "functionRaw", type: .intptr),
                RuntimeABIParameter(name: "arg1", type: .intptr),
                RuntimeABIParameter(name: "arg2", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Delegate"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_function_invoke_3",
            parameters: [
                RuntimeABIParameter(name: "functionRaw", type: .intptr),
                RuntimeABIParameter(name: "arg1", type: .intptr),
                RuntimeABIParameter(name: "arg2", type: .intptr),
                RuntimeABIParameter(name: "arg3", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Delegate"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_function_create_0",
            parameters: [
                RuntimeABIParameter(name: "bodyRaw", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Delegate"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_function_create_1",
            parameters: [
                RuntimeABIParameter(name: "bodyRaw", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Delegate"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_function_create_2",
            parameters: [
                RuntimeABIParameter(name: "bodyRaw", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Delegate"
        ),
    ]
    /// Bitwise/Shift (P5-103)
    public static let bitwiseFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_bitwise_and",
            parameters: [
                RuntimeABIParameter(name: "a", type: .intptr),
                RuntimeABIParameter(name: "b", type: .intptr),
            ],
            returnType: .intptr,
            section: "Bitwise"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_bitwise_or",
            parameters: [
                RuntimeABIParameter(name: "a", type: .intptr),
                RuntimeABIParameter(name: "b", type: .intptr),
            ],
            returnType: .intptr,
            section: "Bitwise"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_bitwise_xor",
            parameters: [
                RuntimeABIParameter(name: "a", type: .intptr),
                RuntimeABIParameter(name: "b", type: .intptr),
            ],
            returnType: .intptr,
            section: "Bitwise"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_op_inv",
            parameters: [
                RuntimeABIParameter(name: "a", type: .intptr),
            ],
            returnType: .intptr,
            section: "Bitwise"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_op_shl",
            parameters: [
                RuntimeABIParameter(name: "a", type: .intptr),
                RuntimeABIParameter(name: "b", type: .intptr),
            ],
            returnType: .intptr,
            section: "Bitwise"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_op_shr",
            parameters: [
                RuntimeABIParameter(name: "a", type: .intptr),
                RuntimeABIParameter(name: "b", type: .intptr),
            ],
            returnType: .intptr,
            section: "Bitwise"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_op_ushr",
            parameters: [
                RuntimeABIParameter(name: "a", type: .intptr),
                RuntimeABIParameter(name: "b", type: .intptr),
            ],
            returnType: .intptr,
            section: "Bitwise"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_op_dmul",
            parameters: [
                RuntimeABIParameter(name: "a", type: .intptr),
                RuntimeABIParameter(name: "b", type: .intptr),
            ],
            returnType: .intptr,
            section: "Bitwise"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_int_toString_radix",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "radix", type: .intptr),
            ],
            returnType: .opaquePointer,
            section: "Bitwise"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_int_countOneBits",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Bitwise"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_int_countLeadingZeroBits",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Bitwise"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_int_countTrailingZeroBits",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Bitwise"
        ),
        // STDLIB-BIT-007: Additional bit manipulation functions
        RuntimeABIFunctionSpec(
            name: "kk_int_rotateLeft",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "distance", type: .intptr),
            ],
            returnType: .intptr,
            section: "Bitwise"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_int_rotateRight",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "distance", type: .intptr),
            ],
            returnType: .intptr,
            section: "Bitwise"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_int_highestOneBit",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Bitwise"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_int_lowestOneBit",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Bitwise"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_int_takeHighestOneBit",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Bitwise"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_int_takeLowestOneBit",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Bitwise"
        ),
        // Long bit manipulation functions
        RuntimeABIFunctionSpec(
            name: "kk_long_rotateLeft",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "distance", type: .intptr),
            ],
            returnType: .intptr,
            section: "Bitwise"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_long_rotateRight",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "distance", type: .intptr),
            ],
            returnType: .intptr,
            section: "Bitwise"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_long_highestOneBit",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Bitwise"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_long_lowestOneBit",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Bitwise"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_long_takeHighestOneBit",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Bitwise"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_long_takeLowestOneBit",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Bitwise"
        ),
        // Int/Long comparison operators
        RuntimeABIFunctionSpec(
            name: "kk_op_eq",
            parameters: [
                RuntimeABIParameter(name: "lhs", type: .intptr),
                RuntimeABIParameter(name: "rhs", type: .intptr),
            ],
            returnType: .intptr,
            section: "Bitwise"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_op_ne",
            parameters: [
                RuntimeABIParameter(name: "lhs", type: .intptr),
                RuntimeABIParameter(name: "rhs", type: .intptr),
            ],
            returnType: .intptr,
            section: "Bitwise"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_op_lt",
            parameters: [
                RuntimeABIParameter(name: "lhs", type: .intptr),
                RuntimeABIParameter(name: "rhs", type: .intptr),
            ],
            returnType: .intptr,
            section: "Bitwise"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_op_le",
            parameters: [
                RuntimeABIParameter(name: "lhs", type: .intptr),
                RuntimeABIParameter(name: "rhs", type: .intptr),
            ],
            returnType: .intptr,
            section: "Bitwise"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_op_gt",
            parameters: [
                RuntimeABIParameter(name: "lhs", type: .intptr),
                RuntimeABIParameter(name: "rhs", type: .intptr),
            ],
            returnType: .intptr,
            section: "Bitwise"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_op_ge",
            parameters: [
                RuntimeABIParameter(name: "lhs", type: .intptr),
                RuntimeABIParameter(name: "rhs", type: .intptr),
            ],
            returnType: .intptr,
            section: "Bitwise"
        ),
        // Int/Long flooring division and modulo operators
        RuntimeABIFunctionSpec(
            name: "kk_op_floor_div",
            parameters: [
                RuntimeABIParameter(name: "lhs", type: .intptr),
                RuntimeABIParameter(name: "rhs", type: .intptr),
            ],
            returnType: .intptr,
            section: "Bitwise"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_op_lfloor_div",
            parameters: [
                RuntimeABIParameter(name: "lhs", type: .intptr),
                RuntimeABIParameter(name: "rhs", type: .intptr),
            ],
            returnType: .intptr,
            section: "Bitwise"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_op_mod",
            parameters: [
                RuntimeABIParameter(name: "lhs", type: .intptr),
                RuntimeABIParameter(name: "rhs", type: .intptr),
            ],
            returnType: .intptr,
            section: "Bitwise"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_op_lmod",
            parameters: [
                RuntimeABIParameter(name: "lhs", type: .intptr),
                RuntimeABIParameter(name: "rhs", type: .intptr),
            ],
            returnType: .intptr,
            section: "Bitwise"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_op_floor_mod",
            parameters: [
                RuntimeABIParameter(name: "lhs", type: .intptr),
                RuntimeABIParameter(name: "rhs", type: .intptr),
            ],
            returnType: .intptr,
            section: "Bitwise"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_op_lfloor_mod",
            parameters: [
                RuntimeABIParameter(name: "lhs", type: .intptr),
                RuntimeABIParameter(name: "rhs", type: .intptr),
            ],
            returnType: .intptr,
            section: "Bitwise"
        ),
    ]

    /// Boolean logical operators
    public static let booleanFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_op_not",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Boolean"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_logical_and",
            parameters: [
                RuntimeABIParameter(name: "lhs", type: .intptr),
                RuntimeABIParameter(name: "rhs", type: .intptr),
            ],
            returnType: .intptr,
            section: "Boolean"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_logical_or",
            parameters: [
                RuntimeABIParameter(name: "lhs", type: .intptr),
                RuntimeABIParameter(name: "rhs", type: .intptr),
            ],
            returnType: .intptr,
            section: "Boolean"
        ),
    ]

    /// Char operations
    public static let charFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_char_minus",
            parameters: [
                RuntimeABIParameter(name: "lhsRaw", type: .intptr),
                RuntimeABIParameter(name: "rhsRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Char"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_char_plus",
            parameters: [
                RuntimeABIParameter(name: "charValue", type: .intptr),
                RuntimeABIParameter(name: "stringRaw", type: .intptr),
            ],
            returnType: .opaquePointer,
            section: "Char"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_char_get",
            parameters: [
                RuntimeABIParameter(name: "charValue", type: .intptr),
                RuntimeABIParameter(name: "index", type: .intptr),
            ],
            returnType: .intptr,
            section: "Char"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_char_rangeTo",
            parameters: [
                RuntimeABIParameter(name: "startValue", type: .intptr),
                RuntimeABIParameter(name: "endValue", type: .intptr),
            ],
            returnType: .intptr,
            section: "Char"
        ),
    ]

    /// Regex (STDLIB-100/101/102/103)
    public static let regexFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_regex_create",
            parameters: [
                RuntimeABIParameter(name: "pattern", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_matches_regex",
            parameters: [
                RuntimeABIParameter(name: "str", type: .intptr),
                RuntimeABIParameter(name: "regex", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_contains_regex",
            parameters: [
                RuntimeABIParameter(name: "str", type: .intptr),
                RuntimeABIParameter(name: "regex", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_regex_find",
            parameters: [
                RuntimeABIParameter(name: "regex", type: .intptr),
                RuntimeABIParameter(name: "input", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_regex_findAll",
            parameters: [
                RuntimeABIParameter(name: "regex", type: .intptr),
                RuntimeABIParameter(name: "input", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_replace_regex",
            parameters: [
                RuntimeABIParameter(name: "str", type: .intptr),
                RuntimeABIParameter(name: "regex", type: .intptr),
                RuntimeABIParameter(name: "replacement", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_split_regex",
            parameters: [
                RuntimeABIParameter(name: "str", type: .intptr),
                RuntimeABIParameter(name: "regex", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_toRegex",
            parameters: [
                RuntimeABIParameter(name: "str", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_regex_pattern",
            parameters: [
                RuntimeABIParameter(name: "regex", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex"
        ),
        // STDLIB-REGEX-096: Regex.options: Set<RegexOption>
        RuntimeABIFunctionSpec(
            name: "kk_regex_options",
            parameters: [
                RuntimeABIParameter(name: "regex", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_match_result_value",
            parameters: [
                RuntimeABIParameter(name: "matchResult", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_match_result_groupValues",
            parameters: [
                RuntimeABIParameter(name: "matchResult", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex"
        ),
        // STDLIB-351: Regex.replace lambda / STDLIB-350: Regex.matchEntire
        RuntimeABIFunctionSpec(
            name: "kk_regex_replace_lambda",
            parameters: [
                RuntimeABIParameter(name: "regexRaw", type: .intptr),
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Regex"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_regex_matchEntire",
            parameters: [
                RuntimeABIParameter(name: "regexRaw", type: .intptr),
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex"
        ),
        // STDLIB-480: Regex(pattern, option) constructor
        RuntimeABIFunctionSpec(
            name: "kk_regex_create_with_option",
            parameters: [
                RuntimeABIParameter(name: "patternRaw", type: .intptr),
                RuntimeABIParameter(name: "optionRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex"
        ),
        // STDLIB-480: Regex(pattern, options: Set<RegexOption>) constructor
        RuntimeABIFunctionSpec(
            name: "kk_regex_create_with_options",
            parameters: [
                RuntimeABIParameter(name: "patternRaw", type: .intptr),
                RuntimeABIParameter(name: "optionsSetRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex"
        ),
        // STDLIB-480: Regex.containsMatchIn(input)
        RuntimeABIFunctionSpec(
            name: "kk_regex_containsMatchIn",
            parameters: [
                RuntimeABIParameter(name: "regexRaw", type: .intptr),
                RuntimeABIParameter(name: "inputRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex"
        ),
        // MatchResult.groups / MatchGroupCollection / MatchGroup
        RuntimeABIFunctionSpec(
            name: "kk_match_result_groups",
            parameters: [
                RuntimeABIParameter(name: "matchRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_match_group_collection_get",
            parameters: [
                RuntimeABIParameter(name: "collectionRaw", type: .intptr),
                RuntimeABIParameter(name: "nameRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_match_group_value",
            parameters: [
                RuntimeABIParameter(name: "groupRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_match_group_range",
            parameters: [
                RuntimeABIParameter(name: "groupRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex"
        ),
        // STDLIB-REGEX-094: Regex.matches(input)
        // STDLIB-REGEX-094: Regex.fromLiteral
        // First param is the Companion object receiver (ignored at runtime).
        RuntimeABIFunctionSpec(
            name: "kk_regex_from_literal",
            parameters: [
                RuntimeABIParameter(name: "companionRef", type: .intptr),
                RuntimeABIParameter(name: "literalRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex"
        ),
        // STDLIB-REGEX-094: String.replaceFirst(Regex, replacement)
        RuntimeABIFunctionSpec(
            name: "kk_string_replaceFirst_regex",
            parameters: [
                RuntimeABIParameter(name: "str", type: .intptr),
                RuntimeABIParameter(name: "regex", type: .intptr),
                RuntimeABIParameter(name: "replacement", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex"
        ),
        // STDLIB-REGEX-097: Regex.groupNames
        RuntimeABIFunctionSpec(
            name: "kk_regex_group_names",
            parameters: [
                RuntimeABIParameter(name: "regexRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Regex"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_chunked",
            parameters: [
                RuntimeABIParameter(name: "str", type: .intptr),
                RuntimeABIParameter(name: "size", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_chunkedSequence_transform",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "size", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_windowed_default",
            parameters: [
                RuntimeABIParameter(name: "str", type: .intptr),
                RuntimeABIParameter(name: "size", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_windowed",
            parameters: [
                RuntimeABIParameter(name: "str", type: .intptr),
                RuntimeABIParameter(name: "size", type: .intptr),
                RuntimeABIParameter(name: "step", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_windowed_partial",
            parameters: [
                RuntimeABIParameter(name: "str", type: .intptr),
                RuntimeABIParameter(name: "size", type: .intptr),
                RuntimeABIParameter(name: "step", type: .intptr),
                RuntimeABIParameter(name: "partialWindows", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_windowedSequence_partial",
            parameters: [
                RuntimeABIParameter(name: "str", type: .intptr),
                RuntimeABIParameter(name: "size", type: .intptr),
                RuntimeABIParameter(name: "step", type: .intptr),
                RuntimeABIParameter(name: "partialWindows", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_windowedSequence_transform",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "size", type: .intptr),
                RuntimeABIParameter(name: "step", type: .intptr),
                RuntimeABIParameter(name: "partialWindows", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        // STDLIB-318: commonPrefixWith / commonSuffixWith
        RuntimeABIFunctionSpec(
            name: "kk_string_commonPrefixWith",
            parameters: [
                RuntimeABIParameter(name: "str", type: .intptr),
                RuntimeABIParameter(name: "other", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_commonSuffixWith",
            parameters: [
                RuntimeABIParameter(name: "str", type: .intptr),
                RuntimeABIParameter(name: "other", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        // STDLIB-575/576: commonPrefixWith / commonSuffixWith (ignoreCase overloads)
        RuntimeABIFunctionSpec(
            name: "kk_string_commonPrefixWith_ignoreCase",
            parameters: [
                RuntimeABIParameter(name: "str", type: .intptr),
                RuntimeABIParameter(name: "other", type: .intptr),
                RuntimeABIParameter(name: "ignoreCaseRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_commonSuffixWith_ignoreCase",
            parameters: [
                RuntimeABIParameter(name: "str", type: .intptr),
                RuntimeABIParameter(name: "other", type: .intptr),
                RuntimeABIParameter(name: "ignoreCaseRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        // STDLIB-316: String.zipWithNext()
        RuntimeABIFunctionSpec(
            name: "kk_string_zipWithNext",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        // STDLIB-316: String.zipWithNext(transform: (Char, Char) -> R)
        RuntimeABIFunctionSpec(
            name: "kk_string_zipWithNextTransform",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "String"
        ),
        // STDLIB-317: String.asSequence / asIterable
        RuntimeABIFunctionSpec(
            name: "kk_string_asSequence",
            parameters: [
                RuntimeABIParameter(name: "str", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
    ]

    // MARK: - File I/O (STDLIB-320/321/322/323)

    public static let fileIOFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_file_new",
            parameters: [
                RuntimeABIParameter(name: "pathRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_file_readText",
            parameters: [
                RuntimeABIParameter(name: "fileRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_file_writeText",
            parameters: [
                RuntimeABIParameter(name: "fileRaw", type: .intptr),
                RuntimeABIParameter(name: "textRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_file_appendText",
            parameters: [
                RuntimeABIParameter(name: "fileRaw", type: .intptr),
                RuntimeABIParameter(name: "textRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_file_readLines",
            parameters: [
                RuntimeABIParameter(name: "fileRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_file_readBytes",
            parameters: [
                RuntimeABIParameter(name: "fileRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_file_forEachLine",
            parameters: [
                RuntimeABIParameter(name: "fileRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_file_exists",
            parameters: [
                RuntimeABIParameter(name: "fileRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_file_isFile",
            parameters: [
                RuntimeABIParameter(name: "fileRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_file_isDirectory",
            parameters: [
                RuntimeABIParameter(name: "fileRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_file_name",
            parameters: [
                RuntimeABIParameter(name: "fileRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_file_path",
            parameters: [
                RuntimeABIParameter(name: "fileRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_file_delete",
            parameters: [
                RuntimeABIParameter(name: "fileRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_file_mkdirs",
            parameters: [
                RuntimeABIParameter(name: "fileRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_file_listFiles",
            parameters: [
                RuntimeABIParameter(name: "fileRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_file_walk",
            parameters: [
                RuntimeABIParameter(name: "fileRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        // STDLIB-567: File.bufferedReader()
        RuntimeABIFunctionSpec(
            name: "kk_file_bufferedReader",
            parameters: [
                RuntimeABIParameter(name: "fileRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_buffered_reader_readLine",
            parameters: [
                RuntimeABIParameter(name: "readerRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_buffered_reader_readLines",
            parameters: [
                RuntimeABIParameter(name: "readerRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_buffered_reader_close",
            parameters: [
                RuntimeABIParameter(name: "readerRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        // STDLIB-IO-091: BufferedReader.read() / ready()
        RuntimeABIFunctionSpec(
            name: "kk_buffered_reader_read",
            parameters: [
                RuntimeABIParameter(name: "readerRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_buffered_reader_ready",
            parameters: [
                RuntimeABIParameter(name: "readerRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        // STDLIB-IO-091/093: BufferedWriter
        RuntimeABIFunctionSpec(
            name: "kk_file_bufferedWriter",
            parameters: [
                RuntimeABIParameter(name: "fileRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_buffered_writer_write",
            parameters: [
                RuntimeABIParameter(name: "writerRaw", type: .intptr),
                RuntimeABIParameter(name: "textRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_buffered_writer_new_line",
            parameters: [
                RuntimeABIParameter(name: "writerRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_buffered_writer_flush",
            parameters: [
                RuntimeABIParameter(name: "writerRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_buffered_writer_close",
            parameters: [
                RuntimeABIParameter(name: "writerRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_file_inputStream",
            parameters: [
                RuntimeABIParameter(name: "fileRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_file_outputStream",
            parameters: [
                RuntimeABIParameter(name: "fileRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_bytearrayinputstream_new",
            parameters: [
                RuntimeABIParameter(name: "bufferRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_input_stream_read",
            parameters: [
                RuntimeABIParameter(name: "streamRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_input_stream_available",
            parameters: [
                RuntimeABIParameter(name: "streamRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_input_stream_skip",
            parameters: [
                RuntimeABIParameter(name: "streamRaw", type: .intptr),
                RuntimeABIParameter(name: "countRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_input_stream_read_bytes",
            parameters: [
                RuntimeABIParameter(name: "streamRaw", type: .intptr),
                RuntimeABIParameter(name: "bytesRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_input_stream_close",
            parameters: [
                RuntimeABIParameter(name: "streamRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_output_stream_write_byte",
            parameters: [
                RuntimeABIParameter(name: "streamRaw", type: .intptr),
                RuntimeABIParameter(name: "valueRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_output_stream_write_bytes",
            parameters: [
                RuntimeABIParameter(name: "streamRaw", type: .intptr),
                RuntimeABIParameter(name: "bytesRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_output_stream_flush",
            parameters: [
                RuntimeABIParameter(name: "streamRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_output_stream_close",
            parameters: [
                RuntimeABIParameter(name: "streamRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_classloader_getSystemClassLoader",
            parameters: [],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_classloader_getResource",
            parameters: [
                RuntimeABIParameter(name: "loaderRaw", type: .intptr),
                RuntimeABIParameter(name: "nameRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_classloader_getResourceAsStream",
            parameters: [
                RuntimeABIParameter(name: "loaderRaw", type: .intptr),
                RuntimeABIParameter(name: "nameRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_resource_exists",
            parameters: [
                RuntimeABIParameter(name: "nameRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_readResourceAsText",
            parameters: [
                RuntimeABIParameter(name: "nameRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_resource_stream_read",
            parameters: [
                RuntimeABIParameter(name: "streamRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_resource_stream_close",
            parameters: [
                RuntimeABIParameter(name: "streamRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_file_useLines",
            parameters: [
                RuntimeABIParameter(name: "fileRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uri_new",
            parameters: [
                RuntimeABIParameter(name: "specRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(name: "kk_uri_toString", parameters: [RuntimeABIParameter(name: "uriRaw", type: .intptr)], returnType: .intptr, section: "FileIO"),
        RuntimeABIFunctionSpec(name: "kk_uri_scheme", parameters: [RuntimeABIParameter(name: "uriRaw", type: .intptr)], returnType: .intptr, section: "FileIO"),
        RuntimeABIFunctionSpec(name: "kk_uri_authority", parameters: [RuntimeABIParameter(name: "uriRaw", type: .intptr)], returnType: .intptr, section: "FileIO"),
        RuntimeABIFunctionSpec(name: "kk_uri_path", parameters: [RuntimeABIParameter(name: "uriRaw", type: .intptr)], returnType: .intptr, section: "FileIO"),
        RuntimeABIFunctionSpec(name: "kk_uri_query", parameters: [RuntimeABIParameter(name: "uriRaw", type: .intptr)], returnType: .intptr, section: "FileIO"),
        RuntimeABIFunctionSpec(name: "kk_uri_fragment", parameters: [RuntimeABIParameter(name: "uriRaw", type: .intptr)], returnType: .intptr, section: "FileIO"),
        RuntimeABIFunctionSpec(name: "kk_uri_normalize", parameters: [RuntimeABIParameter(name: "uriRaw", type: .intptr)], returnType: .intptr, section: "FileIO"),
        RuntimeABIFunctionSpec(
            name: "kk_uri_resolve",
            parameters: [
                RuntimeABIParameter(name: "baseRaw", type: .intptr),
                RuntimeABIParameter(name: "otherRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uri_relativize",
            parameters: [
                RuntimeABIParameter(name: "baseRaw", type: .intptr),
                RuntimeABIParameter(name: "otherRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_url_new",
            parameters: [
                RuntimeABIParameter(name: "specRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_url_new_relative",
            parameters: [
                RuntimeABIParameter(name: "baseRaw", type: .intptr),
                RuntimeABIParameter(name: "relativeRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(name: "kk_url_protocol", parameters: [RuntimeABIParameter(name: "urlRaw", type: .intptr)], returnType: .intptr, section: "FileIO"),
        RuntimeABIFunctionSpec(name: "kk_url_host", parameters: [RuntimeABIParameter(name: "urlRaw", type: .intptr)], returnType: .intptr, section: "FileIO"),
        RuntimeABIFunctionSpec(name: "kk_url_port", parameters: [RuntimeABIParameter(name: "urlRaw", type: .intptr)], returnType: .intptr, section: "FileIO"),
        RuntimeABIFunctionSpec(name: "kk_url_path", parameters: [RuntimeABIParameter(name: "urlRaw", type: .intptr)], returnType: .intptr, section: "FileIO"),
        RuntimeABIFunctionSpec(name: "kk_url_query", parameters: [RuntimeABIParameter(name: "urlRaw", type: .intptr)], returnType: .intptr, section: "FileIO"),
        RuntimeABIFunctionSpec(name: "kk_url_fragment", parameters: [RuntimeABIParameter(name: "urlRaw", type: .intptr)], returnType: .intptr, section: "FileIO"),
        RuntimeABIFunctionSpec(
            name: "kk_url_toURI",
            parameters: [
                RuntimeABIParameter(name: "urlRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(name: "kk_url_toExternalForm", parameters: [RuntimeABIParameter(name: "urlRaw", type: .intptr)], returnType: .intptr, section: "FileIO"),
        RuntimeABIFunctionSpec(
            name: "kk_url_sameFile",
            parameters: [
                RuntimeABIParameter(name: "lhsRaw", type: .intptr),
                RuntimeABIParameter(name: "rhsRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_url_equals",
            parameters: [
                RuntimeABIParameter(name: "lhsRaw", type: .intptr),
                RuntimeABIParameter(name: "rhsRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(name: "kk_url_hashCode", parameters: [RuntimeABIParameter(name: "urlRaw", type: .intptr)], returnType: .intptr, section: "FileIO"),
        RuntimeABIFunctionSpec(name: "kk_url_encode", parameters: [RuntimeABIParameter(name: "valueRaw", type: .intptr)], returnType: .intptr, section: "FileIO"),
        RuntimeABIFunctionSpec(name: "kk_url_decode", parameters: [RuntimeABIParameter(name: "valueRaw", type: .intptr)], returnType: .intptr, section: "FileIO"),
        // STDLIB-IO-087: Additional File operations
        RuntimeABIFunctionSpec(
            name: "kk_file_new_parent_child",
            parameters: [
                RuntimeABIParameter(name: "parentRaw", type: .intptr),
                RuntimeABIParameter(name: "childRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_file_absolutePath",
            parameters: [
                RuntimeABIParameter(name: "fileRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_file_canonicalPath",
            parameters: [
                RuntimeABIParameter(name: "fileRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_file_parent",
            parameters: [
                RuntimeABIParameter(name: "fileRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_file_length",
            parameters: [
                RuntimeABIParameter(name: "fileRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_file_lastModified",
            parameters: [
                RuntimeABIParameter(name: "fileRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_file_createNewFile",
            parameters: [
                RuntimeABIParameter(name: "fileRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_file_canRead",
            parameters: [
                RuntimeABIParameter(name: "fileRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_file_canWrite",
            parameters: [
                RuntimeABIParameter(name: "fileRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_file_canExecute",
            parameters: [
                RuntimeABIParameter(name: "fileRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(name: "kk_logger_getLogger", parameters: [RuntimeABIParameter(name: "nameRaw", type: .intptr)], returnType: .intptr, section: "FileIO"),
        RuntimeABIFunctionSpec(name: "kk_logging_level_info", parameters: [], returnType: .intptr, section: "FileIO"),
        RuntimeABIFunctionSpec(name: "kk_logging_level_config", parameters: [], returnType: .intptr, section: "FileIO"),
        RuntimeABIFunctionSpec(name: "kk_logging_level_fine", parameters: [], returnType: .intptr, section: "FileIO"),
        RuntimeABIFunctionSpec(name: "kk_logging_level_finer", parameters: [], returnType: .intptr, section: "FileIO"),
        RuntimeABIFunctionSpec(name: "kk_logging_level_finest", parameters: [], returnType: .intptr, section: "FileIO"),
        RuntimeABIFunctionSpec(name: "kk_logging_level_warning", parameters: [], returnType: .intptr, section: "FileIO"),
        RuntimeABIFunctionSpec(name: "kk_logging_level_severe", parameters: [], returnType: .intptr, section: "FileIO"),
        RuntimeABIFunctionSpec(name: "kk_console_handler_new", parameters: [], returnType: .intptr, section: "FileIO"),
        RuntimeABIFunctionSpec(name: "kk_file_handler_new", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr)], returnType: .intptr, section: "FileIO"),
        RuntimeABIFunctionSpec(name: "kk_logger_addHandler", parameters: [RuntimeABIParameter(name: "loggerRaw", type: .intptr), RuntimeABIParameter(name: "handlerRaw", type: .intptr)], returnType: .intptr, section: "FileIO"),
        RuntimeABIFunctionSpec(name: "kk_logger_log", parameters: [RuntimeABIParameter(name: "loggerRaw", type: .intptr), RuntimeABIParameter(name: "levelRaw", type: .intptr), RuntimeABIParameter(name: "messageRaw", type: .intptr)], returnType: .intptr, section: "FileIO"),
        RuntimeABIFunctionSpec(name: "kk_logger_log_throwable", parameters: [RuntimeABIParameter(name: "loggerRaw", type: .intptr), RuntimeABIParameter(name: "levelRaw", type: .intptr), RuntimeABIParameter(name: "messageRaw", type: .intptr), RuntimeABIParameter(name: "throwableRaw", type: .intptr)], returnType: .intptr, section: "FileIO"),
        RuntimeABIFunctionSpec(name: "kk_logger_info", parameters: [RuntimeABIParameter(name: "loggerRaw", type: .intptr), RuntimeABIParameter(name: "messageRaw", type: .intptr)], returnType: .intptr, section: "FileIO"),
        RuntimeABIFunctionSpec(name: "kk_logger_warning", parameters: [RuntimeABIParameter(name: "loggerRaw", type: .intptr), RuntimeABIParameter(name: "messageRaw", type: .intptr)], returnType: .intptr, section: "FileIO"),
        RuntimeABIFunctionSpec(name: "kk_logger_severe", parameters: [RuntimeABIParameter(name: "loggerRaw", type: .intptr), RuntimeABIParameter(name: "messageRaw", type: .intptr)], returnType: .intptr, section: "FileIO"),
        RuntimeABIFunctionSpec(name: "kk_message_digest_getInstance", parameters: [RuntimeABIParameter(name: "algorithmRaw", type: .intptr), RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer)], returnType: .intptr, section: "FileIO"),
        RuntimeABIFunctionSpec(name: "kk_message_digest_digest", parameters: [RuntimeABIParameter(name: "digestRaw", type: .intptr), RuntimeABIParameter(name: "dataRaw", type: .intptr), RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer)], returnType: .intptr, section: "FileIO"),
        RuntimeABIFunctionSpec(name: "kk_mac_getInstance", parameters: [RuntimeABIParameter(name: "algorithmRaw", type: .intptr), RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer)], returnType: .intptr, section: "FileIO"),
        RuntimeABIFunctionSpec(name: "kk_mac_init", parameters: [RuntimeABIParameter(name: "macRaw", type: .intptr), RuntimeABIParameter(name: "keyRaw", type: .intptr), RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer)], returnType: .intptr, section: "FileIO"),
        RuntimeABIFunctionSpec(name: "kk_mac_doFinal", parameters: [RuntimeABIParameter(name: "macRaw", type: .intptr), RuntimeABIParameter(name: "dataRaw", type: .intptr), RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer)], returnType: .intptr, section: "FileIO"),
        RuntimeABIFunctionSpec(name: "kk_cache_new", parameters: [RuntimeABIParameter(name: "capacityRaw", type: .intptr)], returnType: .intptr, section: "FileIO"),
        RuntimeABIFunctionSpec(name: "kk_cache_put", parameters: [RuntimeABIParameter(name: "cacheRaw", type: .intptr), RuntimeABIParameter(name: "keyRaw", type: .intptr), RuntimeABIParameter(name: "valueRaw", type: .intptr)], returnType: .intptr, section: "FileIO"),
        RuntimeABIFunctionSpec(name: "kk_cache_get", parameters: [RuntimeABIParameter(name: "cacheRaw", type: .intptr), RuntimeABIParameter(name: "keyRaw", type: .intptr)], returnType: .intptr, section: "FileIO"),
        RuntimeABIFunctionSpec(name: "kk_cache_size", parameters: [RuntimeABIParameter(name: "cacheRaw", type: .intptr)], returnType: .intptr, section: "FileIO"),
        RuntimeABIFunctionSpec(
            name: "kk_resource_bundle_getBundle",
            parameters: [
                RuntimeABIParameter(name: "nameRaw", type: .intptr),
                RuntimeABIParameter(name: "localeRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_resource_bundle_getString",
            parameters: [
                RuntimeABIParameter(name: "bundleRaw", type: .intptr),
                RuntimeABIParameter(name: "keyRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_resource_bundle_getObject",
            parameters: [
                RuntimeABIParameter(name: "bundleRaw", type: .intptr),
                RuntimeABIParameter(name: "keyRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_resource_bundle_getKeys",
            parameters: [RuntimeABIParameter(name: "bundleRaw", type: .intptr)],
            returnType: .intptr,
            section: "FileIO"
        ),
    ]

    // MARK: - I18N (STDLIB-I18N-153)

    public static let i18nFunctions: [RuntimeABIFunctionSpec] = [
        // STDLIB-I18N-152: NumberFormat
        RuntimeABIFunctionSpec(
            name: "kk_numberformat_getIntegerInstance",
            parameters: [
                RuntimeABIParameter(name: "localeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "I18N"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_numberformat_getNumberInstance",
            parameters: [
                RuntimeABIParameter(name: "localeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "I18N"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_numberformat_getCurrencyInstance",
            parameters: [
                RuntimeABIParameter(name: "localeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "I18N"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_numberformat_getPercentInstance",
            parameters: [
                RuntimeABIParameter(name: "localeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "I18N"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_numberformat_formatInt",
            parameters: [
                RuntimeABIParameter(name: "formatRaw", type: .intptr),
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "I18N"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_numberformat_formatLong",
            parameters: [
                RuntimeABIParameter(name: "formatRaw", type: .intptr),
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "I18N"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_numberformat_formatFloat",
            parameters: [
                RuntimeABIParameter(name: "formatRaw", type: .intptr),
                RuntimeABIParameter(name: "value", type: .float),
            ],
            returnType: .intptr,
            section: "I18N"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_numberformat_formatDouble",
            parameters: [
                RuntimeABIParameter(name: "formatRaw", type: .intptr),
                RuntimeABIParameter(name: "value", type: .double),
            ],
            returnType: .intptr,
            section: "I18N"
        ),
        // STDLIB-I18N-153: DateFormat
        RuntimeABIFunctionSpec(
            name: "kk_dateformat_ofPattern",
            parameters: [
                RuntimeABIParameter(name: "patternRaw", type: .intptr),
                RuntimeABIParameter(name: "localeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "I18N"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_dateformat_ofPatternWithTimeZone",
            parameters: [
                RuntimeABIParameter(name: "patternRaw", type: .intptr),
                RuntimeABIParameter(name: "localeRaw", type: .intptr),
                RuntimeABIParameter(name: "timeZoneRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "I18N"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_dateformat_getDateInstance",
            parameters: [
                RuntimeABIParameter(name: "localeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "I18N"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_dateformat_getDateInstanceWithTimeZone",
            parameters: [
                RuntimeABIParameter(name: "localeRaw", type: .intptr),
                RuntimeABIParameter(name: "timeZoneRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "I18N"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_dateformat_getTimeInstance",
            parameters: [
                RuntimeABIParameter(name: "localeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "I18N"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_dateformat_getTimeInstanceWithTimeZone",
            parameters: [
                RuntimeABIParameter(name: "localeRaw", type: .intptr),
                RuntimeABIParameter(name: "timeZoneRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "I18N"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_dateformat_getDateTimeInstance",
            parameters: [
                RuntimeABIParameter(name: "localeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "I18N"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_dateformat_getDateTimeInstanceWithTimeZone",
            parameters: [
                RuntimeABIParameter(name: "localeRaw", type: .intptr),
                RuntimeABIParameter(name: "timeZoneRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "I18N"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_dateformat_ofPatternDefaultLocale",
            parameters: [
                RuntimeABIParameter(name: "patternRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "I18N"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_dateformat_format",
            parameters: [
                RuntimeABIParameter(name: "formatRaw", type: .intptr),
                RuntimeABIParameter(name: "epochMillis", type: .intptr),
            ],
            returnType: .intptr,
            section: "I18N"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_dateformat_parse",
            parameters: [
                RuntimeABIParameter(name: "formatRaw", type: .intptr),
                RuntimeABIParameter(name: "stringRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "I18N"
        ),
    ]

    // MARK: - Path (STDLIB-IO-089)

    public static let pathFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(name: "kk_path_new", parameters: [RuntimeABIParameter(name: "pathStringRaw", type: .intptr)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_name", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_fileName", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_parent", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_root", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_nameCount", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_toString", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_resolve_string", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "otherRaw", type: .intptr)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_resolve_path", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "otherRaw", type: .intptr)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_relativize", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "otherRaw", type: .intptr)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_normalize", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_exists", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_isDirectory", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_isRegularFile", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_isAbsolute", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_readText", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_writeText", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "textRaw", type: .intptr), RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_readLines", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_createDirectories", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_deleteIfExists", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_listDirectoryEntries", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_equals", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "otherRaw", type: .intptr)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_startsWith_path", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "otherRaw", type: .intptr)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_startsWith_string", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "otherRaw", type: .intptr)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_endsWith_path", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "otherRaw", type: .intptr)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_endsWith_string", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "otherRaw", type: .intptr)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_toFile", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_toUri", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_get", parameters: [RuntimeABIParameter(name: "pathStringRaw", type: .intptr)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_toAbsolutePath", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr)], returnType: .intptr, section: "Path"),
        RuntimeABIFunctionSpec(name: "kk_path_getName", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr), RuntimeABIParameter(name: "indexRaw", type: .intptr)], returnType: .intptr, section: "Path"),
    ]

    // MARK: - Duration / measureTime (STDLIB-230/231)

    public static let durationFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_measureTime",
            parameters: [
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_inWholeMilliseconds",
            parameters: [
                RuntimeABIParameter(name: "durationRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_inWholeSeconds",
            parameters: [
                RuntimeABIParameter(name: "durationRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_inWholeMinutes",
            parameters: [
                RuntimeABIParameter(name: "durationRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_inWholeMicroseconds",
            parameters: [
                RuntimeABIParameter(name: "durationRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_inWholeNanoseconds",
            parameters: [
                RuntimeABIParameter(name: "durationRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_inWholeHours",
            parameters: [
                RuntimeABIParameter(name: "durationRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_inWholeDays",
            parameters: [
                RuntimeABIParameter(name: "durationRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_toString",
            parameters: [
                RuntimeABIParameter(name: "durationRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_toIsoString",
            parameters: [
                RuntimeABIParameter(name: "durationRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_toComponents_seconds",
            parameters: [
                RuntimeABIParameter(name: "durationRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_toComponents_minutes",
            parameters: [
                RuntimeABIParameter(name: "durationRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_toComponents_hours",
            parameters: [
                RuntimeABIParameter(name: "durationRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_toComponents_days",
            parameters: [
                RuntimeABIParameter(name: "durationRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_parse",
            parameters: [
                RuntimeABIParameter(name: "valueRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_parseOrNull",
            parameters: [
                RuntimeABIParameter(name: "valueRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_parseIsoString",
            parameters: [
                RuntimeABIParameter(name: "valueRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_parseIsoStringOrNull",
            parameters: [
                RuntimeABIParameter(name: "valueRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_zero",
            parameters: [],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_infinite",
            parameters: [],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_from_seconds",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_from_milliseconds",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_from_microseconds",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_from_nanoseconds",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_from_minutes",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_from_hours",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_from_days",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_from_seconds_long",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_from_milliseconds_long",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_from_microseconds_long",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_from_nanoseconds_long",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_from_minutes_long",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_from_hours_long",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_from_days_long",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_from_seconds_double",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_from_milliseconds_double",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_from_microseconds_double",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_from_nanoseconds_double",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_from_minutes_double",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_from_hours_double",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_from_days_double",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_toDuration_int",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "unitOrdinal", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_toDuration_long",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "unitOrdinal", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_toDuration_double",
            parameters: [
                RuntimeABIParameter(name: "valueBits", type: .intptr),
                RuntimeABIParameter(name: "unitOrdinal", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_absoluteValue",
            parameters: [
                RuntimeABIParameter(name: "durationRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_plus",
            parameters: [
                RuntimeABIParameter(name: "lhsRaw", type: .intptr),
                RuntimeABIParameter(name: "rhsRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_minus",
            parameters: [
                RuntimeABIParameter(name: "lhsRaw", type: .intptr),
                RuntimeABIParameter(name: "rhsRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_compareTo",
            parameters: [
                RuntimeABIParameter(name: "lhsRaw", type: .intptr),
                RuntimeABIParameter(name: "rhsRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_div_duration",
            parameters: [
                RuntimeABIParameter(name: "lhsRaw", type: .intptr),
                RuntimeABIParameter(name: "rhsRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_duration_to_java_duration",
            parameters: [
                RuntimeABIParameter(name: "durationRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_java_duration_to_kotlin_duration",
            parameters: [
                RuntimeABIParameter(name: "durationRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_measureTimedValue",
            parameters: [
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_timedvalue_new",
            parameters: [
                RuntimeABIParameter(name: "valueRaw", type: .intptr),
                RuntimeABIParameter(name: "durationRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_timedvalue_value",
            parameters: [
                RuntimeABIParameter(name: "timedValueRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_timedvalue_duration",
            parameters: [
                RuntimeABIParameter(name: "timedValueRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_timedvalue_toString",
            parameters: [
                RuntimeABIParameter(name: "timedValueRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_time_source_mark_now",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_time_source_monotonic_mark_now",
            parameters: [
                RuntimeABIParameter(name: "receiver", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_time_mark_elapsed_now",
            parameters: [
                RuntimeABIParameter(name: "markRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_time_mark_has_passed_now",
            parameters: [
                RuntimeABIParameter(name: "markRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_time_mark_has_not_passed_now",
            parameters: [
                RuntimeABIParameter(name: "markRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_time_mark_plus_duration",
            parameters: [
                RuntimeABIParameter(name: "markRaw", type: .intptr),
                RuntimeABIParameter(name: "durationRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_time_mark_minus_duration",
            parameters: [
                RuntimeABIParameter(name: "markRaw", type: .intptr),
                RuntimeABIParameter(name: "durationRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_time_mark_minus_mark",
            parameters: [
                RuntimeABIParameter(name: "lhsRaw", type: .intptr),
                RuntimeABIParameter(name: "rhsRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_time_mark_compare",
            parameters: [
                RuntimeABIParameter(name: "lhsRaw", type: .intptr),
                RuntimeABIParameter(name: "rhsRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Duration"
        ),
    ]

    public static let allFunctions: [RuntimeABIFunctionSpec] =
        memoryFunctions
            + exceptionFunctions
            + testFunctions
            + stringFunctions
            + stringBridgeFunctions
            + consolePrintFunctions
            + ioFunctions
            + systemFunctions
            + gcFunctions
            + coroutineFunctions
            + boxingFunctions
            + arrayFunctions
            + operatorFunctions
            + primitiveNumericConversionFunctions
            + numericRuntimeBridgeFunctions
            + rangeFunctions
            + kPropertyStubFunctions + kParameterFunctions + kFunctionFunctions + callableRefFunctions + delegateFunctions
            + dispatchBridgeFunctions
            + bitwiseFunctions
            + booleanFunctions
            + charFunctions
            + mathFunctions
            + randomFunctions
            + collectionFunctions
            + collectionBridgeFunctions
            + runtimeOnlyBridgeFunctions
            + sequenceFunctions
            + regexFunctions
            + base64Functions
            + hexFormatFunctions
            + comparatorFunctions
            + resultFunctions
            + kotlinVersionFunctions
            + deepRecursiveFunctions
            + stringBuilderFunctions
            + fileIOFunctions
            + pathFunctions
            + i18nFunctions
            + uuidFunctions
            + durationFunctions
            + timeAndPathBridgeFunctions
            + atomicFunctions
            + nativeRefFunctions
            + threadLocalFunctions
            + threadFunctions
            + securityFunctions
            + parallelFunctions
            + bigIntegerFunctions
            + broadcastChannelFunctions
            + serializationFunctions
            + networkFunctions
            + abiParityFunctions

    public static func generateCHeader() -> String {
        var lines: [String] = []
        lines.append("#ifndef KK_RUNTIME_ABI_H")
        lines.append("#define KK_RUNTIME_ABI_H")
        lines.append("")
        lines.append("#include <stdint.h>")
        lines.append("#include <stddef.h>")
        lines.append("")
        lines.append("/* KSwiftK Runtime C ABI \u{2013} spec \(specVersion) */")
        lines.append("/* Auto-generated from RuntimeABISpec. Do NOT edit manually. */")
        lines.append("")
        lines.append("typedef struct KTypeInfo KTypeInfo;")
        lines.append("")

        var currentSection = ""
        for spec in allFunctions {
            if spec.section != currentSection {
                currentSection = spec.section
                lines.append("")
                lines.append("/* --- \(currentSection) --- */")
            }
            lines.append(spec.cDeclaration)
        }

        lines.append("")
        lines.append("#endif /* KK_RUNTIME_ABI_H */")
        lines.append("")
        return lines.joined(separator: "\n")
    }
}
