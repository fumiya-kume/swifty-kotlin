@testable import CompilerCore
import Foundation
import XCTest

// MARK: - STDLIB-REGEX-001: kotlin.text.Regex API Surface Inventory
//
// This file catalogues *every* Regex-related symbol that the sema layer registers
// as a synthetic stub and verifies that:
//   • the symbol exists in the symbol table after sema
//   • it is wired to the expected ABI / external-link name
//   • class-member lookups use the correct fully-qualified path
//     (kotlin.text.<ClassName>.<member>)
//   • top-level constructor overloads and companion methods are all present
//
// Scope: signature-level / sema-level only — runtime correctness is covered by
//        RuntimeRegexTests and STDLIB-REGEX-003 (commit #1208).

final class RegexAPISurfaceInventoryTests: XCTestCase {

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

    // MARK: - Lookup helpers

    /// External link for a kotlin.text-level symbol (top-level or class member).
    private func externalLink(
        fqPath: [String],
        sema: SemaModule,
        interner: StringInterner
    ) -> String? {
        let interned = fqPath.map { interner.intern($0) }
        guard let sym = sema.symbols.lookup(fqName: interned) else { return nil }
        return sema.symbols.externalLinkName(for: sym)
    }

    /// All external links registered under the given FQ path.
    private func allExternalLinks(
        fqPath: [String],
        sema: SemaModule,
        interner: StringInterner
    ) -> Set<String> {
        let interned = fqPath.map { interner.intern($0) }
        return Set(
            sema.symbols.lookupAll(fqName: interned)
                .compactMap { sema.symbols.externalLinkName(for: $0) }
        )
    }

    // MARK: - 1. Constructors

    func testRegexSingleArgConstructorIsRegistered() throws {
        let (sema, interner) = try makeSema()
        // Regex(pattern: String) -> Regex
        let links = allExternalLinks(
            fqPath: ["kotlin", "text", "Regex"],
            sema: sema,
            interner: interner
        )
        XCTAssertTrue(
            links.contains("kk_regex_create"),
            "Regex(pattern) constructor must link to kk_regex_create"
        )
    }

    func testRegexSingleOptionConstructorIsRegistered() throws {
        let (sema, interner) = try makeSema()
        // Regex(pattern: String, option: RegexOption) -> Regex
        let links = allExternalLinks(
            fqPath: ["kotlin", "text", "Regex"],
            sema: sema,
            interner: interner
        )
        XCTAssertTrue(
            links.contains("kk_regex_create_with_option"),
            "Regex(pattern, option) constructor must link to kk_regex_create_with_option"
        )
    }

    func testRegexSetOptionsConstructorIsRegistered() throws {
        let (sema, interner) = try makeSema()
        // Regex(pattern: String, options: Set<RegexOption>) -> Regex
        let links = allExternalLinks(
            fqPath: ["kotlin", "text", "Regex"],
            sema: sema,
            interner: interner
        )
        XCTAssertTrue(
            links.contains("kk_regex_create_with_options"),
            "Regex(pattern, options) constructor must link to kk_regex_create_with_options"
        )
    }

    func testAllThreeRegexConstructorOverloadsArePresent() throws {
        let (sema, interner) = try makeSema()
        let links = allExternalLinks(
            fqPath: ["kotlin", "text", "Regex"],
            sema: sema,
            interner: interner
        )
        let required: Set<String> = [
            "kk_regex_create",
            "kk_regex_create_with_option",
            "kk_regex_create_with_options",
        ]
        XCTAssertTrue(
            required.isSubset(of: links),
            "All three Regex constructor overloads must be registered; found: \(links)"
        )
    }

    // MARK: - 2. RegexOption enum entries

    func testRegexOptionEnumClassIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "text", "RegexOption"].map { interner.intern($0) }
        let sym = sema.symbols.lookup(fqName: fq)
        XCTAssertNotNil(sym, "kotlin.text.RegexOption enum class must exist in symbol table")
    }

    func testRegexOptionAllEnumEntriesAreRegistered() throws {
        let (sema, interner) = try makeSema()
        let entries = [
            "IGNORE_CASE", "MULTILINE", "DOT_MATCHES_ALL",
            "LITERAL", "UNIX_LINES", "COMMENTS", "CANON_EQ",
        ]
        for entry in entries {
            let fq = ["kotlin", "text", "RegexOption", entry].map { interner.intern($0) }
            XCTAssertNotNil(
                sema.symbols.lookup(fqName: fq),
                "RegexOption.\(entry) must be registered in symbol table"
            )
        }
    }

    // MARK: - 3. Regex member functions

    func testRegexMatchesIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let link = externalLink(
            fqPath: ["kotlin", "text", "Regex", "matches"],
            sema: sema,
            interner: interner
        )
        XCTAssertEqual(link, "kk_regex_matches", "Regex.matches must link to kk_regex_matches")
    }

    func testRegexContainsMatchInIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let link = externalLink(
            fqPath: ["kotlin", "text", "Regex", "containsMatchIn"],
            sema: sema,
            interner: interner
        )
        XCTAssertEqual(link, "kk_regex_containsMatchIn",
                       "Regex.containsMatchIn must link to kk_regex_containsMatchIn")
    }

    func testRegexFindIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let link = externalLink(
            fqPath: ["kotlin", "text", "Regex", "find"],
            sema: sema,
            interner: interner
        )
        XCTAssertEqual(link, "kk_regex_find", "Regex.find must link to kk_regex_find")
    }

    func testRegexFindAllIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let link = externalLink(
            fqPath: ["kotlin", "text", "Regex", "findAll"],
            sema: sema,
            interner: interner
        )
        XCTAssertEqual(link, "kk_regex_findAll", "Regex.findAll must link to kk_regex_findAll")
    }

    func testRegexMatchEntireIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let link = externalLink(
            fqPath: ["kotlin", "text", "Regex", "matchEntire"],
            sema: sema,
            interner: interner
        )
        XCTAssertEqual(link, "kk_regex_matchEntire",
                       "Regex.matchEntire must link to kk_regex_matchEntire")
    }

    func testRegexReplaceWithLambdaIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let link = externalLink(
            fqPath: ["kotlin", "text", "Regex", "replace"],
            sema: sema,
            interner: interner
        )
        XCTAssertEqual(link, "kk_regex_replace_lambda",
                       "Regex.replace(input, transform) must link to kk_regex_replace_lambda")
    }

    // MARK: - 4. Regex properties

    func testRegexPatternPropertyIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let link = externalLink(
            fqPath: ["kotlin", "text", "Regex", "pattern"],
            sema: sema,
            interner: interner
        )
        XCTAssertEqual(link, "kk_regex_pattern", "Regex.pattern must link to kk_regex_pattern")
    }

    func testRegexOptionsPropertyIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let link = externalLink(
            fqPath: ["kotlin", "text", "Regex", "options"],
            sema: sema,
            interner: interner
        )
        XCTAssertEqual(link, "kk_regex_options", "Regex.options must link to kk_regex_options")
    }

    func testRegexGroupNamesPropertyIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let link = externalLink(
            fqPath: ["kotlin", "text", "Regex", "groupNames"],
            sema: sema,
            interner: interner
        )
        XCTAssertEqual(link, "kk_regex_group_names",
                       "Regex.groupNames must link to kk_regex_group_names")
    }

    // MARK: - 5. Companion methods (fromLiteral)

    func testRegexFromLiteralCompanionMethodIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "text", "Regex", "Companion", "fromLiteral"]
            .map { interner.intern($0) }
        let syms = sema.symbols.lookupAll(fqName: fq)
        XCTAssertFalse(syms.isEmpty, "Regex.Companion.fromLiteral must be registered")
        let links = Set(syms.compactMap { sema.symbols.externalLinkName(for: $0) })
        XCTAssertTrue(
            links.contains("kk_regex_from_literal"),
            "Regex.fromLiteral must link to kk_regex_from_literal; found: \(links)"
        )
    }

    // MARK: - 6. MatchResult properties and functions

    func testMatchResultValueIsRegistered() throws {
        let (sema, interner) = try makeSema()
        // MatchResult.value has multiple registrations (on MatchResult and MatchGroup);
        // verify the MatchResult one exists.
        let fq = ["kotlin", "text", "MatchResult", "value"].map { interner.intern($0) }
        let syms = sema.symbols.lookupAll(fqName: fq)
        let links = Set(syms.compactMap { sema.symbols.externalLinkName(for: $0) })
        XCTAssertTrue(
            links.contains("kk_match_result_value"),
            "MatchResult.value must link to kk_match_result_value; found: \(links)"
        )
    }

    func testMatchResultRangeIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "text", "MatchResult", "range"].map { interner.intern($0) }
        let syms = sema.symbols.lookupAll(fqName: fq)
        let links = Set(syms.compactMap { sema.symbols.externalLinkName(for: $0) })
        XCTAssertTrue(
            links.contains("kk_match_result_range"),
            "MatchResult.range must link to kk_match_result_range; found: \(links)"
        )
    }

    func testMatchResultGroupsIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let link = externalLink(
            fqPath: ["kotlin", "text", "MatchResult", "groups"],
            sema: sema,
            interner: interner
        )
        XCTAssertEqual(link, "kk_match_result_groups",
                       "MatchResult.groups must link to kk_match_result_groups")
    }

    func testMatchResultGroupValuesIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let link = externalLink(
            fqPath: ["kotlin", "text", "MatchResult", "groupValues"],
            sema: sema,
            interner: interner
        )
        XCTAssertEqual(link, "kk_match_result_groupValues",
                       "MatchResult.groupValues must link to kk_match_result_groupValues")
    }

    func testMatchResultComponent1IsRegistered() throws {
        let (sema, interner) = try makeSema()
        let link = externalLink(
            fqPath: ["kotlin", "text", "MatchResult", "component1"],
            sema: sema,
            interner: interner
        )
        XCTAssertEqual(link, "kk_match_result_component1",
                       "MatchResult.component1() must link to kk_match_result_component1")
    }

    func testMatchResultComponent2IsRegistered() throws {
        let (sema, interner) = try makeSema()
        let link = externalLink(
            fqPath: ["kotlin", "text", "MatchResult", "component2"],
            sema: sema,
            interner: interner
        )
        XCTAssertEqual(link, "kk_match_result_component2",
                       "MatchResult.component2() must link to kk_match_result_component2")
    }

    func testMatchResultNextIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let link = externalLink(
            fqPath: ["kotlin", "text", "MatchResult", "next"],
            sema: sema,
            interner: interner
        )
        XCTAssertEqual(link, "kk_match_result_next",
                       "MatchResult.next() must link to kk_match_result_next")
    }

    // MARK: - 7. MatchGroupCollection

    func testMatchGroupCollectionGetByNameIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "text", "MatchGroupCollection", "get"].map { interner.intern($0) }
        let syms = sema.symbols.lookupAll(fqName: fq)
        let links = Set(syms.compactMap { sema.symbols.externalLinkName(for: $0) })
        XCTAssertTrue(
            links.contains("kk_match_group_collection_get"),
            "MatchGroupCollection.get(name) must link to kk_match_group_collection_get; found: \(links)"
        )
    }

    func testMatchGroupCollectionGetByIndexIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "text", "MatchGroupCollection", "get"].map { interner.intern($0) }
        let syms = sema.symbols.lookupAll(fqName: fq)
        let links = Set(syms.compactMap { sema.symbols.externalLinkName(for: $0) })
        XCTAssertTrue(
            links.contains("kk_match_group_collection_get_at"),
            "MatchGroupCollection.get(index) must link to kk_match_group_collection_get_at; found: \(links)"
        )
    }

    func testMatchGroupCollectionHasBothGetOverloads() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "text", "MatchGroupCollection", "get"].map { interner.intern($0) }
        let syms = sema.symbols.lookupAll(fqName: fq)
        XCTAssertGreaterThanOrEqual(
            syms.count, 2,
            "MatchGroupCollection.get must have at least 2 overloads (by-name and by-index)"
        )
    }

    // MARK: - 8. MatchGroup properties

    func testMatchGroupValueIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let link = externalLink(
            fqPath: ["kotlin", "text", "MatchGroup", "value"],
            sema: sema,
            interner: interner
        )
        XCTAssertEqual(link, "kk_match_group_value",
                       "MatchGroup.value must link to kk_match_group_value")
    }

    func testMatchGroupRangeIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let link = externalLink(
            fqPath: ["kotlin", "text", "MatchGroup", "range"],
            sema: sema,
            interner: interner
        )
        XCTAssertEqual(link, "kk_match_group_range",
                       "MatchGroup.range must link to kk_match_group_range")
    }

    // MARK: - 9. String extension: replaceFirst / split with Regex

    func testStringReplaceFirstWithRegexIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fq = ["kotlin", "text", "replaceFirst"].map { interner.intern($0) }
        let syms = sema.symbols.lookupAll(fqName: fq)
        let links = Set(syms.compactMap { sema.symbols.externalLinkName(for: $0) })
        XCTAssertTrue(
            links.contains("kk_string_replaceFirst_regex"),
            "kotlin.text.replaceFirst(Regex, String) must link to kk_string_replaceFirst_regex; found: \(links)"
        )
    }

    func testStringSplitWithRegexIsRegistered() throws {
        let (sema, interner) = try makeSema()
        // String.split(Regex) is registered in HeaderHelpers+SyntheticStringStubs
        // as kotlin.text.split with externalLinkName kk_string_split_regex.
        let fq = ["kotlin", "text", "split"].map { interner.intern($0) }
        let syms = sema.symbols.lookupAll(fqName: fq)
        let links = Set(syms.compactMap { sema.symbols.externalLinkName(for: $0) })
        XCTAssertTrue(
            links.contains("kk_string_split_regex"),
            "kotlin.text.split(Regex) must link to kk_string_split_regex; found: \(links)"
        )
    }

    // MARK: - 10. Call-site resolution: constructors resolve in Kotlin source

    func testRegexSingleArgConstructorResolvesInCallExpr() throws {
        // Verify that Regex(pattern: String) compiles without sema errors.
        // Symbol-level verification is covered by testRegexSingleArgConstructorIsRegistered
        // and testAllThreeRegexConstructorOverloadsArePresent.
        let source = """
        fun test() {
            val r = Regex("[a-z]+")
            println(r.containsMatchIn("abc"))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Regex(pattern) should compile without sema errors"
            )
        }
    }

    func testRegexSingleOptionConstructorResolvesInCallExpr() throws {
        let source = """
        fun test() {
            val r = Regex("hello", RegexOption.IGNORE_CASE)
            println(r.matches("HELLO"))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            let regexCallExprs = allExprIDs(in: ast) { _, expr in
                guard case let .call(callee, _, _, _) = expr,
                      case let .nameRef(calleeName, _) = ast.arena.expr(callee)
                else { return false }
                return ctx.interner.resolve(calleeName) == "Regex"
            }

            // Pick the call with 2 arguments (the one with an option)
            let twoArgCall = regexCallExprs.first { exprID in
                guard case let .call(_, _, args, _) = ast.arena.expr(exprID) else { return false }
                return args.count == 2
            }
            let callExpr = try XCTUnwrap(twoArgCall, "Expected Regex(pattern, option) call")
            let binding = try XCTUnwrap(sema.bindings.callBinding(for: callExpr))
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: binding.chosenCallee),
                "kk_regex_create_with_option"
            )
        }
    }

    func testRegexMatchesMemberCallResolvesCorrectly() throws {
        let source = """
        fun test() {
            val r = Regex("^\\\\d+$")
            println(r.matches("123"))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "matches"
            }, "Expected .matches(...) member call")

            let binding = try XCTUnwrap(sema.bindings.callBinding(for: callExpr))
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: binding.chosenCallee),
                "kk_regex_matches"
            )
        }
    }

    func testRegexContainsMatchInMemberCallResolvesCorrectly() throws {
        let source = """
        fun test() {
            val r = Regex("[a-z]+")
            println(r.containsMatchIn("hello world"))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "containsMatchIn"
            }, "Expected .containsMatchIn(...) member call")

            let binding = try XCTUnwrap(sema.bindings.callBinding(for: callExpr))
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: binding.chosenCallee),
                "kk_regex_containsMatchIn"
            )
        }
    }

    func testRegexFindMemberCallResolvesCorrectly() throws {
        let source = """
        fun test() {
            val r = Regex("\\\\d+")
            val m = r.find("abc123")
            println(m?.value)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "find"
            }, "Expected .find(...) member call")

            let binding = try XCTUnwrap(sema.bindings.callBinding(for: callExpr))
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: binding.chosenCallee),
                "kk_regex_find"
            )
        }
    }

    func testRegexMatchEntireMemberCallResolvesCorrectly() throws {
        let source = """
        fun test() {
            val r = Regex("[a-z]+")
            val m = r.matchEntire("hello")
            println(m?.value)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "matchEntire"
            }, "Expected .matchEntire(...) member call")

            let binding = try XCTUnwrap(sema.bindings.callBinding(for: callExpr))
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: binding.chosenCallee),
                "kk_regex_matchEntire"
            )
        }
    }

    func testRegexFromLiteralCallResolvesCorrectly() throws {
        let source = """
        fun test() {
            val r = Regex.fromLiteral("hello.world")
            println(r.matches("hello.world"))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                return ctx.interner.resolve(callee) == "fromLiteral"
            }, "Expected .fromLiteral(...) member call")

            let binding = try XCTUnwrap(sema.bindings.callBinding(for: callExpr))
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: binding.chosenCallee),
                "kk_regex_from_literal"
            )
        }
    }

    // MARK: - 11. Named group access resolves at call site

    func testNamedGroupAccessChainResolves() throws {
        let source = """
        fun test() {
            val r = Regex("(?<year>\\\\d{4})-(?<month>\\\\d{2})")
            val m = r.find("2025-04")
            val year = m?.groups?.get("year")?.value
            println(year)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            // No diagnostics expected for valid named-group access chain.
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Named group access chain should produce no sema errors"
            )
        }
    }

    // MARK: - 12. Option combination (setOf) compiles without sema errors

    func testRegexOptionSetCombinationCompiles() throws {
        let source = """
        fun test() {
            val r = Regex(
                "^hello",
                setOf(RegexOption.IGNORE_CASE, RegexOption.MULTILINE, RegexOption.DOT_MATCHES_ALL)
            )
            println(r.containsMatchIn("HELLO"))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Regex option set combination should compile without sema errors"
            )
        }
    }

    // MARK: - 13. Empty pattern compiles

    func testEmptyPatternCompiles() throws {
        let source = """
        fun test() {
            val r = Regex("")
            println(r.matches(""))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Empty pattern Regex should compile without sema errors"
            )
        }
    }

    // MARK: - 14. Unicode pattern compiles

    func testUnicodePatternCompiles() throws {
        let source = """
        fun test() {
            val r = Regex("[\\u00C0-\\u024F]+")
            println(r.matches("café"))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Unicode pattern Regex should compile without sema errors"
            )
        }
    }

    // MARK: - 15. Symbol table completeness: all mandatory API symbols present

    func testMandatoryAPISymbolsAreAllRegistered() throws {
        let (sema, interner) = try makeSema()

        // Each (fqPath, expectedLinkName) pair must be present.
        // nil linkName means we only check symbol existence, not the link.
        let mandatoryLinks: [([String], String)] = [
            // Constructors (top-level in kotlin.text)
            (["kotlin", "text", "Regex"], "kk_regex_create"),
            (["kotlin", "text", "Regex"], "kk_regex_create_with_option"),
            (["kotlin", "text", "Regex"], "kk_regex_create_with_options"),
            // Member functions
            (["kotlin", "text", "Regex", "matches"], "kk_regex_matches"),
            (["kotlin", "text", "Regex", "containsMatchIn"], "kk_regex_containsMatchIn"),
            (["kotlin", "text", "Regex", "find"], "kk_regex_find"),
            (["kotlin", "text", "Regex", "findAll"], "kk_regex_findAll"),
            (["kotlin", "text", "Regex", "matchEntire"], "kk_regex_matchEntire"),
            (["kotlin", "text", "Regex", "replace"], "kk_regex_replace_lambda"),
            // Properties
            (["kotlin", "text", "Regex", "pattern"], "kk_regex_pattern"),
            (["kotlin", "text", "Regex", "options"], "kk_regex_options"),
            (["kotlin", "text", "Regex", "groupNames"], "kk_regex_group_names"),
            // Companion
            (["kotlin", "text", "Regex", "Companion", "fromLiteral"], "kk_regex_from_literal"),
            // MatchResult
            (["kotlin", "text", "MatchResult", "value"], "kk_match_result_value"),
            (["kotlin", "text", "MatchResult", "range"], "kk_match_result_range"),
            (["kotlin", "text", "MatchResult", "groups"], "kk_match_result_groups"),
            (["kotlin", "text", "MatchResult", "groupValues"], "kk_match_result_groupValues"),
            (["kotlin", "text", "MatchResult", "component1"], "kk_match_result_component1"),
            (["kotlin", "text", "MatchResult", "component2"], "kk_match_result_component2"),
            (["kotlin", "text", "MatchResult", "next"], "kk_match_result_next"),
            // MatchGroup
            (["kotlin", "text", "MatchGroup", "value"], "kk_match_group_value"),
            (["kotlin", "text", "MatchGroup", "range"], "kk_match_group_range"),
            // MatchGroupCollection
            (["kotlin", "text", "MatchGroupCollection", "get"], "kk_match_group_collection_get"),
            (["kotlin", "text", "MatchGroupCollection", "get"], "kk_match_group_collection_get_at"),
            // String extensions
            (["kotlin", "text", "replaceFirst"], "kk_string_replaceFirst_regex"),
            (["kotlin", "text", "split"], "kk_string_split_regex"),
        ]

        for (fqPath, expectedLink) in mandatoryLinks {
            let links = allExternalLinks(fqPath: fqPath, sema: sema, interner: interner)
            XCTAssertTrue(
                links.contains(expectedLink),
                "Missing API: \(fqPath.joined(separator: ".")) -> \(expectedLink) (found: \(links))"
            )
        }
    }

    // MARK: - Helpers

    private func allExprIDs(
        in ast: ASTModule,
        where predicate: (ExprID, Expr) -> Bool
    ) -> [ExprID] {
        ast.arena.exprs.indices.compactMap { index in
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID), predicate(exprID, expr) else {
                return nil
            }
            return exprID
        }
    }
}
