import RuntimeABI
@testable import Runtime
import XCTest

// MARK: - Synthetic Stub / Runtime ABI Consistency (TOOL-046)
//
// Why this file is structured the way it is
// -----------------------------------------
// Every synthetic Sema stub registers an external link name (e.g. `kk_todo`)
// that must be backed by an entry in `RuntimeABISpec.allFunctions`. The test
// below checks that contract.
//
// Until recently this list was a single 426-line `[String]` literal, which
// became a major merge-conflict hotspot: every PR that added a synthetic stub
// appended to the same trailing lines. We now split the names into
// category-scoped `Set<String>` literals (one `static let` per category,
// entries sorted alphabetically). Parallel branches that touch different
// categories edit *different* `static let`s and no longer collide.
//
// To add a new synthetic link name:
//   1. Find the appropriate category `static let` below.
//   2. Insert your `"kk_..."` literal at its alphabetical position inside
//      that Set literal — do NOT append at the bottom.
//   3. If no category fits, add a new `static let myAreaStubLinkNames: Set<String>`
//      and union it into `allSyntheticStubLinkNames` below.

extension ABIMismatchTests {
    // MARK: Core stubs (TODO, print/read, test framework, top-level stdlib)
    private static let coreStubLinkNames: Set<String> = [
        "kk_array_of_nulls",
        "kk_print_any",
        "kk_print_noarg",
        "kk_println_any",
        "kk_println_newline",
        "kk_readline",
        "kk_readln",
        "kk_readlnOrNull",
        "kk_sequence_generate",
        "kk_sequence_of",
        "kk_string_chunked_sequence_transform",
        "kk_string_hexToUInt",
        "kk_test_assertEquals",
        "kk_test_assertEquals_message",
        "kk_test_assertNull",
        "kk_test_assertNull_message",
        "kk_test_assertTrue",
        "kk_test_assertTrue_message",
        "kk_todo",
        "kk_todo_noarg",
    ]

    // MARK: Exception constructors
    private static let exceptionStubLinkNames: Set<String> = [
        "kk_concurrent_modification_exception_new",
        "kk_concurrent_modification_exception_new_cause",
        "kk_concurrent_modification_exception_new_message",
        "kk_concurrent_modification_exception_new_message_cause",
        "kk_no_when_branch_matched_exception_new",
        "kk_no_when_branch_matched_exception_new_cause",
        "kk_no_when_branch_matched_exception_new_message",
        "kk_no_when_branch_matched_exception_new_message_cause",
    ]

    // MARK: Comparator (STDLIB-176)
    private static let comparatorStubLinkNames: Set<String> = [
        "kk_comparator_then_comparator",
    ]

    // MARK: Collection HOF / conversion / windowing
    private static let collectionStubLinkNames: Set<String> = [
        "kk_collection_toList",
        "kk_collection_toMutableList",
        "kk_collection_toTypedArray",
        "kk_iterable_toMutableList",
        "kk_iterable_toMutableSet",
        "kk_int_stream_toList",
        "kk_js_array_toMutableList",
        "kk_js_map_toMutableMap",
        "kk_js_set_toMutableSet",
        "kk_js_set_toSet",
        "kk_list_binarySearch",
        "kk_list_binarySearch_compare",
        "kk_list_binarySearch_comparator",
        "kk_list_indices",
        "kk_list_intersect",
        "kk_list_lastIndex",
        "kk_list_reduceRightIndexed",
        "kk_list_reduceRightIndexedOrNull",
        "kk_list_reduceRightOrNull",
        "kk_list_subtract",
        "kk_list_sumBy",
        "kk_list_sumByDouble",
        "kk_list_toBooleanArray",
        "kk_list_toDoubleArray",
        "kk_list_toFloatArray",
        "kk_list_toHashSet",
        "kk_list_toIntArray",
        "kk_list_toLongArray",
        "kk_list_toMap",
        "kk_list_toShortArray",
        "kk_list_toTypedArray",
        "kk_list_union",
        "kk_list_unzip",
        "kk_list_windowed",
        "kk_list_windowed_default",
        "kk_list_windowed_partial",
        "kk_list_windowed_transform",
        "kk_list_withIndex",
        "kk_list_zip",
        "kk_list_zipWithNext",
        "kk_list_zipWithNextTransform",
        "kk_long_stream_toList",
        "kk_map_withDefault",
        "kk_mutable_list_removeFirst",
        "kk_mutable_list_removeFirstOrNull",
        "kk_mutable_list_removeLast",
        "kk_mutable_list_removeLastOrNull",
        "kk_mutable_list_sortWith",
    ]

