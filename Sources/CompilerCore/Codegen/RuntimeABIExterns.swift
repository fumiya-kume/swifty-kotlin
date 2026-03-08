// swiftlint:disable file_length type_body_length
// swiftlint:disable identifier_name
import Foundation

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
    public static let specVersion = "J21"

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

    public static let kk_string_toDouble = ExternDecl(
        name: "kk_string_toDouble",
        parameterTypes: ["intptr_t", "intptr_t * _Nullable"],
        returnType: "intptr_t"
    )

    // MARK: - Println

    public static let kk_println_any = ExternDecl(
        name: "kk_println_any",
        parameterTypes: ["void * _Nullable"],
        returnType: "void"
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

    // MARK: - All Functions (canonical list)

    /// All runtime extern declarations, ordered by section.
    /// This is the authoritative list that must match `RuntimeABISpec.allFunctions`.
    public static let allExterns: [ExternDecl] = [
        // Memory
        kk_alloc,
        kk_gc_collect,
        kk_write_barrier,
        // Exception
        kk_throwable_new,
        kk_throwable_is_cancellation,
        kk_panic,
        kk_abort_unreachable,
        // String
        kk_string_from_utf8,
        kk_string_concat,
        kk_string_compareTo,
        kk_compare_any,
        kk_string_length,
        kk_string_trim,
        kk_string_format,
        kk_string_isNullOrEmpty,
        kk_string_isNullOrBlank,
        kk_string_startsWith,
        kk_string_endsWith,
        kk_string_contains_str,
        kk_string_replace,
        kk_string_split,
        kk_string_toInt,
        kk_string_toDouble,
        // Println
        kk_println_any,
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
        kk_type_token_simple_name,
        kk_type_token_qualified_name,
        kk_op_is,
        kk_op_cast,
        kk_op_safe_cast,
        kk_op_contains,
        // Range/Progression
        kk_op_rangeTo,
        kk_op_rangeUntil,
        kk_op_downTo,
        kk_op_step,
    ] + kPropertyStubExterns + [
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
        // Bitwise/Shift (P5-103)
        kk_bitwise_and,
        kk_bitwise_or,
        kk_bitwise_xor,
        kk_op_inv,
        kk_op_shl,
        kk_op_shr,
        kk_op_ushr,
        kk_int_toString_radix,
    ] + collectionExterns + sequenceExterns

    /// Look up an extern declaration by symbol name.
    public static func externDecl(named name: String) -> ExternDecl? {
        allExterns.first { $0.name == name }
    }
}

// swiftlint:enable file_length type_body_length
