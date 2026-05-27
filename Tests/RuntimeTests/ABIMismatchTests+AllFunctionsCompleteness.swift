import RuntimeABI
import XCTest

extension ABIMismatchTests {
    /// Direct uniqueness check on `RuntimeABISpec.allFunctions`.
    ///
    /// The existing `testRuntimeABISpecSectionsHaveUniqueNames` enumerates
    /// sections via a hand-written list and verifies that this list has
    /// unique entries (and that its size matches `allFunctions.count`).
    /// That check assumes the central concatenation is itself correct —
    /// but if a 3-way merge accidentally introduces the same sub-array
    /// twice into `allFunctions` while leaving the hand-written sections
    /// list unchanged, the existing test still passes.
    ///
    /// This test closes that gap by inspecting `allFunctions` directly.
    /// It is the safety net for the merge-conflict-prevention layout
    /// (sub-arrays listed alphabetically one per line) — without it,
    /// double-concatenation would silently inflate the runtime surface.
    func testRuntimeABISpecAllFunctionsHaveNoDuplicateNames() {
        let names = RuntimeABISpec.allFunctions.map(\.name)
        let duplicates = Dictionary(grouping: names, by: { $0 })
            .filter { $0.value.count > 1 }
            .keys
            .sorted()
        XCTAssertTrue(
            duplicates.isEmpty,
            "RuntimeABISpec.allFunctions contains duplicate names: " +
                "\(duplicates.joined(separator: ", "))"
        )
    }
}
