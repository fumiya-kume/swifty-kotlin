// Residual ABI specs not yet assigned to a categorized RuntimeABISpec section.
// Runtime-backed entries below are generated from Sources/Runtime exported C symbols.

public extension RuntimeABISpec {
    static let abiParityFunctions: [RuntimeABIFunctionSpec] = [
        // Compiler-reserved runtime ABI names without @_cdecl implementations yet.
        abiParitySpec("kk_result_mapCatching", parameters: [
            p("p0", .intptr),
            p("p1", .intptr),
            p("p2", .intptr),
            p("p3", .nullableIntptrPointer),
        ]),
        abiParitySpec("kk_result_flatMap", parameters: [
            p("p0", .intptr),
            p("p1", .intptr),
            p("p2", .intptr),
            p("p3", .nullableIntptrPointer),
        ]),
        abiParitySpec("kk_result_flatMapCatching", parameters: [
            p("p0", .intptr),
            p("p1", .intptr),
            p("p2", .intptr),
            p("p3", .nullableIntptrPointer),
        ]),
        abiParitySpec("kk_kclass_register_annotation", parameters: [
            p("p0", .intptr),
            p("p1", .intptr),
        ]),
        abiParitySpec("kk_kclass_has_annotation", parameters: [
            p("p0", .intptr),
            p("p1", .intptr),
        ]),
        abiParitySpec("kk_kclass_java", parameters: [
            p("kclassRaw", .intptr),
        ]),
        abiParitySpec("kk_kclass_js", parameters: [
            p("kclassRaw", .intptr),
        ]),
        abiParitySpec("kk_annotation_class_name", parameters: [
            p("p0", .intptr),
        ]),
        abiParitySpec("kk_annotation_simple_class_name", parameters: [
            p("p0", .intptr),
        ]),
        abiParitySpec("kk_annotation_get_arguments", parameters: [
            p("p0", .intptr),
        ]),
        abiParitySpec("kk_any_javaClass", parameters: [
            p("receiverRaw", .intptr),
        ]),
        abiParitySpec("kk_array_isArrayOf", parameters: [
            p("arrayRaw", .intptr),
        ]),
        abiParitySpec("kk_function_andThen", parameters: [
            p("functionRaw", .intptr),
            p("nextRaw", .intptr),
        ]),
        abiParitySpec("kk_function_compose", parameters: [
            p("functionRaw", .intptr),
            p("beforeRaw", .intptr),
        ]),
        abiParitySpec("kk_function_curried", parameters: [
            p("functionRaw", .intptr),
        ]),
        abiParitySpec("kk_future_getState", parameters: [
            p("futureRaw", .intptr),
        ]),
        abiParitySpec("kk_int_to_int", parameters: [
            p("value", .intptr),
        ]),
        abiParitySpec("kk_native_atomic_ref_create", parameters: [
            p("valueRaw", .intptr),
        ]),
        abiParitySpec("kk_native_atomic_ref_load", parameters: [
            p("refRaw", .intptr),
        ]),
        abiParitySpec("kk_native_atomic_ref_compareAndSwap", parameters: [
            p("refRaw", .intptr),
            p("expectedRaw", .intptr),
            p("newRaw", .intptr),
        ]),
        abiParitySpec("kk_native_atomic_ref_compareAndSet", parameters: [
            p("refRaw", .intptr),
            p("expectedRaw", .intptr),
            p("newRaw", .intptr),
        ]),
        abiParitySpec("kk_optional_getOrDefault", parameters: [
            p("optionalRaw", .intptr),
            p("defaultRaw", .intptr),
        ]),
        abiParitySpec("kk_optional_getOrNull", parameters: [
            p("optionalRaw", .intptr),
        ]),
        abiParitySpec("kk_optional_asSequence", parameters: [
            p("optionalRaw", .intptr),
        ]),
        abiParitySpec("kk_optional_getOrElse", parameters: [
            p("optionalRaw", .intptr),
            p("defaultValueRaw", .intptr),
        ]),
        abiParitySpec("kk_optional_toCollection", parameters: [
            p("optionalRaw", .intptr),
            p("collectionRaw", .intptr),
        ]),
        abiParitySpec("kk_kclass_javaClass", parameters: [
            p("kclassRaw", .intptr),
        ]),
        abiParitySpec("kk_kclass_javaPrimitiveType", parameters: [
            p("kclassRaw", .intptr),
        ]),
        abiParitySpec("kk_kclass_javaObjectType", parameters: [
            p("kclassRaw", .intptr),
        ]),
        abiParitySpec("kk_optional_toSet", parameters: [
            p("optionalRaw", .intptr),
        ]),

        // Runtime @_cdecl entries awaiting a dedicated RuntimeABISpec category.
        abiParitySpec("component1", parameters: [
            p("pairRaw", .intptr),
        ]),
        abiParitySpec("component2", parameters: [
            p("pairRaw", .intptr),
        ]),
        abiParitySpec("kk_adv_logger_add_async_appender", parameters: [
            p("loggerRaw", .intptr),
            p("appenderRaw", .intptr),
        ]),
        abiParitySpec("kk_adv_logger_add_file_appender", parameters: [
            p("loggerRaw", .intptr),
            p("appenderRaw", .intptr),
        ]),
        abiParitySpec("kk_adv_logger_add_rolling_appender", parameters: [
            p("loggerRaw", .intptr),
            p("appenderRaw", .intptr),
        ]),
        abiParitySpec("kk_adv_logger_add_structured_appender", parameters: [
            p("loggerRaw", .intptr),
            p("appenderRaw", .intptr),
        ]),
        abiParitySpec("kk_adv_logger_get", parameters: [
            p("nameRaw", .intptr),
        ]),
        abiParitySpec("kk_adv_logger_log", parameters: [
            p("loggerRaw", .intptr),
            p("levelRaw", .intptr),
            p("messageRaw", .intptr),
        ]),
        abiParitySpec("kk_adv_logger_log_throwable", parameters: [
            p("loggerRaw", .intptr),
            p("levelRaw", .intptr),
            p("messageRaw", .intptr),
            p("throwableRaw", .intptr),
        ]),
        abiParitySpec("kk_adv_logger_set_filter", parameters: [
            p("loggerRaw", .intptr),
            p("prefixRaw", .intptr),
        ]),
        abiParitySpec("kk_adv_logger_set_level", parameters: [
            p("loggerRaw", .intptr),
            p("levelRaw", .intptr),
        ]),
        abiParitySpec("kk_async_appender_wrap_file", parameters: [
            p("appenderRaw", .intptr),
        ]),
        abiParitySpec("kk_async_appender_wrap_rolling", parameters: [
            p("appenderRaw", .intptr),
        ]),
        abiParitySpec("kk_async_appender_wrap_structured", parameters: [
            p("appenderRaw", .intptr),
        ]),
        abiParitySpec("kk_atomic_ref_array_compareAndExchangeAt", parameters: [
            p("receiver", .intptr),
            p("index", .intptr),
            p("expect", .intptr),
            p("update", .intptr),
        ]),
        abiParitySpec("kk_atomic_ref_array_fetchAndUpdateAt", parameters: [
            p("receiver", .intptr),
            p("index", .intptr),
            p("updateFn", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("kk_atomic_ref_array_loadAt", parameters: [
            p("receiver", .intptr),
            p("index", .intptr),
        ]),
        abiParitySpec("kk_atomic_ref_array_new", parameters: [
            p("size", .intptr),
        ]),
        abiParitySpec("kk_atomic_ref_array_size", parameters: [
            p("receiver", .intptr),
        ]),
        abiParitySpec("kk_atomic_ref_array_storeAt", parameters: [
            p("receiver", .intptr),
            p("index", .intptr),
            p("value", .intptr),
        ]),
        abiParitySpec("kk_atomic_ref_array_updateAndFetchAt", parameters: [
            p("receiver", .intptr),
            p("index", .intptr),
            p("updateFn", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("kk_atomic_ref_array_updateAt", parameters: [
            p("receiver", .intptr),
            p("index", .intptr),
            p("updateFn", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("kk_biginteger_modInverse", parameters: [
            p("selfRaw", .intptr),
            p("modulusRaw", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("kk_biginteger_modPow", parameters: [
            p("selfRaw", .intptr),
            p("exponentRaw", .intptr),
            p("modulusRaw", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("kk_biginteger_not", parameters: [
            p("selfRaw", .intptr),
        ]),
        abiParitySpec("kk_biginteger_or", parameters: [
            p("selfRaw", .intptr),
            p("otherRaw", .intptr),
        ]),
        abiParitySpec("kk_biginteger_shiftLeft", parameters: [
            p("selfRaw", .intptr),
            p("n", .intptr),
        ]),
        abiParitySpec("kk_biginteger_shiftRight", parameters: [
            p("selfRaw", .intptr),
            p("n", .intptr),
        ]),
        abiParitySpec("kk_biginteger_toByteArray", parameters: [
            p("selfRaw", .intptr),
        ]),
        abiParitySpec("kk_biginteger_xor", parameters: [
            p("selfRaw", .intptr),
            p("otherRaw", .intptr),
        ]),
        abiParitySpec("kk_callable_ref_arity", parameters: [
            p("tagged", .intptr),
        ]),
        abiParitySpec("kk_callable_ref_call_0", parameters: [
            p("tagged", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("kk_callable_ref_call_1", parameters: [
            p("tagged", .intptr),
            p("arg", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("kk_callable_ref_call_2", parameters: [
            p("tagged", .intptr),
            p("arg1", .intptr),
            p("arg2", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("kk_callable_ref_call_3", parameters: [
            p("tagged", .intptr),
            p("arg1", .intptr),
            p("arg2", .intptr),
            p("arg3", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("kk_callable_ref_is_suspend", parameters: [
            p("tagged", .intptr),
        ]),
        abiParitySpec("kk_callable_ref_parameters", parameters: [
            p("tagged", .intptr),
        ]),
        abiParitySpec("kk_callback_flow_await_close", parameters: [
            p("channelRaw", .intptr),
            p("closeHandlerFnPtr", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("kk_callback_flow_create", parameters: [
            p("emitterFnPtr", .intptr),
            p("arg1", .intptr),
        ]),
        abiParitySpec("kk_channel_flow_create", parameters: [
            p("emitterFnPtr", .intptr),
            p("arg1", .intptr),
        ]),
        abiParitySpec("kk_channel_flow_send", parameters: [
            p("channelRaw", .intptr),
            p("value", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("kk_channel_flow_try_send", parameters: [
            p("channelRaw", .intptr),
            p("value", .intptr),
        ]),
        abiParitySpec("kk_channel_is_closed_for_receive", parameters: [
            p("handle", .intptr),
        ]),
        abiParitySpec("kk_channel_is_closed_for_send", parameters: [
            p("handle", .intptr),
        ]),
        abiParitySpec("kk_channel_iterator", parameters: [
            p("handle", .intptr),
        ]),
        abiParitySpec("kk_channel_iterator_hasNext", parameters: [
            p("iterHandle", .intptr),
        ]),
        abiParitySpec("kk_channel_iterator_next", parameters: [
            p("iterHandle", .intptr),
        ]),
        abiParitySpec("kk_channel_send_suspending", parameters: [
            p("handle", .intptr),
            p("value", .intptr),
            p("continuation", .intptr),
        ]),
        abiParitySpec("kk_char_digitToChar_radix", parameters: [
            p("digit", .intptr),
            p("radix", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("kk_char_digitToInt_radix", parameters: [
            p("value", .intptr),
            p("radix", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("kk_char_fromCode", parameters: [
            p("code", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("kk_char_isHighSurrogate", parameters: [
            p("value", .intptr),
        ]),
        abiParitySpec("kk_char_isISOControl", parameters: [
            p("value", .intptr),
        ]),
        abiParitySpec("kk_char_isLowSurrogate", parameters: [
            p("value", .intptr),
        ]),
        abiParitySpec("kk_char_isSurrogate", parameters: [
            p("value", .intptr),
        ]),
        abiParitySpec("kk_char_isTitleCase", parameters: [
            p("value", .intptr),
        ]),
        abiParitySpec("kk_check_not_null", parameters: [
            p("value", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("kk_check_not_null_lazy", parameters: [
            p("value", .intptr),
            p("fnPtr", .intptr),
            p("closureRaw", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("kk_cname_lookup", parameters: [
            p("externNameRaw", .intptr),
        ]),
        abiParitySpec("kk_cname_register", parameters: [
            p("externNameRaw", .intptr),
            p("fnPtr", .intptr),
        ]),
        abiParitySpec("kk_copaque_pointer_address", parameters: [
            p("handle", .intptr),
        ]),
        abiParitySpec("kk_copaque_pointer_new", parameters: [
            p("address", .intptr),
        ]),
        abiParitySpec("kk_coroutine_continuation_context", parameters: [
            p("continuation", .intptr),
        ]),
        abiParitySpec("kk_coroutine_continuation_resume", parameters: [
            p("continuation", .intptr),
            p("value", .intptr),
        ], returnType: .void),
        abiParitySpec("kk_coroutine_continuation_resume_with", parameters: [
            p("continuation", .intptr),
            p("resultRaw", .intptr),
        ], returnType: .void),
        abiParitySpec("kk_coroutine_continuation_resume_with_exception", parameters: [
            p("continuation", .intptr),
            p("exception", .intptr),
        ], returnType: .void),
        abiParitySpec("kk_cpointer_address", parameters: [
            p("handle", .intptr),
        ]),
        abiParitySpec("kk_cpointer_new", parameters: [
            p("address", .intptr),
        ]),
        abiParitySpec("kk_decimalformat_formatDouble", parameters: [
            p("formatRaw", .intptr),
            p("value", .double),
        ]),
        abiParitySpec("kk_decimalformat_formatFloat", parameters: [
            p("formatRaw", .intptr),
            p("value", .float),
        ]),
        abiParitySpec("kk_decimalformat_formatInt", parameters: [
            p("formatRaw", .intptr),
            p("value", .intptr),
        ]),
        abiParitySpec("kk_decimalformat_formatLong", parameters: [
            p("formatRaw", .intptr),
            p("value", .intptr),
        ]),
        abiParitySpec("kk_decimalformat_getDecimalSeparator", parameters: [
            p("formatRaw", .intptr),
        ]),
        abiParitySpec("kk_decimalformat_getGroupingSeparator", parameters: [
            p("formatRaw", .intptr),
        ]),
        abiParitySpec("kk_decimalformat_new", parameters: [
            p("patternRaw", .intptr),
        ]),
        abiParitySpec("kk_decimalformat_newWithLocale", parameters: [
            p("patternRaw", .intptr),
            p("localeRaw", .intptr),
        ]),
        abiParitySpec("kk_decimalformat_parse", parameters: [
            p("formatRaw", .intptr),
            p("stringRaw", .intptr),
        ]),
        abiParitySpec("kk_file_appender_new", parameters: [
            p("pathRaw", .intptr),
        ]),
        abiParitySpec("kk_files_copy", parameters: [
            p("filesRaw", .intptr),
            p("sourceRaw", .intptr),
            p("targetRaw", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("kk_files_createDirectories", parameters: [
            p("filesRaw", .intptr),
            p("pathRaw", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("kk_files_createDirectory", parameters: [
            p("filesRaw", .intptr),
            p("pathRaw", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("kk_files_createFile", parameters: [
            p("filesRaw", .intptr),
            p("pathRaw", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("kk_files_createTempDirectory", parameters: [
            p("filesRaw", .intptr),
            p("prefixRaw", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("kk_files_createTempFile", parameters: [
            p("filesRaw", .intptr),
            p("prefixRaw", .intptr),
            p("suffixRaw", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("kk_files_delete", parameters: [
            p("filesRaw", .intptr),
            p("pathRaw", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("kk_files_exists", parameters: [
            p("filesRaw", .intptr),
            p("pathRaw", .intptr),
        ]),
        abiParitySpec("kk_files_getLastModifiedTime", parameters: [
            p("filesRaw", .intptr),
            p("pathRaw", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("kk_files_isDirectory", parameters: [
            p("filesRaw", .intptr),
            p("pathRaw", .intptr),
        ]),
        abiParitySpec("kk_files_isRegularFile", parameters: [
            p("filesRaw", .intptr),
            p("pathRaw", .intptr),
        ]),
        abiParitySpec("kk_files_list", parameters: [
            p("filesRaw", .intptr),
            p("pathRaw", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("kk_files_move", parameters: [
            p("filesRaw", .intptr),
            p("sourceRaw", .intptr),
            p("targetRaw", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("kk_files_newDirectoryStream", parameters: [
            p("filesRaw", .intptr),
            p("pathRaw", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("kk_files_size", parameters: [
            p("filesRaw", .intptr),
            p("pathRaw", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("kk_files_walk", parameters: [
            p("filesRaw", .intptr),
            p("pathRaw", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("kk_fileTime_toMillis", parameters: [
            p("fileTimeRaw", .intptr),
        ]),
        abiParitySpec("kk_flow_catch", parameters: [
            p("flowHandle", .intptr),
            p("handlerFnPtr", .intptr),
            p("arg2", .intptr),
        ]),
        abiParitySpec("kk_flow_emit_with_timestamp", parameters: [
            p("flowHandle", .intptr),
            p("value", .intptr),
            p("tag", .intptr),
            p("timestamp", .uint64),
        ]),
        abiParitySpec("kk_flow_on_completion", parameters: [
            p("flowHandle", .intptr),
            p("handlerFnPtr", .intptr),
            p("arg2", .intptr),
        ]),
        abiParitySpec("kk_flow_on_error_resume", parameters: [
            p("flowHandle", .intptr),
            p("fallbackFlowHandle", .intptr),
            p("arg2", .intptr),
        ]),
        abiParitySpec("kk_flow_on_error_return", parameters: [
            p("flowHandle", .intptr),
            p("fallbackValue", .intptr),
            p("arg2", .intptr),
        ]),
        abiParitySpec("kk_flow_retry", parameters: [
            p("flowHandle", .intptr),
            p("retries", .intptr),
            p("arg2", .intptr),
        ]),
        abiParitySpec("kk_flow_retry_when", parameters: [
            p("flowHandle", .intptr),
            p("predicateFnPtr", .intptr),
            p("arg2", .intptr),
        ]),
        abiParitySpec("kk_flow_share_in", parameters: [
            p("flowHandle", .intptr),
            p("replay", .intptr),
        ]),
        abiParitySpec("kk_flow_state_in", parameters: [
            p("flowHandle", .intptr),
            p("initialValue", .intptr),
        ]),
        abiParitySpec("kk_freezable_atomic_ref_compareAndSet", parameters: [
            p("refHandle", .intptr),
            p("expectedRaw", .intptr),
            p("newRaw", .intptr),
        ]),
        abiParitySpec("kk_freezable_atomic_ref_compareAndSwap", parameters: [
            p("refHandle", .intptr),
            p("expectedRaw", .intptr),
            p("newRaw", .intptr),
        ]),
        abiParitySpec("kk_freezable_atomic_ref_create", parameters: [
            p("initialRaw", .intptr),
        ]),
        abiParitySpec("kk_freezable_atomic_ref_is_frozen", parameters: [
            p("refHandle", .intptr),
        ]),
        abiParitySpec("kk_freezable_atomic_ref_load", parameters: [
            p("refHandle", .intptr),
        ]),
        abiParitySpec("kk_freezable_atomic_ref_store", parameters: [
            p("refHandle", .intptr),
            p("valueRaw", .intptr),
        ]),
        abiParitySpec("kk_freeze_object", parameters: [
            p("objectRaw", .intptr),
        ]),
        abiParitySpec("kk_future_complete", parameters: [
            p("futureHandle", .intptr),
            p("valueRaw", .intptr),
        ]),
        abiParitySpec("kk_future_consume", parameters: [
            p("futureHandle", .intptr),
        ]),
        abiParitySpec("kk_future_is_ready", parameters: [
            p("futureHandle", .intptr),
        ]),
        abiParitySpec("kk_future_new"),
        abiParitySpec("kk_future_result", parameters: [
            p("futureHandle", .intptr),
        ]),
        abiParitySpec("kk_hexformat_prefix", parameters: [
            p("formatRaw", .intptr),
            p("prefixRaw", .intptr),
        ]),
        abiParitySpec("kk_hexformat_suffix", parameters: [
            p("formatRaw", .intptr),
            p("suffixRaw", .intptr),
        ]),
        abiParitySpec("kk_http_body_handlers_ofString", parameters: [
            p("bodyHandlersRaw", .intptr),
        ]),
        abiParitySpec("kk_http_body_publishers_noBody", parameters: [
            p("bodyPublishersRaw", .intptr),
        ]),
        abiParitySpec("kk_http_body_publishers_ofString", parameters: [
            p("bodyPublishersRaw", .intptr),
            p("bodyRaw", .intptr),
        ]),
        abiParitySpec("kk_http_client_newHttpClient"),
        abiParitySpec("kk_http_client_send", parameters: [
            p("clientRaw", .intptr),
            p("requestRaw", .intptr),
            p("bodyHandlerRaw", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("kk_http_headers_firstValue", parameters: [
            p("headersRaw", .intptr),
            p("nameRaw", .intptr),
        ]),
        abiParitySpec("kk_http_headers_map", parameters: [
            p("headersRaw", .intptr),
        ]),
        abiParitySpec("kk_http_request_builder_build", parameters: [
            p("builderRaw", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("kk_http_request_builder_GET", parameters: [
            p("builderRaw", .intptr),
        ]),
        abiParitySpec("kk_http_request_builder_header", parameters: [
            p("builderRaw", .intptr),
            p("nameRaw", .intptr),
            p("valueRaw", .intptr),
        ]),
        abiParitySpec("kk_http_request_builder_POST", parameters: [
            p("builderRaw", .intptr),
            p("publisherRaw", .intptr),
        ]),
        abiParitySpec("kk_http_request_builder_uri", parameters: [
            p("builderRaw", .intptr),
            p("uriRaw", .intptr),
        ]),
        abiParitySpec("kk_http_request_newBuilder"),
        abiParitySpec("kk_http_request_newBuilder_uri", parameters: [
            p("uriRaw", .intptr),
        ]),
        abiParitySpec("kk_http_response_headers", parameters: [
            p("responseRaw", .intptr),
        ]),
        abiParitySpec("kk_input_stream_mark", parameters: [
            p("streamRaw", .intptr),
            p("readLimitRaw", .intptr),
        ]),
        abiParitySpec("kk_input_stream_mark_supported", parameters: [
            p("streamRaw", .intptr),
        ]),
        abiParitySpec("kk_input_stream_reset", parameters: [
            p("streamRaw", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("kk_io_createTempDir", parameters: [
            p("prefixRaw", .intptr),
            p("suffixRaw", .intptr),
            p("directoryRaw", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("kk_io_createTempDir_default", parameters: [
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("kk_io_createTempDir_prefix", parameters: [
            p("prefixRaw", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("kk_io_createTempDir_prefix_suffix", parameters: [
            p("prefixRaw", .intptr),
            p("suffixRaw", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("kk_io_createTempFile", parameters: [
            p("prefixRaw", .intptr),
            p("suffixRaw", .intptr),
            p("directoryRaw", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("kk_io_createTempFile_default", parameters: [
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("kk_io_createTempFile_prefix", parameters: [
            p("prefixRaw", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("kk_io_createTempFile_prefix_suffix", parameters: [
            p("prefixRaw", .intptr),
            p("suffixRaw", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("kk_is_frozen", parameters: [
            p("objectRaw", .intptr),
        ]),
        abiParitySpec("kk_iterator_hasNext", parameters: [
            p("iterRaw", .intptr),
        ]),
        abiParitySpec("kk_iterator_next", parameters: [
            p("iterRaw", .intptr),
        ]),
        abiParitySpec("kk_kclass_is_final", parameters: [
            p("kclassRaw", .intptr),
        ]),
        abiParitySpec("kk_kclass_is_open", parameters: [
            p("kclassRaw", .intptr),
        ]),
        abiParitySpec("kk_kclass_register_member", parameters: [
            p("kclassRaw", .intptr),
            p("memberRaw", .intptr),
        ]),
        abiParitySpec("kk_kclass_register_metadata_v2", parameters: [
            p("typeToken", .intptr),
            p("qualifiedNameRaw", .intptr),
            p("simpleNameRaw", .intptr),
            p("supertypeNameRaw", .intptr),
            p("flags", .intptr),
            p("fieldCount", .intptr),
            p("memberCount", .intptr),
            p("constructorCount", .intptr),
            p("visibilityRaw", .intptr),
            p("typeParameterCount", .intptr),
        ]),
        abiParitySpec("kk_kclass_supertypes", parameters: [
            p("kclassRaw", .intptr),
        ]),
        abiParitySpec("kk_kclass_type_parameters", parameters: [
            p("kclassRaw", .intptr),
        ]),
        abiParitySpec("kk_kclass_visibility", parameters: [
            p("kclassRaw", .intptr),
        ]),
        abiParitySpec("kk_list_dropLast", parameters: [
            p("listRaw", .intptr),
            p("count", .intptr),
        ]),
        abiParitySpec("kk_list_elementAt", parameters: [
            p("listRaw", .intptr),
            p("index", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("kk_list_elementAtOrElse", parameters: [
            p("listRaw", .intptr),
            p("index", .intptr),
            p("fnPtr", .intptr),
            p("closureRaw", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("kk_list_foldRight", parameters: [
            p("listRaw", .intptr),
            p("initial", .intptr),
            p("fnPtr", .intptr),
            p("closureRaw", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("kk_list_foldRightIndexed", parameters: [
            p("listRaw", .intptr),
            p("initial", .intptr),
            p("fnPtr", .intptr),
            p("closureRaw", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("kk_list_reduceRight", parameters: [
            p("listRaw", .intptr),
            p("fnPtr", .intptr),
            p("closureRaw", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("kk_list_toByteArray", parameters: [
            p("listRaw", .intptr),
        ]),
        abiParitySpec("kk_long_range_average", parameters: [
            p("rangeRaw", .intptr),
        ]),
        abiParitySpec("kk_long_range_drop", parameters: [
            p("rangeRaw", .intptr),
            p("n", .intptr),
        ]),
        abiParitySpec("kk_long_range_sorted", parameters: [
            p("rangeRaw", .intptr),
        ]),
        abiParitySpec("kk_long_range_take", parameters: [
            p("rangeRaw", .intptr),
            p("n", .intptr),
        ]),
        abiParitySpec("kk_map_entry_to_pair", parameters: [
            p("entryRaw", .intptr),
        ]),
        abiParitySpec("kk_match_group_collection_get_at", parameters: [
            p("collectionRaw", .intptr),
            p("index", .intptr),
        ]),
        abiParitySpec("kk_match_result_component1", parameters: [
            p("matchRaw", .intptr),
        ]),
        abiParitySpec("kk_match_result_component2", parameters: [
            p("matchRaw", .intptr),
        ]),
        abiParitySpec("kk_match_result_next", parameters: [
            p("matchRaw", .intptr),
        ]),
        abiParitySpec("kk_match_result_range", parameters: [
            p("matchRaw", .intptr),
        ]),
        abiParitySpec("kk_math_e"),
        abiParitySpec("kk_math_pi"),
        abiParitySpec("kk_mdc_clear"),
        abiParitySpec("kk_mdc_get", parameters: [
            p("keyRaw", .intptr),
        ]),
        abiParitySpec("kk_mdc_put", parameters: [
            p("keyRaw", .intptr),
            p("valueRaw", .intptr),
        ]),
        abiParitySpec("kk_mdc_remove", parameters: [
            p("keyRaw", .intptr),
        ]),
        abiParitySpec("kk_mem_scope_alloc", parameters: [
            p("scopeHandle", .intptr),
            p("byteCount", .intptr),
        ]),
        abiParitySpec("kk_mem_scope_enter"),
        abiParitySpec("kk_mem_scope_exit", parameters: [
            p("handle", .intptr),
        ]),
        abiParitySpec("kk_mutable_shared_flow_create", parameters: [
            p("replay", .intptr),
        ]),
        abiParitySpec("kk_mutable_shared_flow_emit", parameters: [
            p("handle", .intptr),
            p("value", .intptr),
        ]),
        abiParitySpec("kk_mutable_shared_flow_try_emit", parameters: [
            p("handle", .intptr),
            p("value", .intptr),
        ]),
        abiParitySpec("kk_mutable_state_flow_create", parameters: [
            p("initialValue", .intptr),
        ]),
        abiParitySpec("kk_mutable_state_flow_emit", parameters: [
            p("handle", .intptr),
            p("value", .intptr),
        ]),
        abiParitySpec("kk_mutable_state_flow_try_emit", parameters: [
            p("handle", .intptr),
            p("value", .intptr),
        ]),
        abiParitySpec("kk_native_alloc_bytes", parameters: [
            p("byteCount", .intptr),
        ]),
        abiParitySpec("kk_native_heap_alloc", parameters: [
            p("byteCount", .intptr),
        ]),
        abiParitySpec("kk_native_heap_free", parameters: [
            p("handle", .intptr),
        ]),
        abiParitySpec("kk_normalization_form_nfc"),
        abiParitySpec("kk_normalization_form_nfd"),
        abiParitySpec("kk_normalization_form_nfkc"),
        abiParitySpec("kk_normalization_form_nfkd"),
        abiParitySpec("kk_numberformat_getDecimalSeparator", parameters: [
            p("formatRaw", .intptr),
        ]),
        abiParitySpec("kk_numberformat_getGroupingSeparator", parameters: [
            p("formatRaw", .intptr),
        ]),
        abiParitySpec("kk_numberformat_parse", parameters: [
            p("formatRaw", .intptr),
            p("stringRaw", .intptr),
        ]),
        abiParitySpec("kk_numberformat_setGroupingUsed", parameters: [
            p("formatRaw", .intptr),
            p("used", .intptr),
        ]),
        abiParitySpec("kk_numberformat_setMaximumFractionDigits", parameters: [
            p("formatRaw", .intptr),
            p("digits", .intptr),
        ]),
        abiParitySpec("kk_numberformat_setMinimumFractionDigits", parameters: [
            p("formatRaw", .intptr),
            p("digits", .intptr),
        ]),
        abiParitySpec("kk_pin_object", parameters: [
            p("objectRaw", .intptr),
        ]),
        abiParitySpec("kk_pinned_get", parameters: [
            p("pinnedHandle", .intptr),
        ]),
        abiParitySpec("kk_range_average", parameters: [
            p("rangeRaw", .intptr),
        ]),
        abiParitySpec("kk_range_contains", parameters: [
            p("rangeRaw", .intptr),
            p("value", .intptr),
        ]),
        abiParitySpec("kk_range_drop", parameters: [
            p("rangeRaw", .intptr),
            p("n", .intptr),
        ]),
        abiParitySpec("kk_range_end", parameters: [
            p("rangeRaw", .intptr),
        ]),
        abiParitySpec("kk_range_sorted", parameters: [
            p("rangeRaw", .intptr),
        ]),
        abiParitySpec("kk_range_take", parameters: [
            p("rangeRaw", .intptr),
            p("n", .intptr),
        ]),
        abiParitySpec("kk_regex_matches", parameters: [
            p("regexRaw", .intptr),
            p("inputRaw", .intptr),
        ]),
        abiParitySpec("kk_require_not_null", parameters: [
            p("value", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("kk_require_not_null_lazy", parameters: [
            p("value", .intptr),
            p("fnPtr", .intptr),
            p("closureRaw", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("kk_rolling_appender_new", parameters: [
            p("pathRaw", .intptr),
            p("maxBytes", .intptr),
            p("maxFiles", .intptr),
        ]),
        abiParitySpec("kk_sequence_input_stream_available", parameters: [
            p("streamRaw", .intptr),
        ]),
        abiParitySpec("kk_sequence_input_stream_close", parameters: [
            p("streamRaw", .intptr),
        ]),
        abiParitySpec("kk_sequence_input_stream_new", parameters: [
            p("firstRaw", .intptr),
            p("secondRaw", .intptr),
        ]),
        abiParitySpec("kk_sequence_input_stream_read", parameters: [
            p("streamRaw", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("kk_sequence_zipWithNext", parameters: [
            p("seqRaw", .intptr),
        ]),
        abiParitySpec("kk_sequence_zipWithNextTransform", parameters: [
            p("seqRaw", .intptr),
            p("fnPtr", .intptr),
            p("closureRaw", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("kk_set_maxOrNull", parameters: [
            p("setRaw", .intptr),
        ]),
        abiParitySpec("kk_set_minOrNull", parameters: [
            p("setRaw", .intptr),
        ]),
        abiParitySpec("kk_set_toList", parameters: [
            p("setRaw", .intptr),
        ]),
        abiParitySpec("kk_shared_flow_collect", parameters: [
            p("handle", .intptr),
            p("collectorFnPtr", .intptr),
            p("closureRaw", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("kk_shared_flow_replay_cache", parameters: [
            p("handle", .intptr),
        ]),
        abiParitySpec("kk_shared_immutable_init", parameters: [
            p("objectRaw", .intptr),
        ]),
        abiParitySpec("kk_slf4j_is_debug_enabled", parameters: [
            p("loggerRaw", .intptr),
        ]),
        abiParitySpec("kk_slf4j_is_error_enabled", parameters: [
            p("loggerRaw", .intptr),
        ]),
        abiParitySpec("kk_slf4j_is_info_enabled", parameters: [
            p("loggerRaw", .intptr),
        ]),
        abiParitySpec("kk_slf4j_is_trace_enabled", parameters: [
            p("loggerRaw", .intptr),
        ]),
        abiParitySpec("kk_slf4j_is_warn_enabled", parameters: [
            p("loggerRaw", .intptr),
        ]),
        abiParitySpec("kk_slf4j_log_debug", parameters: [
            p("loggerRaw", .intptr),
            p("messageRaw", .intptr),
        ]),
        abiParitySpec("kk_slf4j_log_debug_1", parameters: [
            p("loggerRaw", .intptr),
            p("patternRaw", .intptr),
            p("arg0Raw", .intptr),
        ]),
        abiParitySpec("kk_slf4j_log_error", parameters: [
            p("loggerRaw", .intptr),
            p("messageRaw", .intptr),
        ]),
        abiParitySpec("kk_slf4j_log_error_1", parameters: [
            p("loggerRaw", .intptr),
            p("patternRaw", .intptr),
            p("arg0Raw", .intptr),
        ]),
        abiParitySpec("kk_slf4j_log_error_2", parameters: [
            p("loggerRaw", .intptr),
            p("patternRaw", .intptr),
            p("arg0Raw", .intptr),
            p("arg1Raw", .intptr),
        ]),
        abiParitySpec("kk_slf4j_log_info", parameters: [
            p("loggerRaw", .intptr),
            p("messageRaw", .intptr),
        ]),
        abiParitySpec("kk_slf4j_log_info_1", parameters: [
            p("loggerRaw", .intptr),
            p("patternRaw", .intptr),
            p("arg0Raw", .intptr),
        ]),
        abiParitySpec("kk_slf4j_log_info_2", parameters: [
            p("loggerRaw", .intptr),
            p("patternRaw", .intptr),
            p("arg0Raw", .intptr),
            p("arg1Raw", .intptr),
        ]),
        abiParitySpec("kk_slf4j_log_trace", parameters: [
            p("loggerRaw", .intptr),
            p("messageRaw", .intptr),
        ]),
        abiParitySpec("kk_slf4j_log_trace_1", parameters: [
            p("loggerRaw", .intptr),
            p("patternRaw", .intptr),
            p("arg0Raw", .intptr),
        ]),
        abiParitySpec("kk_slf4j_log_warn", parameters: [
            p("loggerRaw", .intptr),
            p("messageRaw", .intptr),
        ]),
        abiParitySpec("kk_slf4j_log_warn_1", parameters: [
            p("loggerRaw", .intptr),
            p("patternRaw", .intptr),
            p("arg0Raw", .intptr),
        ]),
        abiParitySpec("kk_slf4j_log_warn_2", parameters: [
            p("loggerRaw", .intptr),
            p("patternRaw", .intptr),
            p("arg0Raw", .intptr),
            p("arg1Raw", .intptr),
        ]),
        abiParitySpec("kk_slf4j_logger_get", parameters: [
            p("nameRaw", .intptr),
        ]),
        abiParitySpec("kk_slf4j_set_level", parameters: [
            p("loggerRaw", .intptr),
            p("levelRaw", .intptr),
        ]),
        abiParitySpec("kk_state_flow_value", parameters: [
            p("handle", .intptr),
        ]),
        abiParitySpec("kk_string_contentEquals", parameters: [
            p("receiverRaw", .intptr),
            p("otherRaw", .intptr),
        ]),
        abiParitySpec("kk_string_contentEquals_ignoreCase", parameters: [
            p("receiverRaw", .intptr),
            p("otherRaw", .intptr),
            p("ignoreCaseRaw", .intptr),
        ]),
        abiParitySpec("kk_string_getOrNull", parameters: [
            p("strRaw", .intptr),
            p("index", .intptr),
        ]),
        abiParitySpec("kk_string_isNormalized", parameters: [
            p("strRaw", .intptr),
            p("formTagRaw", .intptr),
        ]),
        abiParitySpec("kk_string_normalize", parameters: [
            p("strRaw", .intptr),
            p("formTagRaw", .intptr),
        ]),
        abiParitySpec("kk_string_partition", parameters: [
            p("strRaw", .intptr),
            p("fnPtr", .intptr),
            p("closureRaw", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("kk_string_subSequence", parameters: [
            p("strRaw", .intptr),
            p("startRaw", .intptr),
            p("endRaw", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("kk_string_toBigInteger", parameters: [
            p("strRaw", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("kk_string_toBooleanStrictOrNull", parameters: [
            p("strRaw", .intptr),
        ]),
        abiParitySpec("kk_string_toByte", parameters: [
            p("strRaw", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("kk_string_toByteOrNull", parameters: [
            p("strRaw", .intptr),
        ]),
        abiParitySpec("kk_string_toShort", parameters: [
            p("strRaw", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("kk_string_toShortOrNull", parameters: [
            p("strRaw", .intptr),
        ]),
        abiParitySpec("kk_structured_appender_new", parameters: [
            p("pathRaw", .intptr),
        ]),
        abiParitySpec("kk_suspend_coroutine", parameters: [
            p("fnPtr", .intptr),
            p("closureRaw", .intptr),
            p("continuation", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("kk_transfer_object", parameters: [
            p("objectRaw", .intptr),
            p("modeRaw", .intptr),
        ]),
        abiParitySpec("kk_uint_range_average", parameters: [
            p("rangeRaw", .intptr),
        ]),
        abiParitySpec("kk_uint_range_drop", parameters: [
            p("rangeRaw", .intptr),
            p("n", .intptr),
        ]),
        abiParitySpec("kk_uint_range_sorted", parameters: [
            p("rangeRaw", .intptr),
        ]),
        abiParitySpec("kk_uint_range_take", parameters: [
            p("rangeRaw", .intptr),
            p("n", .intptr),
        ]),
        abiParitySpec("kk_ulong_range_average", parameters: [
            p("rangeRaw", .intptr),
        ]),
        abiParitySpec("kk_ulong_range_drop", parameters: [
            p("rangeRaw", .intptr),
            p("n", .intptr),
        ]),
        abiParitySpec("kk_ulong_range_sorted", parameters: [
            p("rangeRaw", .intptr),
        ]),
        abiParitySpec("kk_ulong_range_take", parameters: [
            p("rangeRaw", .intptr),
            p("n", .intptr),
        ]),
        abiParitySpec("kk_unpin_object", parameters: [
            p("pinnedHandle", .intptr),
        ]),
        abiParitySpec("kk_worker_execute", parameters: [
            p("workerHandle", .intptr),
            p("modeRaw", .intptr),
            p("producerFnPtr", .intptr),
            p("producerClosureRaw", .intptr),
            p("jobFnPtr", .intptr),
            p("jobClosureRaw", .intptr),
        ]),
        abiParitySpec("kk_worker_execute_after", parameters: [
            p("workerHandle", .intptr),
            p("delayNs", .intptr),
            p("fnPtr", .intptr),
            p("closureRaw", .intptr),
        ]),
        abiParitySpec("kk_worker_id", parameters: [
            p("workerHandle", .intptr),
        ]),
        abiParitySpec("kk_worker_is_terminated", parameters: [
            p("workerHandle", .intptr),
        ]),
        abiParitySpec("kk_worker_name", parameters: [
            p("workerHandle", .intptr),
        ]),
        abiParitySpec("kk_worker_new", parameters: [
            p("nameRaw", .intptr),
        ]),
        abiParitySpec("kk_worker_request_termination", parameters: [
            p("workerHandle", .intptr),
            p("processScheduledRaw", .intptr),
        ]),
    ]
}

private func abiParitySpec(
    _ name: String,
    parameters: [RuntimeABIParameter] = [],
    returnType: RuntimeABICType = .intptr
) -> RuntimeABIFunctionSpec {
    RuntimeABIFunctionSpec(
        name: name,
        parameters: parameters,
        returnType: returnType,
        section: "ABIParity"
    )
}

private func p(_ name: String, _ type: RuntimeABICType) -> RuntimeABIParameter {
    RuntimeABIParameter(name: name, type: type)
}
