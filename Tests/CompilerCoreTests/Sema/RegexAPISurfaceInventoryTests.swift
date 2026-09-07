#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

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

@Suite
struct RegexAPISurfaceInventoryTests {

    // MARK: - Shared sema fixture

    private static nonisolated(unsafe) var _sharedSema: (SemaModule, StringInterner)?

    private func sharedSema() throws -> (SemaModule, StringInterner) {
        if let cached = Self._sharedSema { return cached }
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try #require(ctx.sema)
            result = (sema, ctx.interner)
        }
        let semaResult = try #require(result)
        Self._sharedSema = semaResult
        return semaResult
    }

    // MARK: - Shared source fixture for call-site tests

    private static let regexSourceSamples: [String] = [
        """
        package sample0
        fun test0() {
            val r = Regex("[a-z]+")
            println(r.containsMatchIn("abc"))
        }
        """,
        """
        package sample1
        fun test1() {
            val r = Regex("hello", RegexOption.IGNORE_CASE)
            println(r.matches("HELLO"))
        }
        """,
        """
        package sample2
        fun test2() {
            val r = Regex("^\\\\d+$")
            println(r.matches("123"))
        }
        """,
        """
        package sample3
        fun test3() {
            val r = Regex("[a-z]+")
            println(r.containsMatchIn("hello world"))
        }
        """,
        """
        package sample4
        fun test4() {
            val r = Regex("\\\\d+")
            val m = r.find("abc123")
            println(m?.value)
        }
        """,
        """
        package sample5
        fun test5() {
            val r = Regex("[a-z]+")
            val m = r.matchEntire("hello")
            println(m?.value)
        }
        """,
        """
        package sample6
        fun test6() {
            val r = Regex.fromLiteral("hello.world")
            println(r.matches("hello.world"))
        }
        """,
        """
        package sample7
        fun test7() {
            val r = Regex("(?<year>\\\\d{4})-(?<month>\\\\d{2})")
            val m = r.find("2025-04")
            val year = m?.groups?.get("year")?.value
            println(year)
        }
        """,
        """
        package sample8
        fun test8() {
            val r = Regex(
                "^hello",
                setOf(RegexOption.IGNORE_CASE, RegexOption.MULTILINE, RegexOption.DOT_MATCHES_ALL)
            )
            println(r.containsMatchIn("HELLO"))
        }
        """,
        """
        package sample9
        fun test9() {
            val r = Regex("")
            println(r.matches(""))
        }
        """,
        """
        package sample10
        fun test10() {
            val r = Regex("[\\u00C0-\\u024F]+")
            println(r.matches("café"))
        }
        """,
    ]

    private static nonisolated(unsafe) var _sharedSourceCtx: (CompilationContext, [String])?

    private func sharedSourceCtx() throws -> (CompilationContext, [String]) {
        if let cached = Self._sharedSourceCtx { return cached }
        var result: (CompilationContext, [String])?
        try withTemporaryFiles(contents: Self.regexSourceSamples) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            result = (ctx, paths)
        }
        let ctxAndPaths = try #require(result)
        Self._sharedSourceCtx = ctxAndPaths
        return ctxAndPaths
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

    @Test func testRegexSingleArgConstructorIsRegistered() throws {
        let (sema, interner) = try sharedSema()
        // Regex(pattern: String) -> Regex
        let links = allExternalLinks(
            fqPath: ["kotlin", "text", "Regex", "<init>"],
            sema: sema,
            interner: interner
        )
        #expect(
            links.contains("__kk_regex_create_flat"),
            "Regex(pattern) constructor must link to __kk_regex_create_flat"
        )
    }

    @Test func testRegexSingleOptionConstructorIsRegistered() throws {
        let (sema, interner) = try sharedSema()
        // Regex(pattern: String, option: RegexOption) -> Regex
        let links = allExternalLinks(
            fqPath: ["kotlin", "text", "Regex", "<init>"],
            sema: sema,
            interner: interner
        )
        #expect(
            links.contains("__kk_regex_create_with_option_flat"),
            "Regex(pattern, option) constructor must link to __kk_regex_create_with_option_flat"
        )
    }

    @Test func testRegexSetOptionsConstructorIsRegistered() throws {
        let (sema, interner) = try sharedSema()
        // Regex(pattern: String, options: Set<RegexOption>) -> Regex
        let links = allExternalLinks(
            fqPath: ["kotlin", "text", "Regex", "<init>"],
            sema: sema,
            interner: interner
        )
        #expect(
            links.contains("__kk_regex_create_with_options_flat"),
            "Regex(pattern, options) constructor must link to __kk_regex_create_with_options_flat"
        )
    }

    @Test func testAllThreeRegexConstructorOverloadsArePresent() throws {
        let (sema, interner) = try sharedSema()
        let links = allExternalLinks(
            fqPath: ["kotlin", "text", "Regex", "<init>"],
            sema: sema,
            interner: interner
        )
        let required: Set<String> = [
            "__kk_regex_create_flat",
            "__kk_regex_create_with_option_flat",
            "__kk_regex_create_with_options_flat",
        ]
        #expect(
            required.isSubset(of: links),
            Comment(rawValue: "All three Regex constructor overloads must be registered; found: \(links)")
        )
    }

    // MARK: - 2. RegexOption enum entries

    @Test func testRegexOptionEnumClassIsRegistered() throws {
        let (sema, interner) = try sharedSema()
        let fq = ["kotlin", "text", "RegexOption"].map { interner.intern($0) }
        let sym = sema.symbols.lookup(fqName: fq)
        #expect(sym != nil, "kotlin.text.RegexOption enum class must exist in symbol table")
    }

    @Test func testRegexOptionAllEnumEntriesAreRegistered() throws {
        let (sema, interner) = try sharedSema()
        let entries = [
            "IGNORE_CASE", "MULTILINE", "DOT_MATCHES_ALL",
            "LITERAL", "UNIX_LINES", "COMMENTS", "CANON_EQ",
        ]
        for entry in entries {
            let fq = ["kotlin", "text", "RegexOption", entry].map { interner.intern($0) }
            #expect(
                sema.symbols.lookup(fqName: fq) != nil,
                Comment(rawValue: "RegexOption.\(entry) must be registered in symbol table")
            )
        }
    }

    // MARK: - 3. Regex member functions

    @Test func testRegexMatchesIsRegistered() throws {
        let (sema, interner) = try sharedSema()
        let link = externalLink(
            fqPath: ["kotlin", "text", "Regex", "matches"],
            sema: sema,
            interner: interner
        )
        #expect(link == "__kk_regex_matches_flat", "Regex.matches must link to kk_regex_matches")
    }

    @Test func testRegexContainsMatchInIsRegistered() throws {
        let (sema, interner) = try sharedSema()
        let link = externalLink(
            fqPath: ["kotlin", "text", "Regex", "containsMatchIn"],
            sema: sema,
            interner: interner
        )
        #expect(link == "__kk_regex_containsMatchIn_flat",
                       "Regex.containsMatchIn must link to kk_regex_containsMatchIn")
    }

    @Test func testRegexFindIsRegistered() throws {
        let (sema, interner) = try sharedSema()
        let link = externalLink(
            fqPath: ["kotlin", "text", "Regex", "find"],
            sema: sema,
            interner: interner
        )
        #expect(link == "__kk_regex_find_flat", "Regex.find must link to kk_regex_find")
    }

    @Test func testRegexFindAllIsRegistered() throws {
        let (sema, interner) = try sharedSema()
        let link = externalLink(
            fqPath: ["kotlin", "text", "Regex", "findAll"],
            sema: sema,
            interner: interner
        )
        #expect(link == "__kk_regex_findAll_flat", "Regex.findAll must link to kk_regex_findAll")
    }

    @Test func testRegexMatchEntireIsRegistered() throws {
        let (sema, interner) = try sharedSema()
        let link = externalLink(
            fqPath: ["kotlin", "text", "Regex", "matchEntire"],
            sema: sema,
            interner: interner
        )
        #expect(link == "__kk_regex_matchEntire_flat",
                       "Regex.matchEntire must link to kk_regex_matchEntire")
    }

    @Test func testRegexReplaceWithLambdaIsRegistered() throws {
        let (sema, interner) = try sharedSema()
        let links = allExternalLinks(
            fqPath: ["kotlin", "text", "Regex", "replace"],
            sema: sema,
            interner: interner
        )
        #expect(
            links.contains("__kk_regex_replace_lambda"),
            "Regex.replace(input, transform) must link to __kk_regex_replace_lambda"
        )
    }

    // MARK: - 4. Regex properties (KSP-486: migrated to bundled Kotlin source)

    @Test func testRegexAccessorsAreNoLongerRuntimeLinked() throws {
        let (sema, _) = try sharedSema()
        let removed = ["kk_regex_pattern", "kk_regex_options", "kk_regex_group_names"]
        let present = registeredLinkNames(sema: sema).intersection(removed)
        #expect(
            present.isEmpty,
            Comment(rawValue: "Regex.pattern/options/groupNames are Kotlin source now; stale links: \(present)")
        )
    }

    // MARK: - 5. Companion methods (fromLiteral)

    @Test func testRegexFromLiteralCompanionMethodIsRegistered() throws {
        let (sema, interner) = try sharedSema()
        let fq = ["kotlin", "text", "Regex", "Companion", "fromLiteral"]
            .map { interner.intern($0) }
        let syms = sema.symbols.lookupAll(fqName: fq)
        #expect(!(syms.isEmpty), "Regex.Companion.fromLiteral must be registered")
        let links = Set(syms.compactMap { sema.symbols.externalLinkName(for: $0) })
        #expect(
            links.contains("__kk_regex_from_literal_flat"),
            Comment(rawValue: "Regex.fromLiteral must link to kk_regex_from_literal; found: \(links)")
        )
    }

    // MARK: - 6-8. MatchResult / MatchGroup layer (KSP-486: Kotlin source)

    /// The whole MatchResult / MatchGroup / MatchGroupCollection / Destructured
    /// public layer lives in `__bundled_kotlin/text/MatchResult.kt`; only the raw
    /// match-position `__kk_*` bridges remain in the runtime.
    @Test func testMatchResultLayerIsNoLongerRuntimeLinked() throws {
        let (sema, _) = try sharedSema()
        var removed: Set<String> = [
            "kk_match_result_value",
            "kk_match_result_range",
            "kk_match_result_groups",
            "kk_match_result_groupValues",
            "kk_match_result_component1",
            "kk_match_result_component2",
            "kk_match_result_next",
            "kk_match_result_destructured",
            "kk_match_result_destructured_match",
            "kk_match_group_collection_get",
            "kk_match_group_collection_get_at",
            "kk_match_group_collection_size",
            "kk_match_group_value",
            "kk_match_group_range",
        ]
        for index in 1 ... 9 {
            removed.insert("kk_match_result_destructured_component\(index)")
        }
        let present = registeredLinkNames(sema: sema).intersection(removed)
        #expect(
            present.isEmpty,
            Comment(rawValue: "MatchResult/MatchGroup layer is Kotlin source now; stale links: \(present)")
        )
    }

    /// The remaining raw bridges must stay wired, since the Kotlin layer calls them.
    @Test func testRawMatchDataBridgesAreRegistered() throws {
        let (sema, _) = try sharedSema()
        let bridges: Set<String> = [
            "__kk_match_result_group_count",
            "__kk_match_result_group_value",
            "__kk_match_result_group_start",
            "__kk_match_result_group_end",
            "__kk_match_result_group_index_of_name",
            "__kk_match_result_has_named_group",
            "__kk_match_result_next",
            "__kk_match_result_destructured",
            "__kk_match_result_destructured_match",
            "__kk_regex_pattern",
            "__kk_regex_option_mask",
        ]
        let missing = bridges.subtracting(registeredLinkNames(sema: sema))
        #expect(missing.isEmpty, Comment(rawValue: "Missing raw match-data bridges: \(missing)"))
    }

    // MARK: - 9. String extension: replaceFirst / split with Regex

    @Test func testStringReplaceFirstWithRegexIsRegistered() throws {
        let (sema, interner) = try sharedSema()
        let links = allExternalLinks(
            fqPath: ["kotlin", "text", "replaceFirst"],
            sema: sema,
            interner: interner
        )
        #expect(
            !links.contains("__kk_string_replaceFirst_regex"),
            Comment(rawValue: "kotlin.text.replaceFirst(Regex, String) must be source-backed; found: \(links)")
        )
        let bridgeLink = externalLink(
            fqPath: ["kotlin", "text", "__kk_replaceFirst_regex"],
            sema: sema,
            interner: interner
        )
        #expect(
            bridgeLink == "__kk_string_replaceFirst_regex",
            Comment(rawValue: "StringSearchReplace bridge must link to __kk_string_replaceFirst_regex; found: \(bridgeLink ?? "nil")")
        )
    }

    @Test func testStringSplitWithRegexIsRegistered() throws {
        let (sema, interner) = try sharedSema()
        let links = allExternalLinks(
            fqPath: ["kotlin", "text", "split"],
            sema: sema,
            interner: interner
        )
        #expect(
            !links.contains("__kk_string_split_regex_flat"),
            Comment(rawValue: "kotlin.text.split(Regex) must be source-backed; found: \(links)")
        )
        let bridgeLink = externalLink(
            fqPath: ["kotlin", "text", "__kk_split_regex"],
            sema: sema,
            interner: interner
        )
        #expect(
            bridgeLink == "__kk_string_split_regex_flat",
            Comment(rawValue: "StringSearchReplace bridge must link to __kk_string_split_regex_flat; found: \(bridgeLink ?? "nil")")
        )
    }

    // MARK: - Path-aware expression search helpers

    private func allExprIDs(
        in ast: ASTModule,
        path: String,
        ctx: CompilationContext,
        where predicate: (ExprID, Expr) -> Bool
    ) -> [ExprID] {
        var results: [ExprID] = []
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID) else { continue }
            guard let range = ast.arena.exprRange(exprID), ctx.sourceManager.path(of: range.start.file) == path else { continue }
            if predicate(exprID, expr) { results.append(exprID) }
        }
        return results
    }

    private func firstExprID(
        in ast: ASTModule,
        path: String,
        ctx: CompilationContext,
        where predicate: (ExprID, Expr) -> Bool
    ) -> ExprID? {
        for index in ast.arena.exprs.indices {
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID) else { continue }
            guard let range = ast.arena.exprRange(exprID), ctx.sourceManager.path(of: range.start.file) == path else { continue }
            if predicate(exprID, expr) { return exprID }
        }
        return nil
    }

    // MARK: - 10. Call-site resolution: constructors resolve in Kotlin source

    @Test func testRegexSingleArgConstructorResolvesInCallExpr() throws {
        let (ctx, paths) = try sharedSourceCtx()
        _ = paths[0]
        #expect(
            !(ctx.diagnostics.hasError),
            "Regex(pattern) should compile without sema errors"
        )
    }

    @Test func testRegexSingleOptionConstructorResolvesInCallExpr() throws {
        let (ctx, paths) = try sharedSourceCtx()
        let path = paths[1]

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)

        let regexCallExprs = allExprIDs(in: ast, path: path, ctx: ctx) { _, expr in
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
        let callExpr = try #require(twoArgCall, "Expected Regex(pattern, option) call")
        let binding = try #require(sema.bindings.callBinding(for: callExpr))
        #expect(
            sema.symbols.externalLinkName(for: binding.chosenCallee) == "__kk_regex_create_with_option_flat"
        )
    }

    @Test func testRegexMatchesMemberCallResolvesCorrectly() throws {
        let (ctx, paths) = try sharedSourceCtx()
        let path = paths[2]

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)

        let callExpr = try #require(firstExprID(in: ast, path: path, ctx: ctx) { _, expr in
            guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
            return ctx.interner.resolve(callee) == "matches"
        }, "Expected .matches(...) member call")

        let binding = try #require(sema.bindings.callBinding(for: callExpr))
        #expect(
            sema.symbols.externalLinkName(for: binding.chosenCallee) == "__kk_regex_matches_flat"
        )
    }

    @Test func testRegexContainsMatchInMemberCallResolvesCorrectly() throws {
        let (ctx, paths) = try sharedSourceCtx()
        let path = paths[3]

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)

        let callExpr = try #require(firstExprID(in: ast, path: path, ctx: ctx) { _, expr in
            guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
            return ctx.interner.resolve(callee) == "containsMatchIn"
        }, "Expected .containsMatchIn(...) member call")

        let binding = try #require(sema.bindings.callBinding(for: callExpr))
        #expect(
            sema.symbols.externalLinkName(for: binding.chosenCallee) == "__kk_regex_containsMatchIn_flat"
        )
    }

    @Test func testRegexFindMemberCallResolvesCorrectly() throws {
        let (ctx, paths) = try sharedSourceCtx()
        let path = paths[4]

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)

        let callExpr = try #require(firstExprID(in: ast, path: path, ctx: ctx) { _, expr in
            guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
            return ctx.interner.resolve(callee) == "find"
        }, "Expected .find(...) member call")

        let binding = try #require(sema.bindings.callBinding(for: callExpr))
        #expect(
            sema.symbols.externalLinkName(for: binding.chosenCallee) == "__kk_regex_find_flat"
        )
    }

    @Test func testRegexMatchEntireMemberCallResolvesCorrectly() throws {
        let (ctx, paths) = try sharedSourceCtx()
        let path = paths[5]

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)

        let callExpr = try #require(firstExprID(in: ast, path: path, ctx: ctx) { _, expr in
            guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
            return ctx.interner.resolve(callee) == "matchEntire"
        }, "Expected .matchEntire(...) member call")

        let binding = try #require(sema.bindings.callBinding(for: callExpr))
        #expect(
            sema.symbols.externalLinkName(for: binding.chosenCallee) == "__kk_regex_matchEntire_flat"
        )
    }

    @Test func testRegexFromLiteralCallResolvesCorrectly() throws {
        let (ctx, paths) = try sharedSourceCtx()
        let path = paths[6]

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)

        let callExpr = try #require(firstExprID(in: ast, path: path, ctx: ctx) { _, expr in
            guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
            return ctx.interner.resolve(callee) == "fromLiteral"
        }, "Expected .fromLiteral(...) member call")

        let binding = try #require(sema.bindings.callBinding(for: callExpr))
        #expect(
            sema.symbols.externalLinkName(for: binding.chosenCallee) == "__kk_regex_from_literal_flat"
        )
    }

    // MARK: - 11. Named group access resolves at call site

    @Test func testNamedGroupAccessChainResolves() throws {
        let (ctx, paths) = try sharedSourceCtx()
        _ = paths[7]
        // No diagnostics expected for valid named-group access chain.
        #expect(
            !(ctx.diagnostics.hasError),
            "Named group access chain should produce no sema errors"
        )
    }

    // MARK: - 12. Option combination (setOf) compiles without sema errors

    @Test func testRegexOptionSetCombinationCompiles() throws {
        let (ctx, paths) = try sharedSourceCtx()
        _ = paths[8]
        #expect(
            !(ctx.diagnostics.hasError),
            "Regex option set combination should compile without sema errors"
        )
    }

    // MARK: - 13. Empty pattern compiles

    @Test func testEmptyPatternCompiles() throws {
        let (ctx, paths) = try sharedSourceCtx()
        _ = paths[9]
        #expect(
            !(ctx.diagnostics.hasError),
            "Empty pattern Regex should compile without sema errors"
        )
    }

    // MARK: - 14. Unicode pattern compiles

    @Test func testUnicodePatternCompiles() throws {
        let (ctx, paths) = try sharedSourceCtx()
        _ = paths[10]
        #expect(
            !(ctx.diagnostics.hasError),
            "Unicode pattern Regex should compile without sema errors"
        )
    }

    // MARK: - 15. Symbol table completeness: all mandatory API symbols present

    @Test func testMandatoryAPISymbolsAreAllRegistered() throws {
        let (sema, interner) = try sharedSema()

        // Each (fqPath, expectedLinkName) pair must be present.
        // nil linkName means we only check symbol existence, not the link.
        let mandatoryLinks: [([String], String)] = [
            // Constructors (class <init> in kotlin.text)
            (["kotlin", "text", "Regex", "<init>"], "__kk_regex_create_flat"),
            (["kotlin", "text", "Regex", "<init>"], "__kk_regex_create_with_option_flat"),
            (["kotlin", "text", "Regex", "<init>"], "__kk_regex_create_with_options_flat"),
            // Member functions
            (["kotlin", "text", "Regex", "matches"], "__kk_regex_matches_flat"),
            (["kotlin", "text", "Regex", "containsMatchIn"], "__kk_regex_containsMatchIn_flat"),
            (["kotlin", "text", "Regex", "find"], "__kk_regex_find_flat"),
            (["kotlin", "text", "Regex", "findAll"], "__kk_regex_findAll_flat"),
            (["kotlin", "text", "Regex", "matchEntire"], "__kk_regex_matchEntire_flat"),
            (["kotlin", "text", "Regex", "replace"], "__kk_regex_replace_lambda"),
            // Companion
            (["kotlin", "text", "Regex", "Companion", "fromLiteral"], "__kk_regex_from_literal_flat"),
            // String extension runtime bridges
            (["kotlin", "text", "__kk_string_matches_regex"], "__kk_string_matches_regex_flat"),
            (["kotlin", "text", "__kk_string_contains_regex"], "__kk_string_contains_regex_flat"),
            (["kotlin", "text", "__kk_replace_regex"], "__kk_string_replace_regex"),
            (["kotlin", "text", "__kk_replaceFirst_regex"], "__kk_string_replaceFirst_regex"),
            (["kotlin", "text", "__kk_split_regex"], "__kk_string_split_regex_flat"),
            (["kotlin", "text", "__kk_string_toRegex"], "__kk_string_toRegex_flat"),
            (["kotlin", "text", "__kk_string_toRegex_with_option"], "__kk_string_toRegex_with_option_flat"),
            (["kotlin", "text", "__kk_string_toRegex_with_options"], "__kk_string_toRegex_with_options_flat"),
        ]

        for (fqPath, expectedLink) in mandatoryLinks {
            let links = allExternalLinks(fqPath: fqPath, sema: sema, interner: interner)
            #expect(
                links.contains(expectedLink),
                Comment(rawValue: "Missing API: \(fqPath.joined(separator: ".")) -> \(expectedLink) (found: \(links))")
            )
        }

        // Public source-backed symbols must also be present (they have no external link themselves).
        let mandatoryPublicSymbols = [
            ["kotlin", "text", "Regex"],
            ["kotlin", "text", "matches"],
            ["kotlin", "text", "contains"],
            ["kotlin", "text", "toRegex"],
        ]
        for fqPath in mandatoryPublicSymbols {
            let interned = fqPath.map { interner.intern($0) }
            #expect(
                sema.symbols.lookup(fqName: interned) != nil,
                Comment(rawValue: "Missing public API symbol: \(fqPath.joined(separator: "."))")
            )
        }
    }

    // MARK: - Helpers

    /// Every external link name registered in the symbol table after sema.
    private func registeredLinkNames(sema: SemaModule) -> Set<String> {
        Set(sema.symbols.allSymbols().compactMap { sema.symbols.externalLinkName(for: $0.id) })
    }

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
#endif