    // MARK: Collection binarySearchBy (STDLIB-COL-BSEARCH-001)
    private static let binarySearchByStubLinkNames: Set<String> = [
        "kk_list_binarySearchBy",
        "kk_list_binarySearchBy_fromIndex",
        "kk_list_binarySearchBy_range",
    ]

    // MARK: String radix conversion
    private static let stringRadixStubLinkNames: Set<String> = [
        "kk_string_case_insensitive_order",
        "kk_string_hexToShort",
        "kk_string_hexToUByte",
        "kk_string_hexToUByteArray",
        "kk_string_hexToUInt",
        "kk_string_hexToULong",
        "kk_string_hexToUShort",
        "kk_string_toIntOrNull_radix",
        "kk_string_toUByteOrNull_radix",
        "kk_string_toUIntOrNull_radix",
        "kk_string_toULongOrNull_radix",
        "kk_string_toUShortOrNull_radix",
    ]

    // MARK: System / timing / Stream toList
    private static let systemStubLinkNames: Set<String> = [
        "kk_double_stream_toList",
        "kk_stream_toList",
        "kk_synchronized",
        "kk_system_currentTimeMillis",
        "kk_system_exitProcess",
        "kk_system_getTimeMicros",
        "kk_system_getTimeMillis",
        "kk_system_getTimeNanos",
        "kk_system_measureNanoTime",
        "kk_system_measureTimeMicros",
        "kk_system_measureTimeMillis",
        "kk_system_nanoTime",
        "kk_system_process_start_nanos",
    ]

    // MARK: UUID (kotlin.uuid)
    private static let uuidStubLinkNames: Set<String> = [
        "kk_uuid_fromByteArray",
        "kk_uuid_fromLongs",
        "kk_uuid_leastSignificantBits",
        "kk_uuid_mostSignificantBits",
        "kk_uuid_nameUUIDFromBytes",
        "kk_uuid_nil",
        "kk_uuid_parse",
        "kk_uuid_parseHex",
        "kk_uuid_parseHexDash",
        "kk_uuid_parseHexDashOrNull",
        "kk_uuid_parseHexOrNull",
        "kk_uuid_parseOrNull",
        "kk_uuid_random",
        "kk_uuid_toByteArray",
        "kk_uuid_toHexString",
        "kk_uuid_toLongs",
        "kk_uuid_toString",
        "kk_uuid_variant",
        "kk_uuid_version",
    ]

    // MARK: Instant / Clock / time conversions
    private static let instantStubLinkNames: Set<String> = [
        "kk_instant_compare",
        "kk_instant_elapsed",
        "kk_instant_epoch_seconds",
        "kk_instant_from_epoch_millis",
        "kk_instant_is_distant_future",
        "kk_instant_is_distant_past",
        "kk_instant_minus_duration",
        "kk_instant_nano_of_second",
        "kk_instant_now",
        "kk_instant_plus_duration",
        "kk_instant_until",
        "kk_time_source_as_clock",
    ]

    // MARK: Duration (kotlin.time)
    private static let durationStubLinkNames: Set<String> = [
        "kk_duration_div_duration",
        "kk_duration_from_days_double",
        "kk_duration_from_hours_double",
        "kk_duration_from_microseconds_double",
        "kk_duration_from_milliseconds_double",
        "kk_duration_from_minutes_double",
        "kk_duration_from_nanoseconds_double",
        "kk_duration_from_seconds_double",
        "kk_duration_inWholeDays",
        "kk_duration_infinite",
        "kk_duration_parse",
        "kk_duration_parseIsoString",
        "kk_duration_parseIsoStringOrNull",
        "kk_duration_parseOrNull",
        "kk_duration_toComponents_days",
        "kk_duration_toComponents_hours",
        "kk_duration_toComponents_minutes",
        "kk_duration_toComponents_seconds",
        "kk_duration_toDuration_double",
        "kk_duration_toDuration_int",
        "kk_duration_toDuration_long",
        "kk_duration_toIsoString",
        "kk_duration_zero",
    ]

    // MARK: Lazy (kotlin.lazy + kotlin.properties.Lazy)
    private static let lazyStubLinkNames: Set<String> = [
        "kk_lazy_get_value",
        "kk_lazy_is_initialized",
        "kk_lazy_of",
    ]

    // MARK: Unsigned numeric coercion (STDLIB-500)
    private static let unsignedCoercionStubLinkNames: Set<String> = [
        "kk_ubyte_coerceAtLeast",
        "kk_ubyte_coerceAtMost",
        "kk_ubyte_coerceIn",
        "kk_uint_coerceAtLeast",
        "kk_uint_coerceAtMost",
        "kk_uint_coerceIn",
        "kk_ulong_coerceAtLeast",
        "kk_ulong_coerceAtMost",
        "kk_ulong_coerceIn",
        "kk_ushort_coerceAtLeast",
        "kk_ushort_coerceAtMost",
        "kk_ushort_coerceIn",
    ]

