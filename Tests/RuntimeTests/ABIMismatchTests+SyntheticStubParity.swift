import RuntimeABI
@testable import Runtime
import XCTest

// MARK: - Synthetic Stub / Runtime ABI Consistency (TOOL-046)

extension ABIMismatchTests {
    /// Verifies that every `externalLinkName` registered in synthetic Sema stubs
    /// has a corresponding entry in RuntimeABISpec.allFunctions.
    /// This catches the case where a synthetic stub references a runtime function
    /// that doesn't exist or was renamed.
    func testSyntheticStubExternalLinkNamesExistInABISpec() {
        let allExternNames = Set(RuntimeABIExterns.allExterns.map(\.name))

        // Known synthetic stub external link names collected from
        // HeaderHelpers+SyntheticTODOAndIOStubs.swift and related files.
        // This list should be updated when new synthetic stubs are added.
        let syntheticLinkNames: [String] = [
            "kk_todo_noarg",
            "kk_todo",
            "kk_test_assertEquals",
            "kk_test_assertEquals_message",
            "kk_test_assertTrue",
            "kk_test_assertTrue_message",
            "kk_test_assertNull",
            "kk_test_assertNull_message",
            "kk_println_newline",
            "kk_println_any",
            "kk_print_any",
            "kk_print_noarg",
            "kk_readline",
            "kk_readln",
            "kk_readlnOrNull",
            // Comparator (STDLIB-176)
            "kk_comparator_then_comparator",
            "kk_sequence_of",
            "kk_sequence_generate",
            "kk_system_exitProcess",
            "kk_system_currentTimeMillis",
            "kk_system_nanoTime",
            "kk_system_process_start_nanos",
            "kk_system_measureTimeMillis",
            "kk_system_measureNanoTime",
            "kk_instant_now",
            "kk_instant_from_epoch_millis",
            "kk_instant_epoch_seconds",
            "kk_instant_nano_of_second",
            "kk_instant_plus_duration",
            "kk_instant_minus_duration",
            "kk_instant_compare",
            "kk_instant_until",
            "kk_instant_elapsed",
            // Duration
            "kk_duration_zero",
            "kk_duration_infinite",
            "kk_duration_inWholeDays",
            "kk_duration_from_seconds_double",
            "kk_duration_from_milliseconds_double",
            "kk_duration_from_microseconds_double",
            "kk_duration_from_nanoseconds_double",
            "kk_duration_from_minutes_double",
            "kk_duration_from_hours_double",
            "kk_duration_from_days_double",
            "kk_duration_div_duration",
            "kk_synchronized",
            // Array binarySearch overloads (TYPE-103)
            "kk_array_binarySearch",
            "kk_intArray_binarySearch",
            "kk_longArray_binarySearch",
            "kk_byteArray_binarySearch",
            "kk_shortArray_binarySearch",
            "kk_uIntArray_binarySearch",
            "kk_uLongArray_binarySearch",
            "kk_doubleArray_binarySearch",
            "kk_floatArray_binarySearch",
            "kk_booleanArray_binarySearch",
            "kk_charArray_binarySearch",
            "kk_uByteArray_binarySearch",
            "kk_uShortArray_binarySearch",
            // Atomic (kotlin.concurrent)
            "kk_atomic_int_create",
            "kk_atomic_int_load",
            "kk_atomic_int_store",
            "kk_atomic_int_exchange",
            "kk_atomic_int_compareAndSet",
            "kk_atomic_int_compareAndExchange",
            "kk_atomic_int_fetchAndAdd",
            "kk_atomic_int_addAndFetch",
            "kk_atomic_int_fetchAndIncrement",
            "kk_atomic_int_incrementAndFetch",
            "kk_atomic_int_decrementAndFetch",
            "kk_atomic_int_getAndUpdate",
            "kk_atomic_int_updateAndGet",
            "kk_atomic_long_create",
            "kk_atomic_long_load",
            "kk_atomic_long_store",
            "kk_atomic_long_exchange",
            "kk_atomic_long_compareAndSet",
            "kk_atomic_long_compareAndExchange",
            "kk_atomic_long_fetchAndAdd",
            "kk_atomic_long_addAndFetch",
            "kk_atomic_long_fetchAndIncrement",
            "kk_atomic_long_incrementAndFetch",
            "kk_atomic_long_decrementAndFetch",
            "kk_atomic_long_getAndUpdate",
            "kk_atomic_long_updateAndGet",
            "kk_atomic_ref_create",
            "kk_atomic_ref_load",
            "kk_atomic_ref_store",
            "kk_atomic_ref_exchange",
            "kk_atomic_ref_compareAndSet",
            "kk_atomic_ref_compareAndExchange",
            "kk_atomic_ref_getAndUpdate",
            "kk_atomic_ref_updateAndGet",
            "kk_atomic_bool_create",
            "kk_atomic_bool_load",
            "kk_atomic_bool_store",
            "kk_atomic_bool_exchange",
            "kk_atomic_bool_compareAndSet",
            "kk_atomic_bool_compareAndExchange",
            "kk_atomic_bool_getAndUpdate",
            "kk_atomic_bool_updateAndGet",
            "kk_atomic_int_array_create",
            "kk_atomic_int_array_size",
            "kk_atomic_int_array_loadAt",
            "kk_atomic_int_array_storeAt",
            "kk_atomic_int_array_exchangeAt",
            "kk_atomic_int_array_compareAndSetAt",
            "kk_atomic_int_array_compareAndExchangeAt",
            "kk_atomic_int_array_fetchAndAddAt",
            "kk_atomic_int_array_addAndFetchAt",
            "kk_atomic_int_array_incrementAndFetchAt",
            "kk_atomic_int_array_decrementAndFetchAt",
            "kk_atomic_long_array_create",
            "kk_atomic_long_array_size",
            "kk_atomic_long_array_loadAt",
            "kk_atomic_long_array_storeAt",
            "kk_atomic_long_array_exchangeAt",
            "kk_atomic_long_array_compareAndSetAt",
            "kk_atomic_long_array_compareAndExchangeAt",
            "kk_atomic_long_array_fetchAndAddAt",
            "kk_atomic_long_array_addAndFetchAt",
            "kk_atomic_long_array_incrementAndFetchAt",
            "kk_atomic_long_array_decrementAndFetchAt",
            // ThreadLocal (java.lang / kotlin.concurrent)
            "kk_thread_local_new",
            "kk_thread_local_getOrSet",
            "kk_thread_create",
            // kotlin.concurrent
            "kk_lock_withLock",
            "kk_mutex_create",
            "kk_mutex_lock",
            "kk_mutex_unlock",
            "kk_mutex_tryLock",
            "kk_mutex_isLocked",
            "kk_mutex_withLock",
            "kk_read_write_lock_create",
            "kk_read_write_lock_read",
            "kk_read_write_lock_write",
            // Read/write lock (java.util.concurrent.locks / kotlin.concurrent)
            "kk_reentrant_read_write_lock_new",
            "kk_reentrant_read_write_lock_read",
            // Symmetric crypto (javax.crypto)
            "kk_secretkeyspec_new",
            "kk_ivparameterspec_new",
            "kk_cipher_getInstance",
            "kk_cipher_init",
            "kk_cipher_init_with_iv",
            "kk_cipher_doFinal",
            "kk_cipher_doFinal_noarg",
            "kk_mac_getInstance",
            "kk_mac_init",
            "kk_mac_doFinal",
            // JSON Serialization (STDLIB-SER-132)
            "kk_json_default",
            "kk_json_encodeToString",
            "kk_json_decodeFromString",
            "kk_json_encodeMapToString",
        ]

        for linkName in syntheticLinkNames {
            XCTAssertTrue(
                allExternNames.contains(linkName),
                "Synthetic stub externalLinkName '\(linkName)' not found in RuntimeABIExterns.allExterns"
            )
        }
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
