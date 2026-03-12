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
    public static let specVersion = "J23"

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

    public static let kk_string_format = ExternDecl(
        name: "kk_string_format",
        parameterTypes: ["intptr_t", "intptr_t"],
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

    // MARK: - System

    public static let kk_system_exitProcess = ExternDecl(
        name: "kk_system_exitProcess",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_system_currentTimeMillis = ExternDecl(
        name: "kk_system_currentTimeMillis",
        parameterTypes: [],
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

    // Channel (P5-134)

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

    public static let kk_range_toList = ExternDecl(
        name: "kk_range_toList",
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

    public static let kk_range_reversed = ExternDecl(
        name: "kk_range_reversed",
        parameterTypes: ["intptr_t"],
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

    public static let kk_int_toString_radix = ExternDecl(
        name: "kk_int_toString_radix",
        parameterTypes: ["intptr_t", "intptr_t"],
        returnType: "void *"
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
            kk_throwable_is_cancellation,
            kk_panic,
            kk_abort_unreachable,
            kk_require,
            kk_check,
            kk_require_lazy,
            kk_check_lazy,
            kk_error,
            kk_todo,
            kk_todo_noarg,
            kk_dispatch_error,
            kk_throwable_message,
            kk_throwable_cause,
            kk_throwable_stackTraceToString,
            // String
            kk_string_from_utf8,
            kk_string_concat,
            kk_string_compareTo,
            kk_compare_any,
            kk_string_length,
            kk_string_trim,
            kk_string_lowercase,
            kk_string_uppercase,
            kk_string_trimIndent,
            kk_string_trimMargin_default,
            kk_string_trimMargin,
            kk_string_format,
            kk_string_isNullOrEmpty,
            kk_string_isNullOrBlank,
            kk_string_startsWith,
            kk_string_endsWith,
            kk_string_contains_str,
            kk_string_replace,
            kk_string_substring,
            kk_string_split,
            kk_string_toInt,
            kk_string_toInt_radix,
            kk_string_toIntOrNull,
            kk_string_toDouble,
            kk_string_toDoubleOrNull,
            kk_string_indexOf,
            kk_string_lastIndexOf,
            kk_string_get,
            kk_string_compareTo_member,
            kk_string_compareToIgnoreCase,
            kk_string_equals,
            kk_enum_valueOf_throw,
            kk_string_toBoolean,
            kk_string_toBooleanStrict,
            kk_string_lines,
            kk_string_trimStart,
            kk_string_trimEnd,
            kk_string_toByteArray,
            kk_char_isDigit,
            kk_char_isLetter,
            kk_char_isLetterOrDigit,
            kk_char_isWhitespace,
            kk_char_uppercase,
            kk_char_lowercase,
            kk_char_titlecase,
            kk_char_digitToInt,
            kk_char_digitToIntOrNull,
            kk_string_padStart,
            kk_string_padEnd,
            kk_string_repeat,
            kk_string_reversed,
            kk_string_toList,
            kk_string_toCharArray,
            kk_string_take,
            kk_string_drop,
            kk_string_takeLast,
            kk_string_dropLast,
            // Print / Println
            kk_print_any,
            kk_println_any,
            kk_println_bool,
            kk_println_newline,
            // IO
            kk_readline,
            kk_readln,
            // System
            kk_system_exitProcess,
            kk_system_currentTimeMillis,
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
            // Flow (CORO-003)
            kk_flow_create,
            kk_flow_emit,
            kk_flow_collect,
            kk_flow_retain,
            kk_flow_release,
            // Dispatchers / withContext
            kk_dispatcher_default,
            kk_dispatcher_io,
            kk_dispatcher_main,
            kk_with_context,
            // Channel
            kk_channel_create,
            kk_channel_send,
            kk_channel_receive,
            kk_channel_close,
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
            // Cancellation (CORO-002)
            kk_coroutine_check_cancellation,
            kk_is_cancellation_exception,
            kk_job_cancel,
            kk_coroutine_cancel,
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
            kk_op_downTo,
            kk_op_step,
            // IntRange members (STDLIB-090/091/092/093)
            kk_range_first,
            kk_range_last,
            kk_range_count,
            kk_range_toList,
            kk_range_forEach,
            kk_range_map,
            kk_range_reversed,
        ]
        all += kPropertyStubExterns
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
            kk_custom_delegate_create,
            kk_custom_delegate_get_value,
            kk_custom_delegate_set_value,
        ]
        all += [
            // Bitwise/Shift (P5-103)
            kk_bitwise_and,
            kk_bitwise_or,
            kk_bitwise_xor,
            kk_op_inv,
            kk_op_shl,
            kk_op_shr,
            kk_op_ushr,
            kk_int_toString_radix,
        ]
        all += mathExterns
        all += collectionExterns
        all += sequenceExterns
        all += regexExterns
        all += comparatorExterns
        return all
    }()

    /// Look up an extern declaration by symbol name.
    public static func externDecl(named name: String) -> ExternDecl? {
        allExterns.first { $0.name == name }
    }
}

// swiftlint:enable type_body_length