    // MARK: Array binarySearch overloads (TYPE-103)
    private static let arrayBinarySearchStubLinkNames: Set<String> = [
        "kk_array_binarySearch",
        "kk_array_binarySearch_compare",
        "kk_booleanArray_binarySearch",
        "kk_byteArray_binarySearch",
        "kk_charArray_binarySearch",
        "kk_doubleArray_binarySearch",
        "kk_floatArray_binarySearch",
        "kk_intArray_binarySearch",
        "kk_longArray_binarySearch",
        "kk_shortArray_binarySearch",
        "kk_uByteArray_binarySearch",
        "kk_uIntArray_binarySearch",
        "kk_uLongArray_binarySearch",
        "kk_uShortArray_binarySearch",
    ]

    // MARK: Atomic (kotlin.concurrent.atomics) — scalars and arrays
    private static let atomicStubLinkNames: Set<String> = [
        "kk_atomic_bool_asJavaAtomic",
        "kk_atomic_bool_compareAndExchange",
        "kk_atomic_bool_compareAndSet",
        "kk_atomic_bool_create",
        "kk_atomic_bool_exchange",
        "kk_atomic_bool_getAndUpdate",
        "kk_atomic_bool_load",
        "kk_atomic_bool_store",
        "kk_atomic_bool_updateAndGet",
        "kk_atomic_int_addAndFetch",
        "kk_atomic_int_array_addAndFetchAt",
        "kk_atomic_int_array_asJavaAtomicArray",
        "kk_atomic_int_array_compareAndExchangeAt",
        "kk_atomic_int_array_compareAndSetAt",
        "kk_atomic_int_array_create",
        "kk_atomic_int_array_decrementAndFetchAt",
        "kk_atomic_int_array_exchangeAt",
        "kk_atomic_int_array_fetchAndAddAt",
        "kk_atomic_int_array_fetchAndDecrementAt",
        "kk_atomic_int_array_fetchAndIncrementAt",
        "kk_atomic_int_array_fetchAndUpdateAt",
        "kk_atomic_int_array_incrementAndFetchAt",
        "kk_atomic_int_array_loadAt",
        "kk_atomic_int_array_size",
        "kk_atomic_int_array_storeAt",
        "kk_atomic_int_asJavaAtomic",
        "kk_atomic_int_compareAndExchange",
        "kk_atomic_int_compareAndSet",
        "kk_atomic_int_create",
        "kk_atomic_int_decrementAndFetch",
        "kk_atomic_int_exchange",
        "kk_atomic_int_fetchAndAdd",
        "kk_atomic_int_fetchAndDecrement",
        "kk_atomic_int_fetchAndIncrement",
        "kk_atomic_int_getAndUpdate",
        "kk_atomic_int_incrementAndFetch",
        "kk_atomic_int_load",
        "kk_atomic_int_store",
        "kk_atomic_int_updateAndGet",
        "kk_atomic_long_addAndFetch",
        "kk_atomic_long_array_addAndFetchAt",
        "kk_atomic_long_array_asJavaAtomicArray",
        "kk_atomic_long_array_compareAndExchangeAt",
        "kk_atomic_long_array_compareAndSetAt",
        "kk_atomic_long_array_create",
        "kk_atomic_long_array_decrementAndFetchAt",
        "kk_atomic_long_array_exchangeAt",
        "kk_atomic_long_array_fetchAndAddAt",
        "kk_atomic_long_array_fetchAndDecrementAt",
        "kk_atomic_long_array_fetchAndIncrementAt",
        "kk_atomic_long_array_fetchAndUpdateAt",
        "kk_atomic_long_array_incrementAndFetchAt",
        "kk_atomic_long_array_loadAt",
        "kk_atomic_long_array_size",
        "kk_atomic_long_array_storeAt",
        "kk_atomic_long_asJavaAtomic",
        "kk_atomic_long_compareAndExchange",
        "kk_atomic_long_compareAndSet",
        "kk_atomic_long_create",
        "kk_atomic_long_decrementAndFetch",
        "kk_atomic_long_exchange",
        "kk_atomic_long_fetchAndAdd",
        "kk_atomic_long_fetchAndDecrement",
        "kk_atomic_long_fetchAndIncrement",
        "kk_atomic_long_getAndUpdate",
        "kk_atomic_long_incrementAndFetch",
        "kk_atomic_long_load",
        "kk_atomic_long_store",
        "kk_atomic_long_updateAndGet",
        "kk_atomic_ref_array_asJavaAtomicArray",
        "kk_atomic_ref_array_compareAndSetAt",
        "kk_atomic_ref_array_exchangeAt",
        "kk_atomic_ref_array_of",
        "kk_atomic_ref_asJavaAtomic",
        "kk_atomic_ref_compareAndExchange",
        "kk_atomic_ref_compareAndSet",
        "kk_atomic_ref_create",
        "kk_atomic_ref_exchange",
        "kk_atomic_ref_getAndUpdate",
        "kk_atomic_ref_load",
        "kk_atomic_ref_store",
        "kk_atomic_ref_updateAndGet",
        "kk_java_atomic_bool_asKotlinAtomic",
        "kk_java_atomic_int_array_asKotlinAtomicArray",
        "kk_java_atomic_int_asKotlinAtomic",
        "kk_java_atomic_long_array_asKotlinAtomicArray",
        "kk_java_atomic_long_asKotlinAtomic",
        "kk_java_atomic_ref_array_asKotlinAtomicArray",
        "kk_java_atomic_ref_asKotlinAtomic",
    ]

