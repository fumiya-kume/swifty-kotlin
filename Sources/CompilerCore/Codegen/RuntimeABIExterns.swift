// swiftlint:disable file_length
import Foundation

// swiftlint:disable type_body_length
/// Canonical C ABI extern declarations for the KSwiftK runtime.
///
/// This file defines the expected C signatures of all runtime functions
/// that the compiler backend emits calls to. It serves as the single
/// source of truth on the compiler side, and must be kept in sync with
/// `RuntimeABISpec` in the Runtime module.
///
/// The build-time ABI reconciliation tests (in RuntimeTests) verify that
/// these declarations match the Runtime module's `RuntimeABISpec`.
public enum RuntimeABIExterns {
    public static let specVersion = "J26"

    /// A single extern function declaration for the C preamble.
    public struct ExternDecl: Equatable, Sendable {
        public let name: String
        public let parameterTypes: [String]
        public let returnType: String

        public init(name: String, parameterTypes: [String], returnType: String) {
            self.name = name
            self.parameterTypes = parameterTypes
            self.returnType = returnType
        }

        /// Generates the C extern declaration string.
        public var cExternDeclaration: String {
            let params: String = if parameterTypes.isEmpty {
                "void"
            } else {
                parameterTypes.joined(separator: ", ")
            }
            return "extern \(returnType) \(name)(\(params));"
        }
    }

    // MARK: - Memory

    public static let kk_alloc = ExternDecl(
        name: "kk_alloc",
        parameterTypes: ["uint32_t", "const KTypeInfo *"],
        returnType: "void *"
    )

    public static let kk_gc_collect = ExternDecl(
        name: "kk_gc_collect",
        parameterTypes: [],
        returnType: "void"
    )

    public static let kk_write_barrier = ExternDecl(
        name: "kk_write_barrier",
        parameterTypes: ["void *", "void **"],
        returnType: "void"
    )

    // MARK: - Exception

    public static let kk_throwable_new = ExternDecl(
        name: "kk_throwable_new",
        parameterTypes: ["void * _Nullable"],
        returnType: "void *"
    )

    public static let kk_throwable_new_with_cause = ExternDecl(
        name: "kk_throwable_new_with_cause",
        parameterTypes: ["void * _Nullable", "intptr_t"],
        returnType: "void *"
    )

