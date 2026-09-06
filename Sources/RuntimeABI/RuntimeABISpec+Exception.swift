// swiftlint:disable file_length

/// `RuntimeABISpec.exceptionFunctions` extracted from `RuntimeABISpec.swift`.
public extension RuntimeABISpec {

    static let exceptionFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "__kk_throwable_new",
            parameters: [
                RuntimeABIParameter(name: "message", type: .nullableOpaquePointer),
            ],
            returnType: .opaquePointer,
            section: "Exception"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_throwable_new_with_cause",
            parameters: [
                RuntimeABIParameter(name: "message", type: .nullableOpaquePointer),
                RuntimeABIParameter(name: "causeRaw", type: .intptr),
            ],
            returnType: .opaquePointer,
            section: "Exception",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_throwable_new_cause",
            parameters: [
                RuntimeABIParameter(name: "causeRaw", type: .intptr),
            ],
            returnType: .opaquePointer,
            section: "Exception",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_throwable_new_cause",
            parameters: [
                RuntimeABIParameter(name: "causeRaw", type: .intptr),
            ],
            returnType: .opaquePointer,
            section: "Exception",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_freezing_exception_new",
            parameters: [
                RuntimeABIParameter(name: "toFreezeRaw", type: .intptr),
                RuntimeABIParameter(name: "blockerRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_no_when_branch_matched_exception_new",
            parameters: [],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_no_when_branch_matched_exception_new_message",
            parameters: [
                RuntimeABIParameter(name: "messageRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_no_when_branch_matched_exception_new_message_cause",
            parameters: [
                RuntimeABIParameter(name: "messageRaw", type: .intptr),
                RuntimeABIParameter(name: "causeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_no_when_branch_matched_exception_new_cause",
            parameters: [
                RuntimeABIParameter(name: "causeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_concurrent_modification_exception_new",
            parameters: [],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_concurrent_modification_exception_new_message",
            parameters: [
                RuntimeABIParameter(name: "messageRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_invalid_mutability_exception_new_message",
            parameters: [
                RuntimeABIParameter(name: "messageRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_concurrent_modification_exception_new_message_cause",
            parameters: [
                RuntimeABIParameter(name: "messageRaw", type: .intptr),
                RuntimeABIParameter(name: "causeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_concurrent_modification_exception_new_cause",
            parameters: [
                RuntimeABIParameter(name: "causeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_array_index_out_of_bounds_exception_new",
            parameters: [],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_array_index_out_of_bounds_exception_new_message",
            parameters: [
                RuntimeABIParameter(name: "messageRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
        // Per-type explicit constructor entry points (catch-clause sibling-type
        // discrimination fix). Each built-in exception class below gets its own
        // direct `__kk_*` constructor bridge instead of sharing
        // the type-erased __kk_throwable_new/__kk_throwable_new_with_cause, so the
        // allocated RuntimeThrowableBox subclass carries the correct runtime type
        // identity for kk_op_is / catch-clause dispatch.
        RuntimeABIFunctionSpec(
            name: "__kk_exception_new",
            parameters: [],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_exception_new_message",
            parameters: [
                RuntimeABIParameter(name: "messageRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_exception_new_message_cause",
            parameters: [
                RuntimeABIParameter(name: "messageRaw", type: .intptr),
                RuntimeABIParameter(name: "causeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_exception_new_cause",
            parameters: [
                RuntimeABIParameter(name: "causeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_character_coding_exception_new",
            parameters: [],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_character_coding_exception_new_message",
            parameters: [
                RuntimeABIParameter(name: "messageRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kotlin_nothing_value_exception_new",
            parameters: [],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kotlin_nothing_value_exception_new_message",
            parameters: [
                RuntimeABIParameter(name: "messageRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kotlin_nothing_value_exception_new_message_cause",
            parameters: [
                RuntimeABIParameter(name: "messageRaw", type: .intptr),
                RuntimeABIParameter(name: "causeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_kotlin_nothing_value_exception_new_cause",
            parameters: [
                RuntimeABIParameter(name: "causeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_error_new",
            parameters: [],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_error_new_message",
            parameters: [
                RuntimeABIParameter(name: "messageRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_error_new_message_cause",
            parameters: [
                RuntimeABIParameter(name: "messageRaw", type: .intptr),
                RuntimeABIParameter(name: "causeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_error_new_cause",
            parameters: [
                RuntimeABIParameter(name: "causeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
        // Bridge-only allocation entry points for the bundled Kotlin
        // `kotlin.NotImplementedError` declaration (KSP-616).
        RuntimeABIFunctionSpec(
            name: "__kk_not_implemented_error_new",
            parameters: [],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_not_implemented_error_new_message",
            parameters: [
                RuntimeABIParameter(name: "messageRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
        // Bridge-only allocation entry points for the bundled Kotlin
        // `kotlin.OutOfMemoryError` declaration (KSP-750).
        RuntimeABIFunctionSpec(
            name: "__kk_out_of_memory_error_new",
            parameters: [],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_out_of_memory_error_new_message",
            parameters: [
                RuntimeABIParameter(name: "messageRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_assertion_error_new",
            parameters: [],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_assertion_error_new_message",
            parameters: [
                RuntimeABIParameter(name: "messageRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_assertion_error_new_message_cause",
            parameters: [
                RuntimeABIParameter(name: "messageRaw", type: .intptr),
                RuntimeABIParameter(name: "causeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_illegal_state_exception_new",
            parameters: [],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_illegal_state_exception_new_message",
            parameters: [
                RuntimeABIParameter(name: "messageRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_illegal_state_exception_new_message_cause",
            parameters: [
                RuntimeABIParameter(name: "messageRaw", type: .intptr),
                RuntimeABIParameter(name: "causeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_illegal_state_exception_new_cause",
            parameters: [
                RuntimeABIParameter(name: "causeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_cancellation_exception_new",
            parameters: [],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_cancellation_exception_new_message",
            parameters: [
                RuntimeABIParameter(name: "messageRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_cancellation_exception_new_message_cause",
            parameters: [
                RuntimeABIParameter(name: "messageRaw", type: .intptr),
                RuntimeABIParameter(name: "causeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_cancellation_exception_new_cause",
            parameters: [
                RuntimeABIParameter(name: "causeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_illegal_argument_exception_new",
            parameters: [],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_illegal_argument_exception_new_message",
            parameters: [
                RuntimeABIParameter(name: "messageRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_illegal_argument_exception_new_message_cause",
            parameters: [
                RuntimeABIParameter(name: "messageRaw", type: .intptr),
                RuntimeABIParameter(name: "causeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_illegal_argument_exception_new_cause",
            parameters: [
                RuntimeABIParameter(name: "causeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_unsupported_operation_exception_new",
            parameters: [],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_unsupported_operation_exception_new_message",
            parameters: [
                RuntimeABIParameter(name: "messageRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_unsupported_operation_exception_new_message_cause",
            parameters: [
                RuntimeABIParameter(name: "messageRaw", type: .intptr),
                RuntimeABIParameter(name: "causeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_unsupported_operation_exception_new_cause",
            parameters: [
                RuntimeABIParameter(name: "causeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_no_such_element_exception_new",
            parameters: [],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_no_such_element_exception_new_message",
            parameters: [
                RuntimeABIParameter(name: "messageRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_arithmetic_exception_new",
            parameters: [],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_arithmetic_exception_new_message",
            parameters: [
                RuntimeABIParameter(name: "messageRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_class_cast_exception_new",
            parameters: [],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_class_cast_exception_new_message",
            parameters: [
                RuntimeABIParameter(name: "messageRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_type_cast_exception_new",
            parameters: [],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_type_cast_exception_new_message",
            parameters: [
                RuntimeABIParameter(name: "messageRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_uninitialized_property_access_exception_new",
            parameters: [],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_uninitialized_property_access_exception_new_message",
            parameters: [
                RuntimeABIParameter(name: "messageRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_uninitialized_property_access_exception_new_message_cause",
            parameters: [
                RuntimeABIParameter(name: "messageRaw", type: .intptr),
                RuntimeABIParameter(name: "causeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_uninitialized_property_access_exception_new_cause",
            parameters: [
                RuntimeABIParameter(name: "causeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_negative_array_size_exception_new",
            parameters: [],
            returnType: .intptr,
            section: "Exception"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_negative_array_size_exception_new_message",
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
            section: "Exception",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "kk_abort_unreachable",
            parameters: [
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
        // KSP-618: synchronized(lock) { } is Kotlin source delegating to this
        // demoted bridge; the block arrives as a function pointer + closure
        // environment pair with the usual outThrown channel.
        RuntimeABIFunctionSpec(
            name: "__kk_synchronized",
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
            name: "__kk_assertions_enabled",
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
            name: "kk_dispatch_error",
            parameters: [],
            returnType: .intptr,
            section: "Exception"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_throwable_message",
            parameters: [
                RuntimeABIParameter(name: "throwableRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_throwable_setMessage",
            parameters: [
                RuntimeABIParameter(name: "throwableRaw", type: .intptr),
                RuntimeABIParameter(name: "messageRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_throwable_cause",
            parameters: [
                RuntimeABIParameter(name: "throwableRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_throwable_rawStackFrames",
            parameters: [
                RuntimeABIParameter(name: "throwableRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Exception"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_throwable_toString",
            parameters: [
                RuntimeABIParameter(name: "throwableRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Exception"
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_printStderr",
            parameters: [
                RuntimeABIParameter(name: "messageRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
        // STDLIB-EXCEPT-105: Advanced exception handling
        RuntimeABIFunctionSpec(
            name: "__kk_throwable_setCause",
            parameters: [
                RuntimeABIParameter(name: "throwableRaw", type: .intptr),
                RuntimeABIParameter(name: "causeRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_throwable_appendSuppressed",
            parameters: [
                RuntimeABIParameter(name: "throwableRaw", type: .intptr),
                RuntimeABIParameter(name: "suppressedRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_throwable_suppressedRaw",
            parameters: [
                RuntimeABIParameter(name: "throwableRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
        RuntimeABIFunctionSpec(
            name: "__kk_throwable_captureStackTrace",
            parameters: [
                RuntimeABIParameter(name: "throwableRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Exception",
            isThrowing: false
        ),
    ]
}