    // MARK: kotlin.native.ref (WeakReference, Cleaner, GC, debugging)
    private static let weakRefStubLinkNames: Set<String> = [
        "kk_cleaner_create",
        "kk_debugging_gc_suspend_count",
        "kk_debugging_global_object_count",
        "kk_debugging_is_thread_state_runnable",
        "kk_debugging_thread_count",
        "kk_gc_collect",
        "kk_gc_max_heap_bytes",
        "kk_gc_schedule",
        "kk_gc_target_heap_bytes",
        "kk_gc_target_heap_utilization",
        "kk_weak_ref_clear",
        "kk_weak_ref_create",
        "kk_weak_ref_get",
    ]

    // MARK: ThreadLocal / Thread
    private static let threadLocalStubLinkNames: Set<String> = [
        "kk_thread_create",
        "kk_thread_local_getOrSet",
        "kk_thread_local_new",
    ]

    // MARK: kotlin.concurrent (mutex, locks, grouping)
    private static let concurrentStubLinkNames: Set<String> = [
        "kk_grouping_aggregate",
        "kk_grouping_aggregateTo",
        "kk_grouping_eachCount",
        "kk_grouping_fold",
        "kk_grouping_reduce",
        "kk_lock_withLock",
        "kk_mutex_create",
        "kk_mutex_isLocked",
        "kk_mutex_lock",
        "kk_mutex_tryLock",
        "kk_mutex_unlock",
        "kk_mutex_withLock",
        "kk_read_write_lock_create",
        "kk_read_write_lock_read",
        "kk_read_write_lock_write",
    ]

    // MARK: Read/write lock (java.util.concurrent.locks)
    private static let readWriteLockStubLinkNames: Set<String> = [
        "kk_reentrant_read_write_lock_new",
        "kk_reentrant_read_write_lock_read",
    ]

    // MARK: Symmetric crypto (javax.crypto)
    private static let cryptoStubLinkNames: Set<String> = [
        "kk_cipher_doFinal",
        "kk_cipher_doFinal_noarg",
        "kk_cipher_getInstance",
        "kk_cipher_init",
        "kk_cipher_init_with_iv",
        "kk_ivparameterspec_new",
        "kk_mac_doFinal",
        "kk_mac_getInstance",
        "kk_mac_init",
        "kk_secretkeyspec_new",
    ]

    // MARK: JSON Serialization (STDLIB-SER-132)
    private static let jsonSerializationStubLinkNames: Set<String> = [
        "kk_json_decodeFromString",
        "kk_json_default",
        "kk_json_encodeMapToString",
        "kk_json_encodeToString",
    ]

    // MARK: Base64 (kotlin.io.encoding)
    private static let base64StubLinkNames: Set<String> = [
        "kk_base64_decode_default",
        "kk_base64_decode_instance",
        "kk_base64_decode_mime",
        "kk_base64_decode_urlsafe",
        "kk_base64_decodeFromByteArray_default",
        "kk_base64_decodeFromByteArray_instance",
        "kk_base64_decodeFromByteArray_mime",
        "kk_base64_decodeFromByteArray_urlsafe",
        "kk_base64_encode_default",
        "kk_base64_encode_instance",
        "kk_base64_encode_mime",
        "kk_base64_encode_urlsafe",
        "kk_base64_encodeToByteArray_default",
        "kk_base64_encodeToByteArray_instance",
        "kk_base64_encodeToByteArray_mime",
        "kk_base64_encodeToByteArray_urlsafe",
        "kk_base64_padding_absent",
        "kk_base64_padding_absent_optional",
        "kk_base64_padding_present",
        "kk_base64_padding_present_optional",
        "kk_base64_withPadding_default",
        "kk_base64_withPadding_instance",
        "kk_base64_withPadding_mime",
        "kk_base64_withPadding_urlsafe",
    ]

