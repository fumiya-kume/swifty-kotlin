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
            "kk_println_newline",
            "kk_println_any",
            "kk_print_any",
            "kk_readline",
            "kk_readln",
            "kk_sequence_of",
            "kk_sequence_generate",
            "kk_system_exitProcess",
            "kk_system_currentTimeMillis",
            "kk_system_measureTimeMillis",
            "kk_system_measureNanoTime",
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
