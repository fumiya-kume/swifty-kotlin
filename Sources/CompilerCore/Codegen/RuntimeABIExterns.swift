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
    public static let specVersion = "J16.1"

    /// A single extern function declaration for the C preamble.
    public struct ExternDecl: Equatable {
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
            let params: String
            if parameterTypes.isEmpty {
                params = "void"
            } else {
                params = parameterTypes.joined(separator: ", ")
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

    public static let kk_panic = ExternDecl(
        name: "kk_panic",
        parameterTypes: ["const char *"],
        returnType: "_Noreturn void"
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

    // MARK: - Array

    public static let kk_array_new = ExternDecl(
        name: "kk_array_new",
        parameterTypes: ["intptr_t"],
        returnType: "intptr_t"
    )

    public static let kk_array_get = ExternDecl(
        name: "kk_array_get",
        parameterTypes: ["intptr_t", "intptr_t", "intptr_t * _Nullable"],
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
        kk_panic,
        // String
        kk_string_from_utf8,
        kk_string_concat,
        kk_string_compareTo,
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
        // Flow
        kk_flow_create,
        kk_flow_emit,
        kk_flow_collect,
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
        // Boxing
        kk_box_int,
        kk_box_bool,
        kk_unbox_int,
        kk_unbox_bool,
        // Array
        kk_array_new,
        kk_array_get,
        kk_array_set,
        kk_vararg_spread_concat,
        // Range/Progression
        kk_op_rangeTo,
        kk_op_rangeUntil,
        kk_op_downTo,
        kk_op_step,
        // Delegate
        kk_lazy_create,
        kk_lazy_get_value,
        kk_observable_create,
        kk_observable_get_value,
        kk_observable_set_value,
        kk_vetoable_create,
        kk_vetoable_get_value,
        kk_vetoable_set_value,
    ]

    /// Look up an extern declaration by symbol name.
    public static func externDecl(named name: String) -> ExternDecl? {
        allExterns.first { $0.name == name }
    }
}