    public static let kk_throwable_is_cancellation = ExternDecl(
        name: "kk_throwable_is_cancellation",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_panic = ExternDecl(
        name: "kk_panic",
        parameterTypes: ["const char *"],
        returnType: "_Noreturn void"
    )

    public static let kk_abort_unreachable = ExternDecl(
        name: "kk_abort_unreachable",
        parameterTypes: ["intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    public static let kk_require = ExternDecl(
        name: "kk_require",
        parameterTypes: ["intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    public static let kk_check = ExternDecl(
        name: "kk_check",
        parameterTypes: ["intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    public static let kk_require_lazy = ExternDecl(
        name: "kk_require_lazy",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    public static let kk_check_lazy = ExternDecl(
        name: "kk_check_lazy",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    // MARK: - Assert (STDLIB-258)

    public static let kk_precondition_assert = ExternDecl(
        name: "kk_precondition_assert",
        parameterTypes: ["intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    public static let kk_precondition_assert_lazy = ExternDecl(
        name: "kk_precondition_assert_lazy",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    // MARK: - Test Framework (STDLIB-TEST-157)

    public static let kk_test_assertEquals = ExternDecl(
        name: "kk_test_assertEquals",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    public static let kk_test_assertEquals_message = ExternDecl(
        name: "kk_test_assertEquals_message",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    public static let kk_test_assertTrue = ExternDecl(
        name: "kk_test_assertTrue",
        parameterTypes: ["intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    public static let kk_test_assertTrue_message = ExternDecl(
        name: "kk_test_assertTrue_message",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    public static let kk_test_assertNull = ExternDecl(
        name: "kk_test_assertNull",
        parameterTypes: ["intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    public static let kk_test_assertNull_message = ExternDecl(
        name: "kk_test_assertNull_message",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    public static let kk_error = ExternDecl(
        name: "kk_error",
        parameterTypes: ["intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    public static let kk_todo = ExternDecl(
        name: "kk_todo",
        parameterTypes: ["intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    public static let kk_todo_noarg = ExternDecl(
        name: "kk_todo_noarg",
        parameterTypes: ["intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    public static let kk_dispatch_error = ExternDecl(
        name: "kk_dispatch_error",
        parameterTypes: [],
        returnType: "intptr_t"
    )

    // MARK: - Synchronized (STDLIB-325)

    public static let kk_synchronized = ExternDecl(
        name: "kk_synchronized",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    // MARK: - Duration / measureTime / measureTimedValue (STDLIB-230/231/660)

    public static let kk_measureTime = ExternDecl(
        name: "kk_measureTime",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    public static let kk_measureTimedValue = ExternDecl(
        name: "kk_measureTimedValue",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    // MARK: - TimedValue (STDLIB-660)

    public static let kk_timedvalue_new = ExternDecl(
        name: "kk_timedvalue_new",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_timedvalue_value = ExternDecl(
        name: "kk_timedvalue_value",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_timedvalue_duration = ExternDecl(
        name: "kk_timedvalue_duration",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_timedvalue_toString = ExternDecl(
        name: "kk_timedvalue_toString",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_duration_inWholeMilliseconds = ExternDecl(
        name: "kk_duration_inWholeMilliseconds",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_duration_inWholeSeconds = ExternDecl(
        name: "kk_duration_inWholeSeconds",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_duration_inWholeMinutes = ExternDecl(
        name: "kk_duration_inWholeMinutes",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_duration_toString = ExternDecl(
        name: "kk_duration_toString",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_duration_from_seconds = ExternDecl(
        name: "kk_duration_from_seconds",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_duration_from_milliseconds = ExternDecl(
        name: "kk_duration_from_milliseconds",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_duration_from_microseconds = ExternDecl(
        name: "kk_duration_from_microseconds",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_duration_from_nanoseconds = ExternDecl(
        name: "kk_duration_from_nanoseconds",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_duration_from_minutes = ExternDecl(
        name: "kk_duration_from_minutes",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_duration_from_hours = ExternDecl(
        name: "kk_duration_from_hours",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_duration_from_days = ExternDecl(
        name: "kk_duration_from_days",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_duration_from_seconds_long = ExternDecl(
        name: "kk_duration_from_seconds_long",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_duration_from_milliseconds_long = ExternDecl(
        name: "kk_duration_from_milliseconds_long",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_duration_from_microseconds_long = ExternDecl(
        name: "kk_duration_from_microseconds_long",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_duration_from_nanoseconds_long = ExternDecl(
        name: "kk_duration_from_nanoseconds_long",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_duration_from_minutes_long = ExternDecl(
        name: "kk_duration_from_minutes_long",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_duration_from_hours_long = ExternDecl(
        name: "kk_duration_from_hours_long",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_duration_from_days_long = ExternDecl(
        name: "kk_duration_from_days_long",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_duration_inWholeMicroseconds = ExternDecl(
        name: "kk_duration_inWholeMicroseconds",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_duration_inWholeNanoseconds = ExternDecl(
        name: "kk_duration_inWholeNanoseconds",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_duration_inWholeHours = ExternDecl(
        name: "kk_duration_inWholeHours",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    // MARK: - Duration advanced operations (STDLIB-TIME-082)

    public static let kk_duration_absoluteValue = ExternDecl(
        name: "kk_duration_absoluteValue",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_duration_isNegative = ExternDecl(
        name: "kk_duration_isNegative",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_duration_isPositive = ExternDecl(
        name: "kk_duration_isPositive",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_duration_isInfinite = ExternDecl(
        name: "kk_duration_isInfinite",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_duration_isFinite = ExternDecl(
        name: "kk_duration_isFinite",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_duration_plus = ExternDecl(
        name: "kk_duration_plus",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_duration_minus = ExternDecl(
        name: "kk_duration_minus",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_duration_times_int = ExternDecl(
        name: "kk_duration_times_int",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_duration_div_int = ExternDecl(
        name: "kk_duration_div_int",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_duration_unary_minus = ExternDecl(
        name: "kk_duration_unary_minus",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_duration_compareTo = ExternDecl(
        name: "kk_duration_compareTo",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_throwable_message = ExternDecl(
        name: "kk_throwable_message",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_throwable_cause = ExternDecl(
        name: "kk_throwable_cause",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_throwable_stackTraceToString = ExternDecl(
        name: "kk_throwable_stackTraceToString",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    // MARK: - Test Framework (STDLIB-TEST-157)

    public static let kk_test_assertEquals = ExternDecl(
        name: "kk_test_assertEquals",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    public static let kk_test_assertEquals_message = ExternDecl(
        name: "kk_test_assertEquals_message",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    public static let kk_test_assertTrue = ExternDecl(
        name: "kk_test_assertTrue",
        parameterTypes: ["intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    public static let kk_test_assertTrue_message = ExternDecl(
        name: "kk_test_assertTrue_message",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    public static let kk_test_assertNull = ExternDecl(
        name: "kk_test_assertNull",
        parameterTypes: ["intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    public static let kk_test_assertNull_message = ExternDecl(
        name: "kk_test_assertNull_message",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    // MARK: - String

    public static let kk_string_from_utf8 = ExternDecl(
        name: "kk_string_from_utf8",
        parameterTypes: ["const uint8_t *", "int32_t"],
        returnType: "void *"
    )

    public static let kk_string_concat = ExternDecl(
        name: "kk_string_concat",
        parameterTypes: ["void * _Nullable", "void * _Nullable"],
        returnType: "void *"
    )

    public static let kk_string_compareTo = ExternDecl(
        name: "kk_string_compareTo",
        parameterTypes: ["void * _Nullable", "void * _Nullable"],
        returnType: "intptr_t"
    )

    public static let kk_compare_any = ExternDecl(
        name: "kk_compare_any",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_string_length = ExternDecl(
        name: "kk_string_length",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_string_trim = ExternDecl(
        name: "kk_string_trim",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_string_lowercase = ExternDecl(
        name: "kk_string_lowercase",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_string_uppercase = ExternDecl(
        name: "kk_string_uppercase",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_locale_new = ExternDecl(
        name: "kk_locale_new",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_string_lowercase_locale = ExternDecl(
        name: "kk_string_lowercase_locale",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_normalization_form_nfc = ExternDecl(
        name: "kk_normalization_form_nfc",
        parameterTypes: [],
        returnType: "intptr_t"
    )

    public static let kk_normalization_form_nfd = ExternDecl(
        name: "kk_normalization_form_nfd",
        parameterTypes: [],
        returnType: "intptr_t"
    )

    public static let kk_normalization_form_nfkc = ExternDecl(
        name: "kk_normalization_form_nfkc",
        parameterTypes: [],
        returnType: "intptr_t"
    )

    public static let kk_normalization_form_nfkd = ExternDecl(
        name: "kk_normalization_form_nfkd",
        parameterTypes: [],
        returnType: "intptr_t"
    )

    public static let kk_string_normalize = ExternDecl(
        name: "kk_string_normalize",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_string_isNormalized = ExternDecl(
        name: "kk_string_isNormalized",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_string_uppercase_locale = ExternDecl(
        name: "kk_string_uppercase_locale",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_string_compareTo_locale = ExternDecl(
        name: "kk_string_compareTo_locale",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )


    public static let kk_string_trimIndent = ExternDecl(
        name: "kk_string_trimIndent",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_string_trimMargin_default = ExternDecl(
        name: "kk_string_trimMargin_default",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_string_trimMargin = ExternDecl(
        name: "kk_string_trimMargin",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_string_padStart_default = ExternDecl(
        name: "kk_string_padStart_default",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_string_padEnd_default = ExternDecl(
        name: "kk_string_padEnd_default",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_string_padStart = ExternDecl(
        name: "kk_string_padStart",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_string_padEnd = ExternDecl(
        name: "kk_string_padEnd",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_string_repeat = ExternDecl(
        name: "kk_string_repeat",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    public static let kk_string_reversed = ExternDecl(
        name: "kk_string_reversed",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_string_toList = ExternDecl(
        name: "kk_string_toList",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_string_toCharArray = ExternDecl(
        name: "kk_string_toCharArray",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    // STDLIB-640: CharArray.concatToString()
    public static let kk_chararray_concatToString = ExternDecl(
        name: "kk_chararray_concatToString",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    // STDLIB-317: String.asIterable() — lazy Iterable<Char>
    public static let kk_string_asIterable = ExternDecl(
        name: "kk_string_asIterable",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_string_iterable_toList = ExternDecl(
        name: "kk_string_iterable_toList",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_string_iterable_iterator = ExternDecl(
        name: "kk_string_iterable_iterator",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_string_take = ExternDecl(
        name: "kk_string_take",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_string_drop = ExternDecl(
        name: "kk_string_drop",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_string_takeLast = ExternDecl(
        name: "kk_string_takeLast",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_string_dropLast = ExternDecl(
        name: "kk_string_dropLast",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_string_removePrefix = ExternDecl(
        name: "kk_string_removePrefix",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_string_removeSuffix = ExternDecl(
        name: "kk_string_removeSuffix",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_string_removeSurrounding = ExternDecl(
        name: "kk_string_removeSurrounding",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_string_removeSurrounding_pair = ExternDecl(
        name: "kk_string_removeSurrounding_pair",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_string_prependIndent_default = ExternDecl(
        name: "kk_string_prependIndent_default",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_string_prependIndent = ExternDecl(
        name: "kk_string_prependIndent",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_string_replaceIndent_default = ExternDecl(
        name: "kk_string_replaceIndent_default",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_string_replaceIndent = ExternDecl(
        name: "kk_string_replaceIndent",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_string_equalsIgnoreCase = ExternDecl(
        name: "kk_string_equalsIgnoreCase",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_string_first = ExternDecl(
        name: "kk_string_first",
        parameterTypes: ["intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    public static let kk_string_last = ExternDecl(
        name: "kk_string_last",
        parameterTypes: ["intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    public static let kk_string_single = ExternDecl(
        name: "kk_string_single",
        parameterTypes: ["intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    public static let kk_string_firstOrNull = ExternDecl(
        name: "kk_string_firstOrNull",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_string_lastOrNull = ExternDecl(
        name: "kk_string_lastOrNull",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_string_singleOrNull = ExternDecl(
        name: "kk_string_singleOrNull",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_string_iterator = ExternDecl(
        name: "kk_string_iterator",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_string_iterator_hasNext = ExternDecl(
        name: "kk_string_iterator_hasNext",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_string_iterator_next = ExternDecl(
        name: "kk_string_iterator_next",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_string_filter = ExternDecl(
        name: "kk_string_filter",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    public static let kk_string_map = ExternDecl(
        name: "kk_string_map",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    public static let kk_string_count = ExternDecl(
        name: "kk_string_count",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    public static let kk_string_any = ExternDecl(
        name: "kk_string_any",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    public static let kk_string_all = ExternDecl(
        name: "kk_string_all",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    public static let kk_string_none = ExternDecl(
        name: "kk_string_none",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    public static let kk_string_replaceFirstChar = ExternDecl(
        name: "kk_string_replaceFirstChar",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    public static let kk_string_isEmpty = ExternDecl(
        name: "kk_string_isEmpty",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_string_isNotEmpty = ExternDecl(
        name: "kk_string_isNotEmpty",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_string_isBlank = ExternDecl(
        name: "kk_string_isBlank",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_string_isNotBlank = ExternDecl(
        name: "kk_string_isNotBlank",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_string_substringBefore = ExternDecl(
        name: "kk_string_substringBefore",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_string_substringAfter = ExternDecl(
        name: "kk_string_substringAfter",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_string_substringBeforeLast = ExternDecl(
        name: "kk_string_substringBeforeLast",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_string_substringAfterLast = ExternDecl(
        name: "kk_string_substringAfterLast",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_string_format = ExternDecl(
        name: "kk_string_format",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_string_toBigDecimal = ExternDecl(
        name: "kk_string_toBigDecimal",
        parameterTypes: ["intptr_t", "intptr_t*"],
        returnType: "intptr_t"
    )

    public static let kk_bignum_toString = ExternDecl(
        name: "kk_bignum_toString",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )
    public static let kk_string_isNullOrEmpty = ExternDecl(
        name: "kk_string_isNullOrEmpty",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_string_isNullOrBlank = ExternDecl(
        name: "kk_string_isNullOrBlank",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    /// STDLIB-534: String?.orEmpty()
    public static let kk_string_orEmpty = ExternDecl(
        name: "kk_string_orEmpty",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_string_split = ExternDecl(
        name: "kk_string_split",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_string_replace = ExternDecl(
        name: "kk_string_replace",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_string_replaceFirst = ExternDecl(
        name: "kk_string_replaceFirst",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_string_replaceRange = ExternDecl(
        name: "kk_string_replaceRange",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    public static let kk_string_substring = ExternDecl(
        name: "kk_string_substring",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    public static let kk_string_startsWith = ExternDecl(
        name: "kk_string_startsWith",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_string_endsWith = ExternDecl(
        name: "kk_string_endsWith",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_string_contains_str = ExternDecl(
        name: "kk_string_contains_str",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_string_toInt = ExternDecl(
        name: "kk_string_toInt",
        parameterTypes: ["intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    public static let kk_string_toInt_radix = ExternDecl(
        name: "kk_string_toInt_radix",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    public static let kk_string_toIntOrNull = ExternDecl(
        name: "kk_string_toIntOrNull",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_string_toDouble = ExternDecl(
        name: "kk_string_toDouble",
        parameterTypes: ["intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    public static let kk_string_toDoubleOrNull = ExternDecl(
        name: "kk_string_toDoubleOrNull",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_string_toLong = ExternDecl(
        name: "kk_string_toLong",
        parameterTypes: ["intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    public static let kk_string_toLongOrNull = ExternDecl(
        name: "kk_string_toLongOrNull",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_string_toFloat = ExternDecl(
        name: "kk_string_toFloat",
        parameterTypes: ["intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    public static let kk_string_toFloatOrNull = ExternDecl(
        name: "kk_string_toFloatOrNull",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_string_indexOf = ExternDecl(
        name: "kk_string_indexOf",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_string_lastIndexOf = ExternDecl(
        name: "kk_string_lastIndexOf",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_string_indexOf_from = ExternDecl(
        name: "kk_string_indexOf_from",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_string_indexOfFirst = ExternDecl(
        name: "kk_string_indexOfFirst",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    public static let kk_string_indexOfLast = ExternDecl(
        name: "kk_string_indexOfLast",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    /// STDLIB-140
    public static let kk_string_get = ExternDecl(
        name: "kk_string_get",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    /// STDLIB-141
    public static let kk_string_compareTo_member = ExternDecl(
        name: "kk_string_compareTo_member",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_string_compareToIgnoreCase = ExternDecl(
        name: "kk_string_compareToIgnoreCase",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_string_equals = ExternDecl(
        name: "kk_string_equals",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_enum_valueOf_throw = ExternDecl(
        name: "kk_enum_valueOf_throw",
        parameterTypes: ["intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    /// STDLIB-171: enumValues<T>() / T.values() — creates Array of enum instances
    public static let kk_enum_make_values_array = ExternDecl(
        name: "kk_enum_make_values_array",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    /// ENUM-002: T.entries — creates EnumEntries (List) of enum instances
    public static let kk_enum_make_entries_list = ExternDecl(
        name: "kk_enum_make_entries_list",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    /// STDLIB-142
    public static let kk_string_toBoolean = ExternDecl(
        name: "kk_string_toBoolean",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_string_toBooleanStrict = ExternDecl(
        name: "kk_string_toBooleanStrict",
        parameterTypes: ["intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    /// STDLIB-143
    public static let kk_string_lines = ExternDecl(
        name: "kk_string_lines",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    /// STDLIB-666
    public static let kk_string_lineSequence = ExternDecl(
        name: "kk_string_lineSequence",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    /// STDLIB-144
    public static let kk_string_trimStart = ExternDecl(
        name: "kk_string_trimStart",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_string_trimEnd = ExternDecl(
        name: "kk_string_trimEnd",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    /// STDLIB-145
    public static let kk_string_toByteArray = ExternDecl(
        name: "kk_string_toByteArray",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    /// STDLIB-581: String.toByteArray(charset: Charset)
    public static let kk_string_toByteArray_charset = ExternDecl(
        name: "kk_string_toByteArray_charset",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    /// STDLIB-581: Charsets.* charset tag factories
    public static let kk_charset_utf_8 = ExternDecl(
        name: "kk_charset_utf_8", parameterTypes: [], returnType: "intptr_t"
    )
    public static let kk_charset_iso_8859_1 = ExternDecl(
        name: "kk_charset_iso_8859_1", parameterTypes: [], returnType: "intptr_t"
    )
    public static let kk_charset_us_ascii = ExternDecl(
        name: "kk_charset_us_ascii", parameterTypes: [], returnType: "intptr_t"
    )
    public static let kk_charset_utf_16 = ExternDecl(
        name: "kk_charset_utf_16", parameterTypes: [], returnType: "intptr_t"
    )
    public static let kk_charset_utf_16be = ExternDecl(
        name: "kk_charset_utf_16be", parameterTypes: [], returnType: "intptr_t"
    )
    public static let kk_charset_utf_16le = ExternDecl(
        name: "kk_charset_utf_16le", parameterTypes: [], returnType: "intptr_t"
    )
    public static let kk_charset_utf_32 = ExternDecl(
        name: "kk_charset_utf_32", parameterTypes: [], returnType: "intptr_t"
    )
    public static let kk_charset_utf_32be = ExternDecl(
        name: "kk_charset_utf_32be", parameterTypes: [], returnType: "intptr_t"
    )
    public static let kk_charset_utf_32le = ExternDecl(
        name: "kk_charset_utf_32le", parameterTypes: [], returnType: "intptr_t"
    )

    /// STDLIB-573: String.encodeToByteArray
    public static let kk_string_encodeToByteArray = ExternDecl(
        name: "kk_string_encodeToByteArray",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    /// STDLIB-573: String.encodeToByteArray(startIndex, endIndex)
    public static let kk_string_encodeToByteArray_range = ExternDecl(
        name: "kk_string_encodeToByteArray_range",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    /// STDLIB-573: String.encodeToByteArray(charset)
    public static let kk_string_encodeToByteArray_charset = ExternDecl(
        name: "kk_string_encodeToByteArray_charset",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    /// STDLIB-574: ByteArray.decodeToString
    public static let kk_bytearray_decodeToString = ExternDecl(
        name: "kk_bytearray_decodeToString",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    /// STDLIB-574: ByteArray.decodeToString(charset)
    public static let kk_bytearray_decodeToString_charset = ExternDecl(
        name: "kk_bytearray_decodeToString_charset",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    /// STDLIB-316: String.chunked / String.windowed
    public static let kk_string_chunked = ExternDecl(
        name: "kk_string_chunked",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_string_windowed_default = ExternDecl(
        name: "kk_string_windowed_default",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_string_windowed = ExternDecl(
        name: "kk_string_windowed",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_string_windowed_partial = ExternDecl(
        name: "kk_string_windowed_partial",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    // STDLIB-318: String.commonPrefixWith / commonSuffixWith
    public static let kk_string_commonPrefixWith = ExternDecl(
        name: "kk_string_commonPrefixWith",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_string_commonSuffixWith = ExternDecl(
        name: "kk_string_commonSuffixWith",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    // STDLIB-575/576: commonPrefixWith / commonSuffixWith (ignoreCase overloads)
    public static let kk_string_commonPrefixWith_ignoreCase = ExternDecl(
        name: "kk_string_commonPrefixWith_ignoreCase",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_string_commonSuffixWith_ignoreCase = ExternDecl(
        name: "kk_string_commonSuffixWith_ignoreCase",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    // STDLIB-316: String.zipWithNext()
    public static let kk_string_zipWithNext = ExternDecl(
        name: "kk_string_zipWithNext",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    // STDLIB-317: String.asSequence / asIterable
    public static let kk_string_asSequence = ExternDecl(
        name: "kk_string_asSequence",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_char_isDigit = ExternDecl(
        name: "kk_char_isDigit",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_char_isLetter = ExternDecl(
        name: "kk_char_isLetter",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_char_isLetterOrDigit = ExternDecl(
        name: "kk_char_isLetterOrDigit",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_char_isUpperCase = ExternDecl(
        name: "kk_char_isUpperCase",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_char_isLowerCase = ExternDecl(
        name: "kk_char_isLowerCase",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_char_isWhitespace = ExternDecl(
        name: "kk_char_isWhitespace",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_char_uppercase = ExternDecl(
        name: "kk_char_uppercase",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_char_lowercase = ExternDecl(
        name: "kk_char_lowercase",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_char_titlecase = ExternDecl(
        name: "kk_char_titlecase",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_char_digitToInt = ExternDecl(
        name: "kk_char_digitToInt",
        parameterTypes: ["intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    public static let kk_char_digitToIntOrNull = ExternDecl(
        name: "kk_char_digitToIntOrNull",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    // MARK: - Print / Println

    public static let kk_print_any = ExternDecl(
        name: "kk_print_any",
        parameterTypes: ["void * _Nullable"],
        returnType: "void"
    )

    public static let kk_println_any = ExternDecl(
        name: "kk_println_any",
        parameterTypes: ["void * _Nullable"],
        returnType: "void"
    )

    public static let kk_println_bool = ExternDecl(
        name: "kk_println_bool",
        parameterTypes: ["intptr_t"],
        returnType: "void"
    )

    public static let kk_println_ulong = ExternDecl(
        name: "kk_println_ulong",
        parameterTypes: ["intptr_t"],
        returnType: "void"
    )

    public static let kk_print_noarg = ExternDecl(
        name: "kk_print_noarg",
        parameterTypes: [],
        returnType: "void"
    )

    public static let kk_println_newline = ExternDecl(
        name: "kk_println_newline",
        parameterTypes: [],
        returnType: "void"
    )

    // MARK: - IO

    public static let kk_readline = ExternDecl(
        name: "kk_readline",
        parameterTypes: [],
        returnType: "intptr_t"
    )

    public static let kk_readln = ExternDecl(
        name: "kk_readln",
        parameterTypes: ["intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    public static let kk_readlnOrNull = ExternDecl(
        name: "kk_readlnOrNull",
        parameterTypes: [],
        returnType: "intptr_t"
    )

    // MARK: - System

    public static let kk_system_exitProcess = ExternDecl(
        name: "kk_system_exitProcess",
        parameterTypes: ["intptr_t"],
        returnType: "_Noreturn void"
    )

    public static let kk_system_currentTimeMillis = ExternDecl(
        name: "kk_system_currentTimeMillis",
        parameterTypes: [],
        returnType: "intptr_t"
    )

    public static let kk_system_nanoTime = ExternDecl(
        name: "kk_system_nanoTime",
        parameterTypes: [],
        returnType: "intptr_t"
    )

    public static let kk_system_measureTimeMillis = ExternDecl(
        name: "kk_system_measureTimeMillis",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    public static let kk_system_measureNanoTime = ExternDecl(
        name: "kk_system_measureNanoTime",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    // MARK: - GC

    public static let kk_register_global_root = ExternDecl(
        name: "kk_register_global_root",
        parameterTypes: ["void ** _Nullable"],
        returnType: "void"
    )

    public static let kk_unregister_global_root = ExternDecl(
        name: "kk_unregister_global_root",
        parameterTypes: ["void ** _Nullable"],
        returnType: "void"
    )

    public static let kk_register_frame_map = ExternDecl(
        name: "kk_register_frame_map",
        parameterTypes: ["uint32_t", "const void * _Nullable"],
        returnType: "void"
    )

    public static let kk_push_frame = ExternDecl(
        name: "kk_push_frame",
        parameterTypes: ["uint32_t", "void * _Nullable"],
        returnType: "void"
    )

    public static let kk_pop_frame = ExternDecl(
        name: "kk_pop_frame",
        parameterTypes: [],
        returnType: "void"
    )

    public static let kk_register_coroutine_root = ExternDecl(
        name: "kk_register_coroutine_root",
        parameterTypes: ["void * _Nullable"],
        returnType: "void"
    )

    public static let kk_unregister_coroutine_root = ExternDecl(
        name: "kk_unregister_coroutine_root",
        parameterTypes: ["void * _Nullable"],
        returnType: "void"
    )

    public static let kk_runtime_heap_object_count = ExternDecl(
        name: "kk_runtime_heap_object_count",
        parameterTypes: [],
        returnType: "uint32_t"
    )

    public static let kk_runtime_force_reset = ExternDecl(
        name: "kk_runtime_force_reset",
        parameterTypes: [],
        returnType: "void"
    )

    // MARK: - Coroutine

    public static let kk_coroutine_suspended = ExternDecl(
        name: "kk_coroutine_suspended",
        parameterTypes: [],
        returnType: "void *"
    )

    public static let kk_coroutine_continuation_new = ExternDecl(
        name: "kk_coroutine_continuation_new",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_coroutine_state_enter = ExternDecl(
        name: "kk_coroutine_state_enter",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_coroutine_state_set_label = ExternDecl(
        name: "kk_coroutine_state_set_label",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_coroutine_state_exit = ExternDecl(
        name: "kk_coroutine_state_exit",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_coroutine_state_set_spill = ExternDecl(
        name: "kk_coroutine_state_set_spill",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_coroutine_state_get_spill = ExternDecl(
        name: "kk_coroutine_state_get_spill",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_coroutine_state_set_completion = ExternDecl(
        name: "kk_coroutine_state_set_completion",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_coroutine_state_get_completion = ExternDecl(
        name: "kk_coroutine_state_get_completion",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_kxmini_run_blocking = ExternDecl(
        name: "kk_kxmini_run_blocking",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_kxmini_launch = ExternDecl(
        name: "kk_kxmini_launch",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_kxmini_async = ExternDecl(
        name: "kk_kxmini_async",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_kxmini_async_await = ExternDecl(
        name: "kk_kxmini_async_await",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_kxmini_delay = ExternDecl(
        name: "kk_kxmini_delay",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_coroutine_launcher_arg_set = ExternDecl(
        name: "kk_coroutine_launcher_arg_set",
        parameterTypes: ["intptr_t", "int64_t", "int64_t"],
        returnType: "int64_t"
    )

    public static let kk_coroutine_launcher_arg_get = ExternDecl(
        name: "kk_coroutine_launcher_arg_get",
        parameterTypes: ["intptr_t", "int64_t"],
        returnType: "int64_t"
    )

    public static let kk_kxmini_run_blocking_with_cont = ExternDecl(
        name: "kk_kxmini_run_blocking_with_cont",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_kxmini_launch_with_cont = ExternDecl(
        name: "kk_kxmini_launch_with_cont",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_kxmini_async_with_cont = ExternDecl(
        name: "kk_kxmini_async_with_cont",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    // CORO-071: async/await exception handling, cancellation, and dispatcher support

    /// Exception-aware await: writes thrown exception to outThrown, returns 0 on exception.
    public static let kk_kxmini_async_await_throwing = ExternDecl(
        name: "kk_kxmini_async_await_throwing",
        parameterTypes: ["intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    /// Cancel an async task (Deferred.cancel()).
    public static let kk_async_task_cancel = ExternDecl(
        name: "kk_async_task_cancel",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    /// Async builder with dispatcher specification — async(dispatcher) { body }.
    public static let kk_kxmini_async_with_dispatcher = ExternDecl(
        name: "kk_kxmini_async_with_dispatcher",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    // Flow (P5-88)

    public static let kk_flow_create = ExternDecl(
        name: "kk_flow_create",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_flow_emit = ExternDecl(
        name: "kk_flow_emit",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_flow_collect = ExternDecl(
        name: "kk_flow_collect",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_flow_retain = ExternDecl(
        name: "kk_flow_retain",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_flow_release = ExternDecl(
        name: "kk_flow_release",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    // Flow terminal operators & flowOf (STDLIB-088)

    public static let kk_flow_of = ExternDecl(
        name: "kk_flow_of",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_flow_to_list = ExternDecl(
        name: "kk_flow_to_list",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_flow_first = ExternDecl(
        name: "kk_flow_first",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_flow_count = ExternDecl(
        name: "kk_flow_count",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_flow_fold = ExternDecl(
        name: "kk_flow_fold",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_flow_reduce = ExternDecl(
        name: "kk_flow_reduce",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    // Dispatchers / withContext (P5-133)

    public static let kk_dispatcher_default = ExternDecl(
        name: "kk_dispatcher_default",
        parameterTypes: [],
        returnType: "intptr_t"
    )

    public static let kk_dispatcher_io = ExternDecl(
        name: "kk_dispatcher_io",
        parameterTypes: [],
        returnType: "intptr_t"
    )

    public static let kk_dispatcher_main = ExternDecl(
        name: "kk_dispatcher_main",
        parameterTypes: [],
        returnType: "intptr_t"
    )

    public static let kk_with_context = ExternDecl(
        name: "kk_with_context",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    // CoroutineContext elements (STDLIB-CORO-077)

    public static let kk_coroutine_name_create = ExternDecl(
        name: "kk_coroutine_name_create",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_coroutine_name_get = ExternDecl(
        name: "kk_coroutine_name_get",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_exception_handler_create = ExternDecl(
        name: "kk_exception_handler_create",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_exception_handler_invoke = ExternDecl(
        name: "kk_exception_handler_invoke",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t"],
        returnType: "void"
    )

    public static let kk_context_plus = ExternDecl(
        name: "kk_context_plus",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_context_get_dispatcher = ExternDecl(
        name: "kk_context_get_dispatcher",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_context_get_name = ExternDecl(
        name: "kk_context_get_name",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_context_get_exception_handler = ExternDecl(
        name: "kk_context_get_exception_handler",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_context_release = ExternDecl(
        name: "kk_context_release",
        parameterTypes: ["intptr_t"],
        returnType: "void"
    )

    public static let kk_with_context_full = ExternDecl(
        name: "kk_with_context_full",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    // Channel (CORO-001)

    public static let kk_channel_create = ExternDecl(
        name: "kk_channel_create",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_channel_send = ExternDecl(
        name: "kk_channel_send",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_channel_receive = ExternDecl(
        name: "kk_channel_receive",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_channel_close = ExternDecl(
        name: "kk_channel_close",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_channel_is_closed_token = ExternDecl(
        name: "kk_channel_is_closed_token",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    // Deferred / awaitAll (P5-135)

    public static let kk_await_all = ExternDecl(
        name: "kk_await_all",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    // Structured Concurrency (P5-89)

    public static let kk_coroutine_scope_new = ExternDecl(
        name: "kk_coroutine_scope_new",
        parameterTypes: [],
        returnType: "intptr_t"
    )

    public static let kk_coroutine_scope_cancel = ExternDecl(
        name: "kk_coroutine_scope_cancel",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_coroutine_scope_wait = ExternDecl(
        name: "kk_coroutine_scope_wait",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_coroutine_scope_register_child = ExternDecl(
        name: "kk_coroutine_scope_register_child",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_job_join = ExternDecl(
        name: "kk_job_join",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_coroutine_scope_run = ExternDecl(
        name: "kk_coroutine_scope_run",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_coroutine_scope_run_with_cont = ExternDecl(
        name: "kk_coroutine_scope_run_with_cont",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_supervisor_scope_run = ExternDecl(
        name: "kk_supervisor_scope_run",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_supervisor_scope_run_with_cont = ExternDecl(
        name: "kk_supervisor_scope_run_with_cont",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    // MARK: - Cancellation (CORO-002)

    public static let kk_coroutine_check_cancellation = ExternDecl(
        name: "kk_coroutine_check_cancellation",
        parameterTypes: ["intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    public static let kk_is_cancellation_exception = ExternDecl(
        name: "kk_is_cancellation_exception",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_job_cancel = ExternDecl(
        name: "kk_job_cancel",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_coroutine_cancel = ExternDecl(
        name: "kk_coroutine_cancel",
        parameterTypes: ["intptr_t"],
        returnType: "void"
    )

    // MARK: - Mutex / Semaphore (sync primitives)

    public static let kk_mutex_create = ExternDecl(
        name: "kk_mutex_create",
        parameterTypes: [],
        returnType: "intptr_t"
    )

    public static let kk_mutex_lock = ExternDecl(
        name: "kk_mutex_lock",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_mutex_unlock = ExternDecl(
        name: "kk_mutex_unlock",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_mutex_tryLock = ExternDecl(
        name: "kk_mutex_tryLock",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_mutex_isLocked = ExternDecl(
        name: "kk_mutex_isLocked",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_semaphore_create = ExternDecl(
        name: "kk_semaphore_create",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_semaphore_acquire = ExternDecl(
        name: "kk_semaphore_acquire",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_semaphore_release = ExternDecl(
        name: "kk_semaphore_release",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_semaphore_tryAcquire = ExternDecl(
        name: "kk_semaphore_tryAcquire",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_semaphore_availablePermits = ExternDecl(
        name: "kk_semaphore_availablePermits",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    // MARK: - Boxing

    public static let kk_box_int = ExternDecl(
        name: "kk_box_int",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_box_bool = ExternDecl(
        name: "kk_box_bool",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_lateinit_is_initialized = ExternDecl(
        name: "kk_lateinit_is_initialized",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_lateinit_get_or_throw = ExternDecl(
        name: "kk_lateinit_get_or_throw",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    public static let kk_unbox_int = ExternDecl(
        name: "kk_unbox_int",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_unbox_bool = ExternDecl(
        name: "kk_unbox_bool",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_box_long = ExternDecl(
        name: "kk_box_long",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_box_float = ExternDecl(
        name: "kk_box_float",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_box_double = ExternDecl(
        name: "kk_box_double",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_box_char = ExternDecl(
        name: "kk_box_char",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_unbox_long = ExternDecl(
        name: "kk_unbox_long",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_unbox_float = ExternDecl(
        name: "kk_unbox_float",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_unbox_double = ExternDecl(
        name: "kk_unbox_double",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_unbox_char = ExternDecl(
        name: "kk_unbox_char",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    // MARK: - Array

    public static let kk_array_new = ExternDecl(
        name: "kk_array_new",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_object_new = ExternDecl(
        name: "kk_object_new",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_object_type_id = ExternDecl(
        name: "kk_object_type_id",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_array_get = ExternDecl(
        name: "kk_array_get",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    public static let kk_array_get_inbounds = ExternDecl(
        name: "kk_array_get_inbounds",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_array_set = ExternDecl(
        name: "kk_array_set",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    public static let kk_vararg_spread_concat = ExternDecl(
        name: "kk_vararg_spread_concat",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    // MARK: - TypeCheck Operators

    public static let kk_type_register_super = ExternDecl(
        name: "kk_type_register_super",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_type_register_iface = ExternDecl(
        name: "kk_type_register_iface",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_object_register_itable_method = ExternDecl(
        name: "kk_object_register_itable_method",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_type_token_simple_name = ExternDecl(
        name: "kk_type_token_simple_name",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_type_token_qualified_name = ExternDecl(
        name: "kk_type_token_qualified_name",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_kclass_create = ExternDecl(
        name: "kk_kclass_create",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_kclass_simple_name = ExternDecl(
        name: "kk_kclass_simple_name",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_kclass_qualified_name = ExternDecl(
        name: "kk_kclass_qualified_name",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    // REFL-004: KClass binary metadata registration and accessors

    public static let kk_kclass_register_metadata = ExternDecl(
        name: "kk_kclass_register_metadata",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t", "intptr_t", "intptr_t", "intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_kclass_is_data = ExternDecl(
        name: "kk_kclass_is_data",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_kclass_is_sealed = ExternDecl(
        name: "kk_kclass_is_sealed",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_kclass_is_value = ExternDecl(
        name: "kk_kclass_is_value",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_kclass_is_interface = ExternDecl(
        name: "kk_kclass_is_interface",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_kclass_is_object = ExternDecl(
        name: "kk_kclass_is_object",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_kclass_is_enum = ExternDecl(
        name: "kk_kclass_is_enum",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_kclass_is_abstract = ExternDecl(
        name: "kk_kclass_is_abstract",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_kclass_supertype_name = ExternDecl(
        name: "kk_kclass_supertype_name",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_kclass_members_count = ExternDecl(
        name: "kk_kclass_members_count",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    // REFL-005: KClass.isInstance, members, constructors

    public static let kk_kclass_isInstance = ExternDecl(
        name: "kk_kclass_isInstance",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_kclass_members = ExternDecl(
        name: "kk_kclass_members",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_kclass_constructors = ExternDecl(
        name: "kk_kclass_constructors",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    // REFL-005: KType and typeOf<T>()

    public static let kk_ktype_create = ExternDecl(
        name: "kk_ktype_create",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_ktype_classifier = ExternDecl(
        name: "kk_ktype_classifier",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_ktype_arguments = ExternDecl(
        name: "kk_ktype_arguments",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_ktype_isMarkedNullable = ExternDecl(
        name: "kk_ktype_isMarkedNullable",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_ktypeprojection_create = ExternDecl(
        name: "kk_ktypeprojection_create",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_ktypeprojection_type = ExternDecl(
        name: "kk_ktypeprojection_type",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_ktypeprojection_variance = ExternDecl(
        name: "kk_ktypeprojection_variance",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_typeof = ExternDecl(
        name: "kk_typeof",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_op_is = ExternDecl(
        name: "kk_op_is",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_op_cast = ExternDecl(
        name: "kk_op_cast",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    public static let kk_op_safe_cast = ExternDecl(
        name: "kk_op_safe_cast",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_op_contains = ExternDecl(
        name: "kk_op_contains",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    // MARK: - Range/Progression (P5-68)

    public static let kk_op_rangeTo = ExternDecl(
        name: "kk_op_rangeTo",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_op_rangeUntil = ExternDecl(
        name: "kk_op_rangeUntil",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_op_ulong_rangeUntil = ExternDecl(
        name: "kk_op_ulong_rangeUntil",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_op_downTo = ExternDecl(
        name: "kk_op_downTo",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_op_step = ExternDecl(
        name: "kk_op_step",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    // MARK: - IntRange members (STDLIB-090/091/092/093)

    public static let kk_range_first = ExternDecl(
        name: "kk_range_first",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_range_last = ExternDecl(
        name: "kk_range_last",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_range_count = ExternDecl(
        name: "kk_range_count",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_range_isEmpty = ExternDecl(
        name: "kk_range_isEmpty",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_range_sum = ExternDecl(
        name: "kk_range_sum",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_range_toList = ExternDecl(
        name: "kk_range_toList",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_ulong_range_toList = ExternDecl(
        name: "kk_ulong_range_toList",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_ulong_range_contains = ExternDecl(
        name: "kk_ulong_range_contains",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_ulong_range_first = ExternDecl(
        name: "kk_ulong_range_first",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_ulong_range_last = ExternDecl(
        name: "kk_ulong_range_last",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_ulong_range_step = ExternDecl(
        name: "kk_ulong_range_step",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_ulong_range_isEmpty = ExternDecl(
        name: "kk_ulong_range_isEmpty",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_ulong_range_reversed = ExternDecl(
        name: "kk_ulong_range_reversed",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_ulong_range_toULongArray = ExternDecl(
        name: "kk_ulong_range_toULongArray",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_range_forEach = ExternDecl(
        name: "kk_range_forEach",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    public static let kk_range_map = ExternDecl(
        name: "kk_range_map",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    public static let kk_range_step = ExternDecl(
        name: "kk_range_step",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_range_mapIndexed = ExternDecl(
        name: "kk_range_mapIndexed",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    public static let kk_range_mapNotNull = ExternDecl(
        name: "kk_range_mapNotNull",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    public static let kk_range_filter = ExternDecl(
        name: "kk_range_filter",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    public static let kk_range_filterIndexed = ExternDecl(
        name: "kk_range_filterIndexed",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    public static let kk_range_filterNot = ExternDecl(
        name: "kk_range_filterNot",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    public static let kk_range_reduce = ExternDecl(
        name: "kk_range_reduce",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    public static let kk_range_reduceIndexed = ExternDecl(
        name: "kk_range_reduceIndexed",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    public static let kk_range_fold = ExternDecl(
        name: "kk_range_fold",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    public static let kk_range_foldIndexed = ExternDecl(
        name: "kk_range_foldIndexed",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    public static let kk_range_find = ExternDecl(
        name: "kk_range_find",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    public static let kk_range_findLast = ExternDecl(
        name: "kk_range_findLast",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    public static let kk_range_first_predicate = ExternDecl(
        name: "kk_range_first_predicate",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    public static let kk_range_firstOrNull_predicate = ExternDecl(
        name: "kk_range_firstOrNull_predicate",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    public static let kk_range_last_predicate = ExternDecl(
        name: "kk_range_last_predicate",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    public static let kk_range_lastOrNull_predicate = ExternDecl(
        name: "kk_range_lastOrNull_predicate",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    public static let kk_range_any = ExternDecl(
        name: "kk_range_any",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    public static let kk_range_all = ExternDecl(
        name: "kk_range_all",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    public static let kk_range_none = ExternDecl(
        name: "kk_range_none",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    public static let kk_range_chunked = ExternDecl(
        name: "kk_range_chunked",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_range_windowed = ExternDecl(
        name: "kk_range_windowed",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_range_reversed = ExternDecl(
        name: "kk_range_reversed",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    // MARK: - Progression fromClosedRange (STDLIB-RANGE-039)

    public static let kk_int_progression_fromClosedRange = ExternDecl(
        name: "kk_int_progression_fromClosedRange",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    public static let kk_long_progression_fromClosedRange = ExternDecl(
        name: "kk_long_progression_fromClosedRange",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    public static let kk_uint_progression_fromClosedRange = ExternDecl(
        name: "kk_uint_progression_fromClosedRange",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    public static let kk_ulong_progression_fromClosedRange = ExternDecl(
        name: "kk_ulong_progression_fromClosedRange",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    // MARK: - UIntProgression operations (STDLIB-RANGE-039)

    public static let kk_uint_rangeTo = ExternDecl(
        name: "kk_uint_rangeTo",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_uint_downTo = ExternDecl(
        name: "kk_uint_downTo",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_uint_step = ExternDecl(
        name: "kk_uint_step",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_uint_range_reversed = ExternDecl(
        name: "kk_uint_range_reversed",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_uint_range_toList = ExternDecl(
        name: "kk_uint_range_toList",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    // MARK: - ULongProgression operations (STDLIB-RANGE-039)

    public static let kk_ulong_rangeTo = ExternDecl(
        name: "kk_ulong_rangeTo",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_ulong_downTo = ExternDecl(
        name: "kk_ulong_downTo",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_ulong_step = ExternDecl(
        name: "kk_ulong_step",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    // CharRange (STDLIB-290)
    public static let kk_char_range_toList = ExternDecl(
        name: "kk_char_range_toList",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_char_range_forEach = ExternDecl(
        name: "kk_char_range_forEach",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    // MARK: - Delegate

    public static let kk_lazy_create = ExternDecl(
        name: "kk_lazy_create",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_lazy_get_value = ExternDecl(
        name: "kk_lazy_get_value",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_lazy_is_initialized = ExternDecl(
        name: "kk_lazy_is_initialized",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_observable_create = ExternDecl(
        name: "kk_observable_create",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_observable_get_value = ExternDecl(
        name: "kk_observable_get_value",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_observable_set_value = ExternDecl(
        name: "kk_observable_set_value",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_vetoable_create = ExternDecl(
        name: "kk_vetoable_create",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_vetoable_get_value = ExternDecl(
        name: "kk_vetoable_get_value",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_vetoable_set_value = ExternDecl(
        name: "kk_vetoable_set_value",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_notNull_create = ExternDecl(
        name: "kk_notNull_create",
        parameterTypes: [],
        returnType: "intptr_t"
    )

    public static let kk_notNull_get_value = ExternDecl(
        name: "kk_notNull_get_value",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_notNull_set_value = ExternDecl(
        name: "kk_notNull_set_value",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_custom_delegate_create = ExternDecl(
        name: "kk_custom_delegate_create",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_custom_delegate_get_value = ExternDecl(
        name: "kk_custom_delegate_get_value",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_custom_delegate_set_value = ExternDecl(
        name: "kk_custom_delegate_set_value",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    // MARK: - Bitwise/Shift (P5-103)

    public static let kk_bitwise_and = ExternDecl(
        name: "kk_bitwise_and",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_bitwise_or = ExternDecl(
        name: "kk_bitwise_or",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_bitwise_xor = ExternDecl(
        name: "kk_bitwise_xor",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_op_not = ExternDecl(
        name: "kk_op_not",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_op_inv = ExternDecl(
        name: "kk_op_inv",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_op_shl = ExternDecl(
        name: "kk_op_shl",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_op_shr = ExternDecl(
        name: "kk_op_shr",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_op_ushr = ExternDecl(
        name: "kk_op_ushr",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_op_dmul = ExternDecl(
        name: "kk_op_dmul",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_int_toString_radix = ExternDecl(
        name: "kk_int_toString_radix",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "void *"
    )

    public static let kk_int_countOneBits = ExternDecl(
        name: "kk_int_countOneBits",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_int_countLeadingZeroBits = ExternDecl(
        name: "kk_int_countLeadingZeroBits",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_int_countTrailingZeroBits = ExternDecl(
        name: "kk_int_countTrailingZeroBits",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    // MARK: - STDLIB-BIT-007: Additional bit manipulation functions

    public static let kk_int_rotateLeft = ExternDecl(
        name: "kk_int_rotateLeft",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_int_rotateRight = ExternDecl(
        name: "kk_int_rotateRight",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_int_highestOneBit = ExternDecl(
        name: "kk_int_highestOneBit",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_int_lowestOneBit = ExternDecl(
        name: "kk_int_lowestOneBit",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_int_takeHighestOneBit = ExternDecl(
        name: "kk_int_takeHighestOneBit",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_int_takeLowestOneBit = ExternDecl(
        name: "kk_int_takeLowestOneBit",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    // Long bit manipulation functions

    public static let kk_long_rotateLeft = ExternDecl(
        name: "kk_long_rotateLeft",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_long_rotateRight = ExternDecl(
        name: "kk_long_rotateRight",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_long_highestOneBit = ExternDecl(
        name: "kk_long_highestOneBit",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_long_lowestOneBit = ExternDecl(
        name: "kk_long_lowestOneBit",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_long_takeHighestOneBit = ExternDecl(
        name: "kk_long_takeHighestOneBit",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_long_takeLowestOneBit = ExternDecl(
        name: "kk_long_takeLowestOneBit",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    // MARK: - Any methods (STDLIB-306)

    public static let kk_any_to_string = ExternDecl(
        name: "kk_any_to_string",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "void *"
    )

    public static let kk_any_hashCode = ExternDecl(
        name: "kk_any_hashCode",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_any_equals = ExternDecl(
        name: "kk_any_equals",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_structural_eq = ExternDecl(
        name: "kk_structural_eq",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    // MARK: - Regex (STDLIB-100/101/102/103)

    public static let kk_regex_create = ExternDecl(
        name: "kk_regex_create",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_string_matches_regex = ExternDecl(
        name: "kk_string_matches_regex",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_string_contains_regex = ExternDecl(
        name: "kk_string_contains_regex",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_regex_find = ExternDecl(
        name: "kk_regex_find",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_regex_findAll = ExternDecl(
        name: "kk_regex_findAll",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_string_replace_regex = ExternDecl(
        name: "kk_string_replace_regex",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_string_split_regex = ExternDecl(
        name: "kk_string_split_regex",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_string_toRegex = ExternDecl(
        name: "kk_string_toRegex",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_regex_pattern = ExternDecl(
        name: "kk_regex_pattern",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_match_result_value = ExternDecl(
        name: "kk_match_result_value",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_match_result_groupValues = ExternDecl(
        name: "kk_match_result_groupValues",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    // STDLIB-351: Regex.replace(input) { lambda }
    public static let kk_regex_replace_lambda = ExternDecl(
        name: "kk_regex_replace_lambda",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t", "intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    // STDLIB-350: Regex.matchEntire
    public static let kk_regex_matchEntire = ExternDecl(
        name: "kk_regex_matchEntire",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    // STDLIB-480: Regex(pattern, option) constructor
    public static let kk_regex_create_with_option = ExternDecl(
        name: "kk_regex_create_with_option",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    // STDLIB-480: Regex(pattern, options: Set<RegexOption>) constructor
    public static let kk_regex_create_with_options = ExternDecl(
        name: "kk_regex_create_with_options",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    // STDLIB-480: Regex.containsMatchIn(input)
    public static let kk_regex_containsMatchIn = ExternDecl(
        name: "kk_regex_containsMatchIn",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    // MatchResult.groups
    public static let kk_match_result_groups = ExternDecl(
        name: "kk_match_result_groups",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    // MatchGroupCollection.get(name)
    public static let kk_match_group_collection_get = ExternDecl(
        name: "kk_match_group_collection_get",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "intptr_t"
    )

    // MatchGroup.value
    public static let kk_match_group_value = ExternDecl(
        name: "kk_match_group_value",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    // MatchGroup.range
    public static let kk_match_group_range = ExternDecl(
        name: "kk_match_group_range",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    // STDLIB-REGEX-097: Regex.groupNames
    public static let kk_regex_group_names = ExternDecl(
        name: "kk_regex_group_names",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    // MARK: - File I/O (STDLIB-320/321/322/323)

    // IMPORTANT: The raw parameter type strings here (e.g. "intptr_t",
    // "intptr_t * _Nullable") must exactly match the corresponding
    // `RuntimeABICType.rawValue` values used in RuntimeABISpec (Runtime module).
    // The ABI reconciliation tests in RuntimeTests verify this at build time,
    // but if you add or change a parameter type here, update RuntimeABISpec
    // (and vice-versa) to keep both sides in sync.

    private static let intptr = "intptr_t"
    private static let nullableIntptrPtr = "intptr_t * _Nullable"

    public static let kk_file_new = ExternDecl(
        name: "kk_file_new",
        parameterTypes: [intptr],
        returnType: intptr
    )

    public static let kk_file_readText = ExternDecl(
        name: "kk_file_readText",
        parameterTypes: [intptr, nullableIntptrPtr],
        returnType: intptr
    )

    public static let kk_file_writeText = ExternDecl(
        name: "kk_file_writeText",
        parameterTypes: [intptr, intptr, nullableIntptrPtr],
        returnType: intptr
    )

    public static let kk_file_appendText = ExternDecl(
        name: "kk_file_appendText",
        parameterTypes: [intptr, intptr, nullableIntptrPtr],
        returnType: intptr
    )

    public static let kk_file_readLines = ExternDecl(
        name: "kk_file_readLines",
        parameterTypes: [intptr, nullableIntptrPtr],
        returnType: intptr
    )

    public static let kk_file_readBytes = ExternDecl(
        name: "kk_file_readBytes",
        parameterTypes: [intptr, nullableIntptrPtr],
        returnType: intptr
    )

    public static let kk_file_forEachLine = ExternDecl(
        name: "kk_file_forEachLine",
        parameterTypes: [intptr, intptr, intptr, nullableIntptrPtr],
        returnType: intptr
    )

    public static let kk_file_exists = ExternDecl(
        name: "kk_file_exists",
        parameterTypes: [intptr],
        returnType: intptr
    )

    public static let kk_file_isFile = ExternDecl(
        name: "kk_file_isFile",
        parameterTypes: [intptr],
        returnType: intptr
    )

    public static let kk_file_isDirectory = ExternDecl(
        name: "kk_file_isDirectory",
        parameterTypes: [intptr],
        returnType: intptr
    )

    public static let kk_file_name = ExternDecl(
        name: "kk_file_name",
        parameterTypes: [intptr],
        returnType: intptr
    )

    public static let kk_file_path = ExternDecl(
        name: "kk_file_path",
        parameterTypes: [intptr],
        returnType: intptr
    )

    public static let kk_file_delete = ExternDecl(
        name: "kk_file_delete",
        parameterTypes: [intptr],
        returnType: intptr
    )

    public static let kk_file_mkdirs = ExternDecl(
        name: "kk_file_mkdirs",
        parameterTypes: [intptr],
        returnType: intptr
    )

    public static let kk_file_listFiles = ExternDecl(
        name: "kk_file_listFiles",
        parameterTypes: [intptr],
        returnType: intptr
    )

    public static let kk_file_walk = ExternDecl(
        name: "kk_file_walk",
        parameterTypes: [intptr],
        returnType: intptr
    )

    // STDLIB-567: File.bufferedReader()
    public static let kk_file_bufferedReader = ExternDecl(
        name: "kk_file_bufferedReader",
        parameterTypes: [intptr, nullableIntptrPtr],
        returnType: intptr
    )

    public static let kk_buffered_reader_readLine = ExternDecl(
        name: "kk_buffered_reader_readLine",
        parameterTypes: [intptr],
        returnType: intptr
    )

    public static let kk_buffered_reader_readLines = ExternDecl(
        name: "kk_buffered_reader_readLines",
        parameterTypes: [intptr],
        returnType: intptr
    )

    public static let kk_buffered_reader_close = ExternDecl(
        name: "kk_buffered_reader_close",
        parameterTypes: [intptr],
        returnType: intptr
    )

    public static let kk_file_inputStream = ExternDecl(
        name: "kk_file_inputStream",
        parameterTypes: [intptr, nullableIntptrPtr],
        returnType: intptr
    )

    public static let kk_file_outputStream = ExternDecl(
        name: "kk_file_outputStream",
        parameterTypes: [intptr, nullableIntptrPtr],
        returnType: intptr
    )

    public static let kk_input_stream_read = ExternDecl(
        name: "kk_input_stream_read",
        parameterTypes: [intptr, nullableIntptrPtr],
        returnType: intptr
    )

    public static let kk_input_stream_available = ExternDecl(
        name: "kk_input_stream_available",
        parameterTypes: [intptr],
        returnType: intptr
    )

    public static let kk_input_stream_skip = ExternDecl(
        name: "kk_input_stream_skip",
        parameterTypes: [intptr, intptr, nullableIntptrPtr],
        returnType: intptr
    )

    public static let kk_input_stream_read_bytes = ExternDecl(
        name: "kk_input_stream_read_bytes",
        parameterTypes: [intptr, intptr, nullableIntptrPtr],
        returnType: intptr
    )

    public static let kk_input_stream_close = ExternDecl(
        name: "kk_input_stream_close",
        parameterTypes: [intptr],
        returnType: intptr
    )

    public static let kk_output_stream_write_byte = ExternDecl(
        name: "kk_output_stream_write_byte",
        parameterTypes: [intptr, intptr, nullableIntptrPtr],
        returnType: intptr
    )

    public static let kk_output_stream_write_bytes = ExternDecl(
        name: "kk_output_stream_write_bytes",
        parameterTypes: [intptr, intptr, nullableIntptrPtr],
        returnType: intptr
    )

    public static let kk_output_stream_flush = ExternDecl(
        name: "kk_output_stream_flush",
        parameterTypes: [intptr, nullableIntptrPtr],
        returnType: intptr
    )

    public static let kk_output_stream_close = ExternDecl(
        name: "kk_output_stream_close",
        parameterTypes: [intptr],
        returnType: intptr
    )

    public static let kk_classloader_getSystemClassLoader = ExternDecl(
        name: "kk_classloader_getSystemClassLoader",
        parameterTypes: [],
        returnType: intptr
    )

    public static let kk_classloader_getResource = ExternDecl(
        name: "kk_classloader_getResource",
        parameterTypes: [intptr, intptr],
        returnType: intptr
    )

    public static let kk_classloader_getResourceAsStream = ExternDecl(
        name: "kk_classloader_getResourceAsStream",
        parameterTypes: [intptr, intptr],
        returnType: intptr
    )

    public static let kk_resource_exists = ExternDecl(
        name: "kk_resource_exists",
        parameterTypes: [intptr],
        returnType: intptr
    )

    public static let kk_readResourceAsText = ExternDecl(
        name: "kk_readResourceAsText",
        parameterTypes: [intptr, nullableIntptrPtr],
        returnType: intptr
    )

    public static let kk_resource_stream_read = ExternDecl(
        name: "kk_resource_stream_read",
        parameterTypes: [intptr],
        returnType: intptr
    )

    public static let kk_resource_stream_close = ExternDecl(
        name: "kk_resource_stream_close",
        parameterTypes: [intptr],
        returnType: intptr
    )

    public static let kk_file_useLines = ExternDecl(
        name: "kk_file_useLines",
        parameterTypes: [intptr, intptr, intptr, nullableIntptrPtr],
        returnType: intptr
    )

    public static let kk_uri_new = ExternDecl(name: "kk_uri_new", parameterTypes: [intptr, nullableIntptrPtr], returnType: intptr)
    public static let kk_uri_toString = ExternDecl(name: "kk_uri_toString", parameterTypes: [intptr], returnType: intptr)
    public static let kk_uri_scheme = ExternDecl(name: "kk_uri_scheme", parameterTypes: [intptr], returnType: intptr)
    public static let kk_uri_authority = ExternDecl(name: "kk_uri_authority", parameterTypes: [intptr], returnType: intptr)
    public static let kk_uri_path = ExternDecl(name: "kk_uri_path", parameterTypes: [intptr], returnType: intptr)
    public static let kk_uri_query = ExternDecl(name: "kk_uri_query", parameterTypes: [intptr], returnType: intptr)
    public static let kk_uri_fragment = ExternDecl(name: "kk_uri_fragment", parameterTypes: [intptr], returnType: intptr)
    public static let kk_uri_normalize = ExternDecl(name: "kk_uri_normalize", parameterTypes: [intptr], returnType: intptr)
    public static let kk_uri_resolve = ExternDecl(name: "kk_uri_resolve", parameterTypes: [intptr, intptr, nullableIntptrPtr], returnType: intptr)
    public static let kk_uri_relativize = ExternDecl(name: "kk_uri_relativize", parameterTypes: [intptr, intptr], returnType: intptr)
    public static let kk_logger_getLogger = ExternDecl(name: "kk_logger_getLogger", parameterTypes: [intptr], returnType: intptr)
    public static let kk_logging_level_info = ExternDecl(name: "kk_logging_level_info", parameterTypes: [], returnType: intptr)
    public static let kk_logging_level_warning = ExternDecl(name: "kk_logging_level_warning", parameterTypes: [], returnType: intptr)
    public static let kk_logging_level_severe = ExternDecl(name: "kk_logging_level_severe", parameterTypes: [], returnType: intptr)
    public static let kk_console_handler_new = ExternDecl(name: "kk_console_handler_new", parameterTypes: [], returnType: intptr)
    public static let kk_file_handler_new = ExternDecl(name: "kk_file_handler_new", parameterTypes: [intptr], returnType: intptr)
    public static let kk_logger_addHandler = ExternDecl(name: "kk_logger_addHandler", parameterTypes: [intptr, intptr], returnType: intptr)
    public static let kk_logger_log = ExternDecl(name: "kk_logger_log", parameterTypes: [intptr, intptr, intptr], returnType: intptr)
    public static let kk_logger_info = ExternDecl(name: "kk_logger_info", parameterTypes: [intptr, intptr], returnType: intptr)
    public static let kk_logger_warning = ExternDecl(name: "kk_logger_warning", parameterTypes: [intptr, intptr], returnType: intptr)
    public static let kk_logger_severe = ExternDecl(name: "kk_logger_severe", parameterTypes: [intptr, intptr], returnType: intptr)
    public static let kk_message_digest_getInstance = ExternDecl(name: "kk_message_digest_getInstance", parameterTypes: [intptr, nullableIntptrPtr], returnType: intptr)
    public static let kk_message_digest_digest = ExternDecl(name: "kk_message_digest_digest", parameterTypes: [intptr, intptr, nullableIntptrPtr], returnType: intptr)

    public static let fileIOExterns: [ExternDecl] = [
        kk_file_new,
        kk_file_readText,
        kk_file_writeText,
        kk_file_appendText,
        kk_file_readLines,
        kk_file_readBytes,
        kk_file_forEachLine,
        kk_file_exists,
        kk_file_isFile,
        kk_file_isDirectory,
        kk_file_name,
        kk_file_path,
        kk_file_delete,
        kk_file_mkdirs,
        kk_file_listFiles,
        kk_file_walk,
        kk_file_bufferedReader,
        kk_buffered_reader_readLine,
        kk_buffered_reader_readLines,
        kk_buffered_reader_close,
        kk_file_inputStream,
        kk_file_outputStream,
        kk_input_stream_read,
        kk_input_stream_available,
        kk_input_stream_skip,
        kk_input_stream_read_bytes,
        kk_input_stream_close,
        kk_output_stream_write_byte,
        kk_output_stream_write_bytes,
        kk_output_stream_flush,
        kk_output_stream_close,
        kk_classloader_getSystemClassLoader,
        kk_classloader_getResource,
        kk_classloader_getResourceAsStream,
        kk_resource_exists,
        kk_readResourceAsText,
        kk_resource_stream_read,
        kk_resource_stream_close,
        kk_file_useLines,
        kk_uri_new,
        kk_uri_toString,
        kk_uri_scheme,
        kk_uri_authority,
        kk_uri_path,
        kk_uri_query,
        kk_uri_fragment,
        kk_uri_normalize,
        kk_uri_resolve,
        kk_uri_relativize,
        kk_logger_getLogger,
        kk_logging_level_info,
        kk_logging_level_warning,
        kk_logging_level_severe,
        kk_console_handler_new,
        kk_file_handler_new,
        kk_logger_addHandler,
        kk_logger_log,
        kk_logger_info,
        kk_logger_warning,
        kk_logger_severe,
        kk_message_digest_getInstance,
        kk_message_digest_digest,
    ]

    public static let regexExterns: [ExternDecl] = [
        kk_regex_create,
        kk_string_matches_regex,
        kk_string_contains_regex,
        kk_regex_find,
        kk_regex_findAll,
        kk_string_replace_regex,
        kk_string_split_regex,
        kk_string_toRegex,
        kk_regex_pattern,
        kk_match_result_value,
        kk_match_result_groupValues,
        kk_regex_replace_lambda,
        kk_regex_matchEntire,
        kk_regex_create_with_option,
        kk_regex_create_with_options,
        kk_regex_containsMatchIn,
        kk_match_result_groups,
        kk_match_group_collection_get,
        kk_match_group_value,
        kk_match_group_range,
        kk_regex_group_names,
    ]

    // MARK: - All Functions (canonical list)

    /// All runtime extern declarations, ordered by section.
    /// This is the authoritative list that must match `RuntimeABISpec.allFunctions`.
    public static let allExterns: [ExternDecl] = {
        var all: [ExternDecl] = [
            // Memory
            kk_alloc,
            kk_gc_collect,
            kk_write_barrier,
            // Exception
            kk_throwable_new,
            kk_throwable_new_with_cause,
            kk_throwable_is_cancellation,
            kk_panic,
            kk_abort_unreachable,
            kk_require,
            kk_check,
            kk_require_lazy,
            kk_synchronized,
            kk_check_lazy,
            kk_precondition_assert,
            kk_precondition_assert_lazy,
            kk_test_assertEquals,
            kk_test_assertEquals_message,
            kk_test_assertTrue,
            kk_test_assertTrue_message,
            kk_test_assertNull,
            kk_test_assertNull_message,
            kk_error,
            kk_todo,
            kk_todo_noarg,
            kk_dispatch_error,
            kk_throwable_message,
            kk_throwable_cause,
            kk_throwable_stackTraceToString,
            // Test Framework
            kk_test_assertEquals,
            kk_test_assertEquals_message,
            kk_test_assertTrue,
            kk_test_assertTrue_message,
            kk_test_assertNull,
            kk_test_assertNull_message,
            // String
            kk_string_from_utf8,
            kk_string_concat,
            kk_string_compareTo,
            kk_compare_any,
            kk_string_length,
            kk_string_trim,
            kk_string_lowercase,
            kk_string_uppercase,
            kk_locale_new,
            kk_string_lowercase_locale,
            kk_string_uppercase_locale,
            kk_string_compareTo_locale,
            kk_normalization_form_nfc,
            kk_normalization_form_nfd,
            kk_normalization_form_nfkc,
            kk_normalization_form_nfkd,
            kk_string_normalize,
            kk_string_isNormalized,
            kk_string_trimIndent,
            kk_string_trimMargin_default,
            kk_string_trimMargin,
            kk_string_format,
            kk_string_toBigDecimal,
            kk_bignum_toString,
            kk_string_isNullOrEmpty,
            kk_string_isNullOrBlank,
            kk_string_startsWith,
            kk_string_endsWith,
            kk_string_contains_str,
            kk_string_replace,
            kk_string_replaceFirst,
            kk_any_to_string,
            kk_any_hashCode,
            kk_any_equals,
            kk_structural_eq,
            kk_string_replaceRange,
            kk_string_substring,
            kk_string_split,
            kk_string_toInt,
            kk_string_toInt_radix,
            kk_string_toIntOrNull,
            kk_string_toDouble,
            kk_string_toDoubleOrNull,
            kk_string_toLong,
            kk_string_toLongOrNull,
            kk_string_toFloat,
            kk_string_toFloatOrNull,
            kk_string_indexOf,
            kk_string_lastIndexOf,
            kk_string_indexOf_from,
            kk_string_indexOfFirst,
            kk_string_indexOfLast,
            kk_string_get,
            kk_string_compareTo_member,
            kk_string_compareToIgnoreCase,
            kk_string_equals,
            kk_enum_valueOf_throw,
            kk_enum_make_values_array,
            kk_enum_make_entries_list,
            kk_string_toBoolean,
            kk_string_toBooleanStrict,
            kk_string_lines,
            kk_string_lineSequence,
            kk_string_trimStart,
            kk_string_trimEnd,
            kk_string_toByteArray,
            kk_string_toByteArray_charset,
            kk_charset_utf_8,
            kk_charset_iso_8859_1,
            kk_charset_us_ascii,
            kk_charset_utf_16,
            kk_charset_utf_16be,
            kk_charset_utf_16le,
            kk_charset_utf_32,
            kk_charset_utf_32be,
            kk_charset_utf_32le,
            kk_string_encodeToByteArray,
            kk_string_encodeToByteArray_range,
            kk_string_encodeToByteArray_charset,
            kk_bytearray_decodeToString,
            kk_bytearray_decodeToString_charset,
            kk_char_isDigit,
            kk_char_isLetter,
            kk_char_isLetterOrDigit,
            kk_char_isUpperCase,
            kk_char_isLowerCase,
            kk_char_isWhitespace,
            kk_char_uppercase,
            kk_char_lowercase,
            kk_char_titlecase,
            kk_char_digitToInt,
            kk_char_digitToIntOrNull,
            kk_string_padStart_default,
            kk_string_padEnd_default,
            kk_string_padStart,
            kk_string_padEnd,
            kk_string_repeat,
            kk_string_reversed,
            kk_string_toList,
            kk_string_toCharArray,
            kk_chararray_concatToString,
            kk_string_asIterable,
            kk_string_iterable_toList,
            kk_string_iterable_iterator,
            kk_string_iterator,
            kk_string_iterator_hasNext,
            kk_string_iterator_next,
            kk_string_filter,
            kk_string_map,
            kk_string_count,
            kk_string_any,
            kk_string_all,
            kk_string_none,
            kk_string_replaceFirstChar,
            kk_string_take,
            kk_string_drop,
            kk_string_takeLast,
            kk_string_dropLast,
            kk_string_removePrefix,
            kk_string_removeSuffix,
            kk_string_removeSurrounding,
            kk_string_removeSurrounding_pair,
            kk_string_prependIndent_default,
            kk_string_prependIndent,
            kk_string_replaceIndent_default,
            kk_string_replaceIndent,
            kk_string_equalsIgnoreCase,
            kk_string_first,
            kk_string_last,
            kk_string_single,
            kk_string_firstOrNull,
            kk_string_lastOrNull,
            kk_string_singleOrNull,
            kk_string_isEmpty,
            kk_string_isNotEmpty,
            kk_string_isBlank,
            kk_string_isNotBlank,
            kk_string_substringBefore,
            kk_string_substringAfter,
            kk_string_substringBeforeLast,
            kk_string_substringAfterLast,
            kk_string_chunked,
            kk_string_windowed_default,
            kk_string_windowed,
            kk_string_windowed_partial,
            kk_string_commonPrefixWith,
            kk_string_commonSuffixWith,
            kk_string_commonPrefixWith_ignoreCase,
            kk_string_commonSuffixWith_ignoreCase,
            kk_string_zipWithNext,
            kk_string_orEmpty,
            kk_string_asSequence,
            kk_string_asIterable,
            // Print / Println
            kk_print_any,
            kk_print_noarg,
            kk_println_any,
            kk_println_bool,
            kk_println_ulong,
            kk_println_newline,
            // IO
            kk_readline,
            kk_readln,
            kk_readlnOrNull,
            // System
            kk_system_exitProcess,
            kk_system_currentTimeMillis,
            kk_system_nanoTime,
            kk_system_measureTimeMillis,
            kk_system_measureNanoTime,
            // GC
            kk_register_global_root,
            kk_unregister_global_root,
            kk_register_frame_map,
            kk_push_frame,
            kk_pop_frame,
            kk_register_coroutine_root,
            kk_unregister_coroutine_root,
            kk_runtime_heap_object_count,
            kk_runtime_force_reset,
            // Coroutine
            kk_coroutine_suspended,
            kk_coroutine_continuation_new,
            kk_coroutine_state_enter,
            kk_coroutine_state_set_label,
            kk_coroutine_state_exit,
            kk_coroutine_state_set_spill,
            kk_coroutine_state_get_spill,
            kk_coroutine_state_set_completion,
            kk_coroutine_state_get_completion,
            kk_kxmini_run_blocking,
            kk_kxmini_launch,
            kk_kxmini_async,
            kk_kxmini_async_await,
            kk_kxmini_delay,
            kk_coroutine_launcher_arg_set,
            kk_coroutine_launcher_arg_get,
            kk_kxmini_run_blocking_with_cont,
            kk_kxmini_launch_with_cont,
            kk_kxmini_async_with_cont,
            // CORO-071: async exception handling, cancellation, dispatcher
            kk_kxmini_async_await_throwing,
            kk_async_task_cancel,
            kk_kxmini_async_with_dispatcher,
            // Flow (CORO-003)
            kk_flow_create,
            kk_flow_emit,
            kk_flow_collect,
            kk_flow_retain,
            kk_flow_release,
            // Flow terminal operators & flowOf (STDLIB-088)
            kk_flow_of,
            kk_flow_to_list,
            kk_flow_first,
            kk_flow_count,
            kk_flow_fold,
            kk_flow_reduce,
            // Dispatchers / withContext
            kk_dispatcher_default,
            kk_dispatcher_io,
            kk_dispatcher_main,
            kk_with_context,
            // Channel (CORO-001)
            kk_channel_create,
            kk_channel_send,
            kk_channel_receive,
            kk_channel_close,
            kk_channel_is_closed_token,
            // Deferred / awaitAll
            kk_await_all,
            // Structured Concurrency (P5-89)
            kk_coroutine_scope_new,
            kk_coroutine_scope_cancel,
            kk_coroutine_scope_wait,
            kk_coroutine_scope_register_child,
            kk_job_join,
            kk_coroutine_scope_run,
            kk_coroutine_scope_run_with_cont,
            kk_supervisor_scope_run,
            kk_supervisor_scope_run_with_cont,
            // Cancellation (CORO-002)
            kk_coroutine_check_cancellation,
            kk_is_cancellation_exception,
            kk_job_cancel,
            kk_coroutine_cancel,
            // Mutex / Semaphore (sync primitives)
            kk_mutex_create,
            kk_mutex_lock,
            kk_mutex_unlock,
            kk_mutex_tryLock,
            kk_mutex_isLocked,
            kk_semaphore_create,
            kk_semaphore_acquire,
            kk_semaphore_release,
            kk_semaphore_tryAcquire,
            kk_semaphore_availablePermits,
            // Boxing
            kk_box_int,
            kk_box_bool,
            kk_lateinit_is_initialized,
            kk_lateinit_get_or_throw,
            kk_unbox_int,
            kk_unbox_bool,
            kk_box_long,
            kk_box_float,
            kk_box_double,
            kk_box_char,
            kk_unbox_long,
            kk_unbox_float,
            kk_unbox_double,
            kk_unbox_char,
            // Array
            kk_array_new,
            kk_object_new,
            kk_object_type_id,
            kk_array_get,
            kk_array_get_inbounds,
            kk_array_set,
            kk_vararg_spread_concat,
            // TypeCheck Operators
            kk_type_register_super,
            kk_type_register_iface,
            kk_object_register_itable_method,
            kk_type_token_simple_name,
            kk_type_token_qualified_name,
            kk_kclass_create,
            kk_kclass_simple_name,
            kk_kclass_qualified_name,
            // REFL-004: KClass binary metadata
            kk_kclass_register_metadata,
            kk_kclass_is_data,
            kk_kclass_is_sealed,
            kk_kclass_is_value,
            kk_kclass_is_interface,
            kk_kclass_is_object,
            kk_kclass_is_enum,
            kk_kclass_is_abstract,
            kk_kclass_supertype_name,
            kk_kclass_members_count,
            // REFL-005: KClass.isInstance, members, constructors, KType, typeOf
            kk_kclass_isInstance,
            kk_kclass_members,
            kk_kclass_constructors,
            kk_ktype_create,
            kk_ktype_classifier,
            kk_ktype_arguments,
            kk_ktype_isMarkedNullable,
            kk_ktypeprojection_create,
            kk_ktypeprojection_type,
            kk_ktypeprojection_variance,
            kk_typeof,
            kk_op_is,
            kk_op_cast,
            kk_op_safe_cast,
            kk_op_contains,
        ]
        all += primitiveNumericConversionExterns
        all += [
            // Range/Progression
            kk_op_rangeTo,
            kk_op_rangeUntil,
            kk_op_ulong_rangeUntil,
            kk_op_downTo,
            kk_op_step,
            // IntRange members (STDLIB-090/091/092/093)
            kk_range_first,
            kk_range_last,
            kk_range_count,
            kk_range_isEmpty,
            kk_range_sum,
            kk_range_toList,
            kk_ulong_range_toList,
            kk_ulong_range_contains,
            kk_ulong_range_first,
            kk_ulong_range_last,
            kk_ulong_range_step,
            kk_ulong_range_isEmpty,
            kk_ulong_range_reversed,
            kk_ulong_range_toULongArray,
            kk_range_forEach,
            kk_range_map,
            kk_range_step,
            kk_range_mapIndexed,
            kk_range_mapNotNull,
            kk_range_filter,
            kk_range_filterIndexed,
            kk_range_filterNot,
            kk_range_reduce,
            kk_range_reduceIndexed,
            kk_range_fold,
            kk_range_foldIndexed,
            kk_range_find,
            kk_range_findLast,
            kk_range_first_predicate,
            kk_range_firstOrNull_predicate,
            kk_range_last_predicate,
            kk_range_lastOrNull_predicate,
            kk_range_any,
            kk_range_all,
            kk_range_none,
            kk_range_chunked,
            kk_range_windowed,
            kk_range_reversed,
            // Progression fromClosedRange (STDLIB-RANGE-039)
            kk_int_progression_fromClosedRange,
            kk_long_progression_fromClosedRange,
            kk_uint_progression_fromClosedRange,
            kk_ulong_progression_fromClosedRange,
            // UIntProgression operations (STDLIB-RANGE-039)
            kk_uint_rangeTo,
            kk_uint_downTo,
            kk_uint_step,
            kk_uint_range_reversed,
            kk_uint_range_toList,
            // ULongProgression operations (STDLIB-RANGE-039)
            kk_ulong_rangeTo,
            kk_ulong_downTo,
            kk_ulong_step,
            kk_ulong_range_reversed,
            // CharRange (STDLIB-290)
            kk_char_range_toList,
            kk_char_range_forEach,
        ]
        all += kPropertyStubExterns
        all += callableRefExterns
        all += [
            // Delegate
            kk_lazy_create,
            kk_lazy_get_value,
            kk_lazy_is_initialized,
            kk_observable_create,
            kk_observable_get_value,
            kk_observable_set_value,
            kk_vetoable_create,
            kk_vetoable_get_value,
            kk_vetoable_set_value,
            kk_notNull_create,
            kk_notNull_get_value,
            kk_notNull_set_value,
            kk_custom_delegate_create,
            kk_custom_delegate_get_value,
            kk_custom_delegate_set_value,
        ]
        all += [
            // Bitwise/Shift (P5-103)
            kk_bitwise_and,
            kk_bitwise_or,
            kk_bitwise_xor,
            kk_op_not,
            kk_op_inv,
            kk_op_shl,
            kk_op_shr,
            kk_op_ushr,
            kk_op_dmul,
            kk_int_toString_radix,
            kk_int_countOneBits,
            kk_int_countLeadingZeroBits,
            kk_int_countTrailingZeroBits,
            // STDLIB-BIT-007: Additional bit manipulation functions
            kk_int_rotateLeft,
            kk_int_rotateRight,
            kk_int_highestOneBit,
            kk_int_lowestOneBit,
            kk_int_takeHighestOneBit,
            kk_int_takeLowestOneBit,
            kk_long_rotateLeft,
            kk_long_rotateRight,
            kk_long_highestOneBit,
            kk_long_lowestOneBit,
            kk_long_takeHighestOneBit,
            kk_long_takeLowestOneBit,
        ]
        all += mathExterns
        all += randomExterns
        all += collectionExterns
        all += sequenceExterns
        all += regexExterns
        all += hexFormatExterns
        all += comparatorExterns
        all += resultExterns
        all += stringBuilderExterns
        all += fileIOExterns
        all += uuidExterns
        // Duration / measureTime / measureTimedValue (STDLIB-230/231/660)
        all += [
            kk_measureTime,
            kk_measureTimedValue,
            kk_duration_inWholeMilliseconds,
            kk_duration_inWholeSeconds,
            kk_duration_inWholeMinutes,
            kk_duration_inWholeMicroseconds,
            kk_duration_inWholeNanoseconds,
            kk_duration_inWholeHours,
            kk_duration_toString,
            kk_duration_from_seconds,
            kk_duration_from_milliseconds,
            kk_duration_from_microseconds,
            kk_duration_from_nanoseconds,
            kk_duration_from_minutes,
            kk_duration_from_hours,
            kk_duration_from_days,
            kk_duration_from_seconds_long,
            kk_duration_from_milliseconds_long,
            kk_duration_from_microseconds_long,
            kk_duration_from_nanoseconds_long,
            kk_duration_from_minutes_long,
            kk_duration_from_hours_long,
            kk_duration_from_days_long,
            kk_timedvalue_new,
            kk_timedvalue_value,
            kk_timedvalue_duration,
            kk_timedvalue_toString,
            // Duration advanced operations (STDLIB-TIME-082)
            kk_duration_absoluteValue,
            kk_duration_isNegative,
            kk_duration_isPositive,
            kk_duration_isInfinite,
            kk_duration_isFinite,
            kk_duration_plus,
            kk_duration_minus,
            kk_duration_times_int,
            kk_duration_div_int,
            kk_duration_unary_minus,
            kk_duration_compareTo,
        ]
        all += atomicExterns
        return all
    }()

    /// Look up an extern declaration by symbol name.
    public static func externDecl(named name: String) -> ExternDecl? {
        allExterns.first { $0.name == name }
    }
}

// swiftlint:enable type_body_length
