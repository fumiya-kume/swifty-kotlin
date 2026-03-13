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

    /// Parameter types only (no names), for ABI reconciliation with CompilerCore's RuntimeABIExterns.
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
    public static let specVersion = "J24"

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
        // STDLIB-171: enumValues<T>()
        RuntimeABIFunctionSpec(
            name: "kk_enum_make_values_array",
            parameters: [
                RuntimeABIParameter(name: "count", type: .intptr),
            ],
            returnType: .intptr,
            section: "Exception"
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
            name: "kk_string_trimEnd",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
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
            name: "kk_char_isWhitespace",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
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
            name: "kk_char_lowercase",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
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
            name: "kk_string_take",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "nRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_drop",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "nRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_takeLast",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "nRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "String"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_string_dropLast",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "nRaw", type: .intptr),
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
            name: "kk_string_substringAfter",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "delimiterRaw", type: .intptr),
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
    ]

    public static let printlnFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_print_any",
            parameters: [
                RuntimeABIParameter(name: "obj", type: .nullableOpaquePointer),
            ],
            returnType: .void,
            section: "Println"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_println_any",
            parameters: [
                RuntimeABIParameter(name: "obj", type: .nullableOpaquePointer),
            ],
            returnType: .void,
            section: "Println"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_println_bool",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
            ],
            returnType: .void,
            section: "Println"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_println_newline",
            parameters: [],
            returnType: .void,
            section: "Println"
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
    ]

    public static let systemFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_system_exitProcess",
            parameters: [
                RuntimeABIParameter(name: "status", type: .intptr),
            ],
            returnType: .intptr,
            section: "System"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_system_currentTimeMillis",
            parameters: [],
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
            name: "kk_kxmini_run_blocking",
            parameters: [
                RuntimeABIParameter(name: "entryPointRaw", type: .intptr),
                RuntimeABIParameter(name: "functionID", type: .intptr),
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
        // Channel (P5-134)
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
            name: "kk_coroutine_scope_run",
            parameters: [
                RuntimeABIParameter(name: "entryPointRaw", type: .intptr),
                RuntimeABIParameter(name: "functionID", type: .intptr),
            ],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_coroutine_scope_run_with_cont",
            parameters: [
                RuntimeABIParameter(name: "entryPointRaw", type: .intptr),
                RuntimeABIParameter(name: "continuation", type: .intptr),
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
            name: "kk_coroutine_cancel",
            parameters: [
                RuntimeABIParameter(name: "continuation", type: .intptr),
            ],
            returnType: .void,
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
            name: "kk_range_last",
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
            name: "kk_range_toList",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
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
            name: "kk_range_reversed",
            parameters: [
                RuntimeABIParameter(name: "rangeRaw", type: .intptr),
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
            name: "kk_int_toString_radix",
            parameters: [
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "radix", type: .intptr),
            ],
            returnType: .opaquePointer,
            section: "Bitwise"
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
    ]

    public static let allFunctions: [RuntimeABIFunctionSpec] =
        memoryFunctions
            + exceptionFunctions
            + stringFunctions
            + printlnFunctions
            + ioFunctions
            + systemFunctions
            + gcFunctions
            + coroutineFunctions
            + boxingFunctions
            + arrayFunctions
            + operatorFunctions
            + primitiveNumericConversionFunctions
            + rangeFunctions
            + kPropertyStubFunctions + delegateFunctions
            + bitwiseFunctions
            + mathFunctions
            + randomFunctions
            + collectionFunctions
            + sequenceFunctions
            + regexFunctions
            + comparatorFunctions

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