    // MARK: KotlinVersion
    private static let kotlinVersionStubLinkNames: Set<String> = [
        "kk_kotlin_version_compareTo",
        "kk_kotlin_version_current",
        "kk_kotlin_version_isAtLeast",
        "kk_kotlin_version_isAtLeast_patch",
        "kk_kotlin_version_major",
        "kk_kotlin_version_minor",
        "kk_kotlin_version_new",
        "kk_kotlin_version_new_patch",
        "kk_kotlin_version_patch",
    ]

    // MARK: URL (java.net.URL / kotlin.io extensions)
    private static let urlStubLinkNames: Set<String> = [
        "kk_url_readBytes",
    ]

    // MARK: kotlin.concurrent.schedule / java.util.Timer (STDLIB-CONC-FN-005)
    private static let timerStubLinkNames: Set<String> = [
        "kk_concurrent_schedule_delay",
        "kk_concurrent_schedule_period",
    ]

    /// Union of every category. New categories should be added below.
    /// Each category lives in its own `static let` above so that parallel
    /// branches editing different category Sets do not collide.
    private static var allSyntheticStubLinkNames: Set<String> {
        var result: Set<String> = []
        result.formUnion(coreStubLinkNames)
        result.formUnion(exceptionStubLinkNames)
        result.formUnion(comparatorStubLinkNames)
        result.formUnion(collectionStubLinkNames)
        result.formUnion(binarySearchByStubLinkNames)
        result.formUnion(stringRadixStubLinkNames)
        result.formUnion(systemStubLinkNames)
        result.formUnion(uuidStubLinkNames)
        result.formUnion(instantStubLinkNames)
        result.formUnion(durationStubLinkNames)
        result.formUnion(lazyStubLinkNames)
        result.formUnion(unsignedCoercionStubLinkNames)
        result.formUnion(arrayBinarySearchStubLinkNames)
        result.formUnion(atomicStubLinkNames)
        result.formUnion(weakRefStubLinkNames)
        result.formUnion(threadLocalStubLinkNames)
        result.formUnion(concurrentStubLinkNames)
        result.formUnion(readWriteLockStubLinkNames)
        result.formUnion(cryptoStubLinkNames)
        result.formUnion(jsonSerializationStubLinkNames)
        result.formUnion(base64StubLinkNames)
        result.formUnion(kotlinVersionStubLinkNames)
        result.formUnion(urlStubLinkNames)
        result.formUnion(timerStubLinkNames)
        return result
    }

    /// Verifies that every `externalLinkName` registered in synthetic Sema stubs
    /// has a corresponding entry in `RuntimeABIExterns.allExterns`.
    /// This catches the case where a synthetic stub references a runtime function
    /// that doesn't exist or was renamed.
    func testSyntheticStubExternalLinkNamesExistInABISpec() {
        let allExternNames = Set(RuntimeABIExterns.allExterns.map(\.name))
        let missing = Self.allSyntheticStubLinkNames.subtracting(allExternNames)
        XCTAssertTrue(
            missing.isEmpty,
            "Synthetic stub external link names missing from RuntimeABIExterns.allExterns: " +
                "\(missing.sorted().joined(separator: ", "))"
        )
    }

    /// Verifies that vararg synthetic stubs (like sequenceOf) reference runtime
    /// functions that accept a packed array (single intptr_t argument), not
    /// the unpacked argument form.
    func testVarargSyntheticStubsReferencePackedArrayABI() {
        // sequenceOf is the canonical example: Sema registers it as vararg,
        // but the runtime function kk_sequence_of takes a single packed array.
        let varargLinkNames = [
            "kk_sequence_of",
        ]

        for linkName in varargLinkNames {
            guard let externDecl = RuntimeABIExterns.externDecl(named: linkName) else {
                XCTFail("Vararg function '\(linkName)' not found in RuntimeABIExterns.allExterns")
                continue
            }
            XCTAssertEqual(
                externDecl.parameterTypes.count, 1,
                "Vararg function '\(linkName)' should accept 1 packed array parameter, " +
                    "but has \(externDecl.parameterTypes.count) parameters"
            )
        }
    }
}
