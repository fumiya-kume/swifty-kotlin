import CompilerCore
@testable import Runtime
import XCTest

// MARK: - Synthetic Stub / Runtime ABI Consistency (TOOL-046)

extension ABIMismatchTests {
    /// Verifies that every `externalLinkName` registered in synthetic Sema stubs
    /// has a corresponding entry in RuntimeABISpec.allFunctions.
    /// This catches the case where a synthetic stub references a runtime function
    /// that doesn't exist or was renamed.
    func testSyntheticStubExternalLinkNamesExistInABISpec() {
        let allSpecNames = Set(RuntimeABISpec.allFunctions.map(\.name))
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
            "kk_sequence_of",
            "kk_sequence_generate",
            "kk_system_exitProcess",
            "kk_system_currentTimeMillis",
            "kk_system_measureTimeMillis",
            "kk_system_measureNanoTime",
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
            "kk_atomic_ref_create",
            "kk_atomic_ref_load",
            "kk_atomic_ref_store",
            "kk_atomic_ref_exchange",
            "kk_atomic_ref_compareAndSet",
            "kk_atomic_ref_compareAndExchange",
        ]

        for linkName in syntheticLinkNames {
            XCTAssertTrue(
                allSpecNames.contains(linkName),
                "Synthetic stub externalLinkName '\(linkName)' not found in RuntimeABISpec.allFunctions"
            )
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
