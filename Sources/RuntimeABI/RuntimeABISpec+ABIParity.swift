// Residual ABI specs not yet assigned to a categorized RuntimeABISpec section.
// Runtime-backed entries below are generated from Sources/Runtime exported C symbols.

public extension RuntimeABISpec {
    static let abiParityFunctions: [RuntimeABIFunctionSpec] = [
        // Compiler-reserved runtime ABI names without @_cdecl implementations yet.
        abiParitySpec("kk_kclass_register_annotation", parameters: [
            p("p0", .intptr),
            p("p1", .intptr),
        ]),
        abiParitySpec("kk_kclass_has_annotation", parameters: [
            p("p0", .intptr),
            p("p1", .intptr),
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
        // Runtime @_cdecl entries awaiting a dedicated RuntimeABISpec category.
        abiParitySpec("component1", parameters: [
            p("pairRaw", .intptr),
        ]),
        abiParitySpec("component2", parameters: [
            p("pairRaw", .intptr),
        ]),
        abiParitySpec("kk_atomic_ref_array_compareAndExchangeAt", parameters: [
            p("receiver", .intptr),
            p("index", .intptr),
            p("expect", .intptr),
            p("update", .intptr),
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
        abiParitySpec("kk_callable_ref_arity", parameters: [
            p("tagged", .intptr),
        ],
            isThrowing: false),
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
        ],
            isThrowing: false),
        abiParitySpec("kk_callable_ref_parameters", parameters: [
            p("tagged", .intptr),
        ],
            isThrowing: false),
        // KSP-678: these Channel residuals are bridged from bundled Kotlin
        // (Channels.kt) and return a plain Int handle/flag; they do not use the
        // outThrown ABI lowering path.
        abiParitySpec("kk_channel_is_closed_for_receive", parameters: [
            p("handle", .intptr),
        ], isThrowing: false),
        abiParitySpec("kk_channel_is_closed_for_send", parameters: [
            p("handle", .intptr),
        ], isThrowing: false),
        abiParitySpec("kk_channel_iterator", parameters: [
            p("handle", .intptr),
        ], isThrowing: false),
        abiParitySpec("kk_channel_iterator_hasNext", parameters: [
            p("iterHandle", .intptr),
        ], isThrowing: false),
        abiParitySpec("kk_channel_iterator_next", parameters: [
            p("iterHandle", .intptr),
        ], isThrowing: false),
        abiParitySpec("kk_channel_send_suspending", parameters: [
            p("handle", .intptr),
            p("value", .intptr),
            p("continuation", .intptr),
        ]),
        abiParitySpec("kk_char_isISOControl", parameters: [
            p("value", .intptr),
        ]),
        abiParitySpec("kk_char_isTitleCase", parameters: [
            p("value", .intptr),
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
        abiParitySpec("kk_cpointer_toLong", parameters: [
            p("handle", .intptr),
        ]),
        abiParitySpec("kk_cpointer_toKStringFromUtf32", parameters: [
            p("handle", .intptr),
        ]),
        abiParitySpec("kk_cpointer_toKStringFromUtf16", parameters: [
            p("handle", .intptr),
        ]),
        abiParitySpec("kk_byteArray_toCValues", parameters: [
            p("arrayRaw", .intptr),
        ],
            isThrowing: false),
        // STDLIB-CINTEROP-FN-029: ByteArray.toKString(startIndex, endIndex, throwOnInvalidSequence)
        abiParitySpec("__kk_byteArray_toKString", parameters: [
            p("arrRaw", .intptr),
            p("startIndex", .intptr),
            p("endIndex", .intptr),
            p("throwOnInvalidSequence", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("kk_cinterop_writeBits", parameters: [
            p("ptr", .intptr),
            p("offset", .intptr),
            p("size", .intptr),
            p("value", .intptr),
        ],
            returnType: .void,
            isThrowing: false),
        abiParitySpec("kk_uLongArray_toCValues", parameters: [
            p("arrayRaw", .intptr),
        ],
            isThrowing: false),
        abiParitySpec("kk_uIntArray_toCValues", parameters: [
            p("arrayRaw", .intptr),
        ],
            isThrowing: false),
        abiParitySpec("kk_uByteArray_toCValues", parameters: [
            p("arrayRaw", .intptr),
        ],
            isThrowing: false),
        abiParitySpec("__kk_fileTime_toMillis", parameters: [
            p("fileTimeRaw", .intptr),
        ],
            isThrowing: false),
        abiParitySpec("kk_flow_catch", parameters: [
            p("flowHandle", .intptr),
            p("handlerFnPtr", .intptr),
            p("arg2", .intptr),
        ]),
        abiParitySpec("__kk_flow_emit_with_timestamp", parameters: [
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
        // KSP-676: kk_flow_state_in removed — Flow.stateIn is bundled Kotlin source.
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
        abiParitySpec("kk_http_body_handlers_ofString", parameters: [
            p("bodyHandlersRaw", .intptr),
        ],
            isThrowing: false),
        abiParitySpec("kk_http_body_publishers_noBody", parameters: [
            p("bodyPublishersRaw", .intptr),
        ],
            isThrowing: false),
        abiParitySpec("kk_http_body_publishers_ofString", parameters: [
            p("bodyPublishersRaw", .intptr),
            p("bodyRaw", .intptr),
        ],
            isThrowing: false),
        abiParitySpec("kk_http_client_newHttpClient",
            isThrowing: false),
        abiParitySpec("kk_http_client_send", parameters: [
            p("clientRaw", .intptr),
            p("requestRaw", .intptr),
            p("bodyHandlerRaw", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("kk_http_headers_firstValue", parameters: [
            p("headersRaw", .intptr),
            p("nameRaw", .intptr),
        ],
            isThrowing: false),
        abiParitySpec("kk_http_headers_map", parameters: [
            p("headersRaw", .intptr),
        ],
            isThrowing: false),
        abiParitySpec("kk_http_request_builder_build", parameters: [
            p("builderRaw", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("kk_http_request_builder_GET", parameters: [
            p("builderRaw", .intptr),
        ],
            isThrowing: false),
        abiParitySpec("kk_http_request_builder_header", parameters: [
            p("builderRaw", .intptr),
            p("nameRaw", .intptr),
            p("valueRaw", .intptr),
        ],
            isThrowing: false),
        abiParitySpec("kk_http_request_builder_POST", parameters: [
            p("builderRaw", .intptr),
            p("publisherRaw", .intptr),
        ],
            isThrowing: false),
        abiParitySpec("kk_http_request_builder_uri", parameters: [
            p("builderRaw", .intptr),
            p("uriRaw", .intptr),
        ],
            isThrowing: false),
        abiParitySpec("kk_http_request_newBuilder",
            isThrowing: false),
        abiParitySpec("kk_http_request_newBuilder_uri", parameters: [
            p("uriRaw", .intptr),
        ],
            isThrowing: false),
        abiParitySpec("kk_http_response_headers", parameters: [
            p("responseRaw", .intptr),
        ],
            isThrowing: false),
        abiParitySpec("__kk_input_stream_mark", parameters: [
            p("streamRaw", .intptr),
            p("readLimitRaw", .intptr),
        ]),
        abiParitySpec("__kk_input_stream_mark_supported", parameters: [
            p("streamRaw", .intptr),
        ]),
        abiParitySpec("__kk_input_stream_reset", parameters: [
            p("streamRaw", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("__kk_io_createTempDir", parameters: [
            p("prefixRaw", .intptr),
            p("suffixRaw", .intptr),
            p("directoryRaw", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("__kk_io_createTempDir_default", parameters: [
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("__kk_io_createTempDir_prefix", parameters: [
            p("prefixRaw", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("__kk_io_createTempDir_prefix_suffix", parameters: [
            p("prefixRaw", .intptr),
            p("suffixRaw", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("__kk_io_createTempFile", parameters: [
            p("prefixRaw", .intptr),
            p("suffixRaw", .intptr),
            p("directoryRaw", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("__kk_io_createTempFile_default", parameters: [
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("__kk_io_createTempFile_prefix", parameters: [
            p("prefixRaw", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("__kk_io_createTempFile_prefix_suffix", parameters: [
            p("prefixRaw", .intptr),
            p("suffixRaw", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("kk_is_frozen", parameters: [
            p("objectRaw", .intptr),
        ]),
        abiParitySpec("kk_iterator_hasNext", parameters: [
            p("iterRaw", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("kk_iterator_next", parameters: [
            p("iterRaw", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("__kk_kclass_is_final", parameters: [
            p("kclassRaw", .intptr),
        ],
            isThrowing: false),
        abiParitySpec("__kk_kclass_is_open", parameters: [
            p("kclassRaw", .intptr),
        ],
            isThrowing: false),
        abiParitySpec("__kk_kclass_register_member", parameters: [
            p("kclassRaw", .intptr),
            p("memberRaw", .intptr),
        ]),
        abiParitySpec("__kk_kclass_register_metadata_v2", parameters: [
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
        abiParitySpec("__kk_kclass_supertypes", parameters: [
            p("kclassRaw", .intptr),
        ],
            isThrowing: false),
        abiParitySpec("__kk_kclass_type_parameters", parameters: [
            p("kclassRaw", .intptr),
        ],
            isThrowing: false),
        abiParitySpec("__kk_kclass_visibility", parameters: [
            p("kclassRaw", .intptr),
        ],
            isThrowing: false),
        abiParitySpec("kk_long_range_average", parameters: [
            p("rangeRaw", .intptr),
        ],
            isThrowing: false),
        abiParitySpec("kk_long_range_drop", parameters: [
            p("rangeRaw", .intptr),
            p("n", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("kk_long_range_sorted", parameters: [
            p("rangeRaw", .intptr),
        ],
            isThrowing: false),
        abiParitySpec("kk_long_range_take", parameters: [
            p("rangeRaw", .intptr),
            p("n", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("kk_map_entry_to_pair", parameters: [
            p("entryRaw", .intptr),
        ],
            isThrowing: false),
        // KSP-486: MatchResult iteration / destructuring bridges
        abiParitySpec("__kk_match_result_next", parameters: [
            p("matchRaw", .intptr),
        ],
            isThrowing: false),
        // STDLIB-TEXT-TYPE-010: MatchResult.Destructured
        abiParitySpec("__kk_match_result_destructured", parameters: [
            p("matchRaw", .intptr),
        ]),
        abiParitySpec("__kk_match_result_destructured_match", parameters: [
            p("destructuredRaw", .intptr),
        ]),
        abiParitySpec("kk_math_e"),
        abiParitySpec("kk_math_pi"),
        abiParitySpec("kk_mem_scope_alloc", parameters: [
            p("scopeHandle", .intptr),
            p("byteCount", .intptr),
        ]),
        abiParitySpec("kk_mem_scope_enter"),
        abiParitySpec("kk_mem_scope_exit", parameters: [
            p("handle", .intptr),
        ]),
        // KSP-676: MutableStateFlow is bundled Kotlin source; these C bridges are gone.
        abiParitySpec("kk_native_alloc_bytes", parameters: [
            p("byteCount", .intptr),
        ]),
        abiParitySpec("__kk_normalization_form_nfc",
            isThrowing: false),
        abiParitySpec("__kk_normalization_form_nfd",
            isThrowing: false),
        abiParitySpec("__kk_normalization_form_nfkc",
            isThrowing: false),
        abiParitySpec("__kk_normalization_form_nfkd",
            isThrowing: false),
        abiParitySpec("kk_pin_object", parameters: [
            p("objectRaw", .intptr),
        ]),
        abiParitySpec("kk_pinned_get", parameters: [
            p("pinnedHandle", .intptr),
        ]),
        abiParitySpec("kk_range_average", parameters: [
            p("rangeRaw", .intptr),
        ],
            isThrowing: false),
        abiParitySpec("kk_range_drop", parameters: [
            p("rangeRaw", .intptr),
            p("n", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("kk_range_sorted", parameters: [
            p("rangeRaw", .intptr),
        ],
            isThrowing: false),
        abiParitySpec("kk_range_take", parameters: [
            p("rangeRaw", .intptr),
            p("n", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("kk_regex_matches_flat", parameters: [
            p("regexRaw", .intptr),
            p("data", .nullableConstUInt8Pointer),
            p("length", .intptr),
            p("byteCount", .intptr),
            p("hash", .intptr),
        ]),

        abiParitySpec("__kk_sequence_input_stream_available", parameters: [
            p("streamRaw", .intptr),
        ]),
        abiParitySpec("__kk_sequence_input_stream_close", parameters: [
            p("streamRaw", .intptr),
        ]),
        abiParitySpec("__kk_sequence_input_stream_new", parameters: [
            p("firstRaw", .intptr),
            p("secondRaw", .intptr),
        ]),
        abiParitySpec("__kk_sequence_input_stream_read", parameters: [
            p("streamRaw", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        // KSP-413: kk_string_contentEquals_flat / kk_string_contentEquals_ignoreCase_flat
        // removed; contentEquals is bundled Kotlin source (StringComparison.kt).
        abiParitySpec("__kk_string_isNormalized_flat", parameters: [
            p("receiverData", .nullableConstUInt8Pointer),
            p("receiverLength", .intptr),
            p("receiverByteCount", .intptr),
            p("receiverHash", .intptr),
            p("formTagRaw", .intptr),
        ]),
        abiParitySpec("__kk_string_normalize_flat", parameters: [
            p("receiverData", .nullableConstUInt8Pointer),
            p("receiverLength", .intptr),
            p("receiverByteCount", .intptr),
            p("receiverHash", .intptr),
            p("formTagRaw", .intptr),
            p("outLength", .nullableIntptrPointer),
            p("outByteCount", .nullableIntptrPointer),
            p("outHash", .nullableIntptrPointer),
        ], returnType: .nullableUInt8Pointer),
        abiParitySpec("__kk_string_toBooleanStrictOrNull_flat", parameters: [
            p("data", .nullableConstUInt8Pointer),
            p("length", .intptr),
            p("byteCount", .intptr),
            p("hash", .intptr),
        ], isThrowing: false),
        abiParitySpec("__kk_string_toByte_flat", parameters: [
            p("data", .nullableConstUInt8Pointer),
            p("length", .intptr),
            p("byteCount", .intptr),
            p("hash", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("__kk_string_toByte", parameters: [
            p("strRaw", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("__kk_string_toByte_radix_flat", parameters: [
            p("data", .nullableConstUInt8Pointer),
            p("length", .intptr),
            p("byteCount", .intptr),
            p("hash", .intptr),
            p("radix", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("__kk_string_toByte_radix", parameters: [
            p("strRaw", .intptr),
            p("radix", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("__kk_string_toByteOrNull_flat", parameters: [
            p("data", .nullableConstUInt8Pointer),
            p("length", .intptr),
            p("byteCount", .intptr),
            p("hash", .intptr),
        ], isThrowing: false),
        abiParitySpec("__kk_string_toShortOrNull_flat", parameters: [
            p("data", .nullableConstUInt8Pointer),
            p("length", .intptr),
            p("byteCount", .intptr),
            p("hash", .intptr),
        ], isThrowing: false),
        abiParitySpec("__kk_string_toShort_flat", parameters: [
            p("data", .nullableConstUInt8Pointer),
            p("length", .intptr),
            p("byteCount", .intptr),
            p("hash", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("__kk_string_toShort", parameters: [
            p("strRaw", .intptr),
            p("outThrown", .nullableIntptrPointer),
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
        ],
            isThrowing: false),
        abiParitySpec("kk_uint_range_drop", parameters: [
            p("rangeRaw", .intptr),
            p("n", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("kk_uint_range_sorted", parameters: [
            p("rangeRaw", .intptr),
        ],
            isThrowing: false),
        abiParitySpec("kk_uint_range_take", parameters: [
            p("rangeRaw", .intptr),
            p("n", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("kk_ulong_range_average", parameters: [
            p("rangeRaw", .intptr),
        ],
            isThrowing: false),
        abiParitySpec("kk_ulong_range_drop", parameters: [
            p("rangeRaw", .intptr),
            p("n", .intptr),
            p("outThrown", .nullableIntptrPointer),
        ]),
        abiParitySpec("kk_ulong_range_sorted", parameters: [
            p("rangeRaw", .intptr),
        ],
            isThrowing: false),
        abiParitySpec("kk_ulong_range_take", parameters: [
            p("rangeRaw", .intptr),
            p("n", .intptr),
            p("outThrown", .nullableIntptrPointer),
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
    returnType: RuntimeABICType = .intptr,
    isThrowing: Bool = true
) -> RuntimeABIFunctionSpec {
    RuntimeABIFunctionSpec(
        name: name,
        parameters: parameters,
        returnType: returnType,
        section: "ABIParity",
        isThrowing: isThrowing
    )
}

private func p(_ name: String, _ type: RuntimeABICType) -> RuntimeABIParameter {
    RuntimeABIParameter(name: name, type: type)
}
