@testable import CompilerCore
import Foundation
import XCTest

/// STDLIB-TEXT-TYPE-007: Validates that the synthetic `kotlin.text.MatchGroup`
/// class exists in the symbol table after sema, exposes the expected
/// `value: String` and `range` properties wired to the runtime ABI link names,
/// and that source-level access through `MatchResult.groups[..]` type-checks
/// without diagnostics.
final class MatchGroupTypeTests: XCTestCase {

    // MARK: - Shared sema fixture

    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            result = (sema, ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    // MARK: - 1. Class symbol registration

    func testMatchGroupClassSymbolIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "text", "MatchGroup"].map { interner.intern($0) }
        let sym = try XCTUnwrap(
            sema.symbols.lookup(fqName: fq),
            "kotlin.text.MatchGroup class symbol must be registered by sema"
        )
        let info = try XCTUnwrap(sema.symbols.symbol(sym))
        XCTAssertEqual(info.kind, .class,
                       "MatchGroup should be registered with kind=class")
    }

    // MARK: - 2. value: String property

    func testMatchGroupValuePropertyIsRegisteredAndLinked() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "text", "MatchGroup", "value"].map { interner.intern($0) }
        let sym = try XCTUnwrap(
            sema.symbols.lookup(fqName: fq),
            "MatchGroup.value property must be registered"
        )
        let info = try XCTUnwrap(sema.symbols.symbol(sym))
        XCTAssertEqual(info.kind, .property,
                       "MatchGroup.value should be a property")
        XCTAssertEqual(
            sema.symbols.externalLinkName(for: sym),
            "kk_match_group_value",
            "MatchGroup.value must be wired to the kk_match_group_value runtime entry"
        )
    }

    // MARK: - 3. range property

    func testMatchGroupRangePropertyIsRegisteredAndLinked() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "text", "MatchGroup", "range"].map { interner.intern($0) }
        let sym = try XCTUnwrap(
            sema.symbols.lookup(fqName: fq),
            "MatchGroup.range property must be registered"
        )
        let info = try XCTUnwrap(sema.symbols.symbol(sym))
        XCTAssertEqual(info.kind, .property,
                       "MatchGroup.range should be a property")
        XCTAssertEqual(
            sema.symbols.externalLinkName(for: sym),
            "kk_match_group_range",
            "MatchGroup.range must be wired to the kk_match_group_range runtime entry"
        )
    }

    // MARK: - 4. Source-level usage of MatchGroup

    func testMatchGroupAccessThroughMatchResultGroupsTypeChecks() throws {
        let ctx = makeContextFromSource("""
        fun firstGroupValue(input: String): String? {
            val regex = Regex("(a)(b)")
            val match = regex.find(input)
            val group: MatchGroup? = match?.groups?.get("a")
            return group?.value
        }
        """)
        try runSema(ctx)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
        XCTAssertTrue(
            errors.isEmpty,
            "Expected MatchGroup access via MatchResult.groups to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }
}
