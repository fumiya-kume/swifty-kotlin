// swiftlint:disable file_length

/// `RuntimeABISpec.coroutineFunctions` extracted from `RuntimeABISpec.swift`.
public extension RuntimeABISpec {
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
            name: "kk_coroutine_current_context",
            parameters: [],
            returnType: .intptr,
            section: "Coroutine"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_coroutine_continuation_factory",
            parameters: [
                RuntimeABIParameter(name: "contextRaw", type: .intptr),
                RuntimeABIParameter(name: "resumeWithRaw", type: .intptr),
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
}
