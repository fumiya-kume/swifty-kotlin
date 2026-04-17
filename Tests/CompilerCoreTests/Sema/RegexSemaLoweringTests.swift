@testable import CompilerCore
import Foundation
import XCTest

// MARK: - STDLIB-REGEX-002: Regex sema resolution and KIR lowering
//
// This file verifies:
//   1. Overload selection at call sites (disambiguates the three Regex constructor overloads)
//   2. RegexOption enum member dispatch (static field resolution)
//   3. Method dispatch for every Regex member (matches / containsMatchIn / find /
//      findAll / matchEntire / replace)
//   4. Named-capture-group access chains produce no sema errors and lower to KIR
//   5. toRegex() String extension lowers to kk_string_toRegex
//   6. String.split(Regex) and String.contains(Regex) lower to the correct KIR callees
//   7. Regex.replace with lambda lowers to kk_regex_replace_lambda
//   8. Regex.fromLiteral (companion) lowers to kk_regex_from_literal in KIR
//
// Scope: sema resolution + KIR lowering only. No runtime edits.
// Does NOT overlap with STDLIB-REGEX-001 (API inventory) or STDLIB-REGEX-003 (runtime).

final class RegexSemaLoweringTests: XCTestCase {

    // MARK: - Helpers

    /// Collect every callee name emitted across all KIR functions in a module.
    private func allCalleesInModule(_ module: KIRModule, interner: StringInterner) -> Set<String> {
        var result = Set<String>()
        for decl in module.arena.declarations {
            guard case let .function(function) = decl else { continue }
            result.formUnion(extractCallees(from: function.body, interner: interner))
        }
        return result
    }

    // MARK: - 1. Constructor overload selection (no-error sema checks)
    // Note: Regex constructors are resolved via the KIR lowering (not stored as
    // callBinding in the sema bindings table). The KIR-level overload tests in
    // section 5 below verify the correct callee is selected. These sema tests
    // confirm that each overload compiles without errors.

    func testSingleArgConstructorCompilesSemaClean() throws {
        let source = """
        fun test() {
            val r = Regex("[a-z]+")
            println(r.containsMatchIn("hello"))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(ctx.diagnostics.hasError,
                           "Single-arg Regex constructor must compile without sema errors")
        }
    }

    func testTwoArgOptionConstructorCompilesSemaClean() throws {
        let source = """
        fun test() {
            val r = Regex("foo", RegexOption.IGNORE_CASE)
            println(r.matches("FOO"))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(ctx.diagnostics.hasError,
                           "Two-arg Regex(String, RegexOption) constructor must compile without sema errors")
        }
    }

    func testTwoArgSetOptionsConstructorCompilesSemaClean() throws {
        let source = """
        fun test() {
            val r = Regex("bar", setOf(RegexOption.MULTILINE, RegexOption.DOT_MATCHES_ALL))
            println(r.containsMatchIn("bar"))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(ctx.diagnostics.hasError,
                           "Two-arg Regex(String, Set<RegexOption>) constructor must compile without sema errors")
        }
    }

    // MARK: - 2. RegexOption enum member dispatch

    func testRegexOptionIgnoreCaseResolvesSema() throws {
        let source = """
        fun test() {
            val opt = RegexOption.IGNORE_CASE
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "RegexOption.IGNORE_CASE must resolve without sema errors"
            )
        }
    }

    func testAllRegexOptionEntriesResolveWithoutErrors() throws {
        let entries = [
            "IGNORE_CASE", "MULTILINE", "DOT_MATCHES_ALL",
            "LITERAL", "UNIX_LINES", "COMMENTS", "CANON_EQ",
        ]
        for entry in entries {
            let source = """
            fun test() {
                val opt = RegexOption.\(entry)
            }
            """
            try withTemporaryFile(contents: source) { path in
                let ctx = makeCompilationContext(inputs: [path])
                try runSema(ctx)
                XCTAssertFalse(
                    ctx.diagnostics.hasError,
                    "RegexOption.\(entry) must resolve without sema errors"
                )
            }
        }
    }

    // MARK: - 3. Method dispatch for each Regex member

    func testMatchesBindingResolvesToKkRegexMatches() throws {
        let source = """
        fun test() {
            val r = Regex("^[0-9]+$")
            println(r.matches("42"))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            let callExpr = try XCTUnwrap(
                firstExprID(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return ctx.interner.resolve(callee) == "matches"
                },
                "Expected .matches(...) member call"
            )
            let binding = try XCTUnwrap(sema.bindings.callBinding(for: callExpr))
            XCTAssertEqual(sema.symbols.externalLinkName(for: binding.chosenCallee), "kk_regex_matches")
        }
    }

    func testFindAllBindingResolvesToKkRegexFindAll() throws {
        let source = """
        fun test() {
            val r = Regex("\\\\d+")
            val all = r.findAll("abc 1 def 2 ghi 3")
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            let callExpr = try XCTUnwrap(
                firstExprID(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return ctx.interner.resolve(callee) == "findAll"
                },
                "Expected .findAll(...) member call"
            )
            let binding = try XCTUnwrap(sema.bindings.callBinding(for: callExpr))
            XCTAssertEqual(sema.symbols.externalLinkName(for: binding.chosenCallee), "kk_regex_findAll")
        }
    }

    func testReplaceWithLambdaBindingResolvesToKkRegexReplaceLambda() throws {
        let source = """
        fun test() {
            val r = Regex("\\\\d+")
            val result = r.replace("abc 1 def 2") { m -> "[${m.value}]" }
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            let callExpr = try XCTUnwrap(
                firstExprID(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return ctx.interner.resolve(callee) == "replace"
                },
                "Expected .replace(...) member call"
            )
            let binding = try XCTUnwrap(sema.bindings.callBinding(for: callExpr))
            XCTAssertEqual(
                sema.symbols.externalLinkName(for: binding.chosenCallee),
                "kk_regex_replace_lambda"
            )
        }
    }

    // MARK: - 4. Named capture group access chain

    func testNamedGroupAccessChainProducesNoSemaErrors() throws {
        let source = """
        fun test() {
            val r = Regex("(?<year>\\\\d{4})-(?<month>\\\\d{2})-(?<day>\\\\d{2})")
            val m = r.find("2025-04-17")
            val year = m?.groups?.get("year")?.value
            println(year)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Named group access chain should have no sema errors"
            )
        }
    }

    func testGroupsByIndexAccessProducesNoSemaErrors() throws {
        let source = """
        fun test() {
            val r = Regex("(\\\\d+)-(\\\\w+)")
            val m = r.find("123-abc")
            val first = m?.groups?.get(1)?.value
            println(first)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Group-by-index access chain should have no sema errors"
            )
        }
    }

    func testGroupValuesListAccessProducesNoSemaErrors() throws {
        let source = """
        fun test() {
            val r = Regex("(\\\\d+)")
            val m = r.find("42")
            val vals = m?.groupValues
            println(vals)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "groupValues access should have no sema errors"
            )
        }
    }

    // MARK: - 5. KIR lowering: constructor calls emit correct KIR callees

    func testSingleArgRegexConstructorLowersToKkRegexCreate() throws {
        let source = """
        fun test() {
            val r = Regex("[a-z]+")
            println(r.matches("hello"))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            let module = try XCTUnwrap(ctx.kir)
            let callees = allCalleesInModule(module, interner: ctx.interner)
            XCTAssertTrue(
                callees.contains("kk_regex_create"),
                "KIR must contain kk_regex_create for single-arg constructor; found: \(callees)"
            )
        }
    }

    func testTwoArgOptionRegexConstructorLowersToKkRegexCreateWithOption() throws {
        let source = """
        fun test() {
            val r = Regex("foo", RegexOption.IGNORE_CASE)
            println(r.matches("FOO"))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            let module = try XCTUnwrap(ctx.kir)
            let callees = allCalleesInModule(module, interner: ctx.interner)
            XCTAssertTrue(
                callees.contains("kk_regex_create_with_option"),
                "KIR must contain kk_regex_create_with_option; found: \(callees)"
            )
        }
    }

    func testSetOptionsRegexConstructorLowersToKkRegexCreateWithOptions() throws {
        let source = """
        fun test() {
            val r = Regex("bar", setOf(RegexOption.MULTILINE, RegexOption.IGNORE_CASE))
            println(r.containsMatchIn("bar"))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            let module = try XCTUnwrap(ctx.kir)
            let callees = allCalleesInModule(module, interner: ctx.interner)
            XCTAssertTrue(
                callees.contains("kk_regex_create_with_options"),
                "KIR must contain kk_regex_create_with_options; found: \(callees)"
            )
        }
    }

    // MARK: - 6. KIR lowering: member calls emit correct KIR callees

    func testRegexMatchesLowersToKkRegexMatches() throws {
        let source = """
        fun test() {
            val r = Regex("^\\\\d+$")
            println(r.matches("123"))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            let module = try XCTUnwrap(ctx.kir)
            let callees = allCalleesInModule(module, interner: ctx.interner)
            XCTAssertTrue(callees.contains("kk_regex_matches"), "KIR must contain kk_regex_matches; found: \(callees)")
        }
    }

    func testRegexContainsMatchInLowersToKkRegexContainsMatchIn() throws {
        let source = """
        fun test() {
            val r = Regex("[a-z]+")
            println(r.containsMatchIn("hello world"))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            let module = try XCTUnwrap(ctx.kir)
            let callees = allCalleesInModule(module, interner: ctx.interner)
            XCTAssertTrue(callees.contains("kk_regex_containsMatchIn"), "KIR must contain kk_regex_containsMatchIn; found: \(callees)")
        }
    }

    func testRegexFindLowersToKkRegexFind() throws {
        let source = """
        fun test() {
            val r = Regex("\\\\d+")
            val m = r.find("abc123")
            println(m?.value)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            let module = try XCTUnwrap(ctx.kir)
            let callees = allCalleesInModule(module, interner: ctx.interner)
            XCTAssertTrue(callees.contains("kk_regex_find"), "KIR must contain kk_regex_find; found: \(callees)")
        }
    }

    func testRegexFindAllLowersToKkRegexFindAll() throws {
        let source = """
        fun test() {
            val r = Regex("\\\\d+")
            val ms = r.findAll("a1b2c3")
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            let module = try XCTUnwrap(ctx.kir)
            let callees = allCalleesInModule(module, interner: ctx.interner)
            XCTAssertTrue(callees.contains("kk_regex_findAll"), "KIR must contain kk_regex_findAll; found: \(callees)")
        }
    }

    func testRegexMatchEntireLowersToKkRegexMatchEntire() throws {
        let source = """
        fun test() {
            val r = Regex("[a-z]+")
            val m = r.matchEntire("hello")
            println(m?.value)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            let module = try XCTUnwrap(ctx.kir)
            let callees = allCalleesInModule(module, interner: ctx.interner)
            XCTAssertTrue(callees.contains("kk_regex_matchEntire"), "KIR must contain kk_regex_matchEntire; found: \(callees)")
        }
    }

    func testRegexReplaceWithLambdaLowersToKkRegexReplaceLambda() throws {
        let source = """
        fun test() {
            val r = Regex("\\\\d+")
            val result = r.replace("abc 1 def 2") { m -> "[${m.value}]" }
            println(result)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            let module = try XCTUnwrap(ctx.kir)
            let callees = allCalleesInModule(module, interner: ctx.interner)
            XCTAssertTrue(callees.contains("kk_regex_replace_lambda"), "KIR must contain kk_regex_replace_lambda; found: \(callees)")
        }
    }

    // MARK: - 7. KIR lowering: String.toRegex()

    func testStringToRegexLowersToKkStringToRegex() throws {
        let source = """
        fun test() {
            val r = "[a-z]+".toRegex()
            println(r.matches("abc"))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            let module = try XCTUnwrap(ctx.kir)
            let callees = allCalleesInModule(module, interner: ctx.interner)
            XCTAssertTrue(callees.contains("kk_string_toRegex"), "KIR must contain kk_string_toRegex; found: \(callees)")
        }
    }

    // MARK: - 8. KIR lowering: String.split(Regex) and String.contains(Regex)

    func testStringSplitWithRegexLowersToKkStringSplitRegex() throws {
        let source = """
        fun test() {
            val r = Regex("\\\\s+")
            val parts = "hello world  foo".split(r)
            println(parts)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            let module = try XCTUnwrap(ctx.kir)
            let callees = allCalleesInModule(module, interner: ctx.interner)
            XCTAssertTrue(callees.contains("kk_string_split_regex"), "KIR must contain kk_string_split_regex; found: \(callees)")
        }
    }

    func testStringContainsWithRegexLowersToKkStringContainsRegex() throws {
        let source = """
        fun test() {
            val r = Regex("\\\\d+")
            println("abc123".contains(r))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            let module = try XCTUnwrap(ctx.kir)
            let callees = allCalleesInModule(module, interner: ctx.interner)
            XCTAssertTrue(callees.contains("kk_string_contains_regex"), "KIR must contain kk_string_contains_regex; found: \(callees)")
        }
    }

    // MARK: - 9. KIR lowering: Regex.fromLiteral (companion)

    func testRegexFromLiteralLowersToKkRegexFromLiteral() throws {
        let source = """
        fun test() {
            val r = Regex.fromLiteral("hello.world")
            println(r.matches("hello.world"))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            let module = try XCTUnwrap(ctx.kir)
            let callees = allCalleesInModule(module, interner: ctx.interner)
            XCTAssertTrue(callees.contains("kk_regex_from_literal"), "KIR must contain kk_regex_from_literal; found: \(callees)")
        }
    }

    // MARK: - 10. KIR lowering: named group access chain produces kk_match_group_collection_get

    func testNamedGroupAccessChainLowersToKkMatchGroupCollectionGet() throws {
        let source = """
        fun test() {
            val r = Regex("(?<year>\\\\d{4})-(?<month>\\\\d{2})")
            val m = r.find("2025-04")
            val year = m?.groups?.get("year")?.value
            println(year)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            let module = try XCTUnwrap(ctx.kir)
            let callees = allCalleesInModule(module, interner: ctx.interner)
            XCTAssertTrue(
                callees.contains("kk_match_group_collection_get"),
                "KIR must contain kk_match_group_collection_get for named group access; found: \(callees)"
            )
        }
    }

    func testGroupsByIndexLowersToKkMatchGroupCollectionGetAt() throws {
        let source = """
        fun test() {
            val r = Regex("(\\\\d+)-(\\\\w+)")
            val m = r.find("123-abc")
            val first = m?.groups?.get(1)?.value
            println(first)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            let module = try XCTUnwrap(ctx.kir)
            let callees = allCalleesInModule(module, interner: ctx.interner)
            XCTAssertTrue(
                callees.contains("kk_match_group_collection_get_at"),
                "KIR must contain kk_match_group_collection_get_at for index-based group access; found: \(callees)"
            )
        }
    }

    // MARK: - 11. KIR lowering: MatchResult component calls

    func testMatchResultComponent1LowersCorrectly() throws {
        // Call component1() and component2() explicitly rather than via destructuring,
        // since the compiler lowers val (a, b) = m differently.
        let source = """
        fun test() {
            val r = Regex("(\\\\w+)")
            val m = r.find("hello")
            val v1 = m?.component1()
            val v2 = m?.component2()
            println(v1)
            println(v2)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToKIR(ctx)
            let module = try XCTUnwrap(ctx.kir)
            let callees = allCalleesInModule(module, interner: ctx.interner)
            XCTAssertTrue(
                callees.contains("kk_match_result_component1"),
                "KIR must contain kk_match_result_component1; found: \(callees)"
            )
            XCTAssertTrue(
                callees.contains("kk_match_result_component2"),
                "KIR must contain kk_match_result_component2; found: \(callees)"
            )
        }
    }

    // MARK: - 12. No stray sema errors on valid Regex programs

    func testComplexRegexProgramProducesNoSemaErrors() throws {
        let source = """
        fun parseDate(input: String): String? {
            val r = Regex("(?<year>\\\\d{4})-(?<month>\\\\d{2})-(?<day>\\\\d{2})")
            val m = r.find(input) ?: return null
            val year = m.groups.get("year")?.value ?: "?"
            val month = m.groups.get("month")?.value ?: "?"
            val day = m.groups.get("day")?.value ?: "?"
            return "$year/$month/$day"
        }
        fun main() {
            println(parseDate("2025-04-17"))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Complex Regex program must produce no sema errors"
            )
        }
    }

    func testRegexWithAllOptionCombinationsProducesNoSemaErrors() throws {
        let source = """
        fun test() {
            val r1 = Regex("hello", RegexOption.IGNORE_CASE)
            val r2 = Regex("world", RegexOption.MULTILINE)
            val r3 = Regex("foo", RegexOption.DOT_MATCHES_ALL)
            val r4 = Regex("bar", RegexOption.LITERAL)
            val r5 = Regex("baz", RegexOption.UNIX_LINES)
            val r6 = Regex("qux", RegexOption.COMMENTS)
            val r7 = Regex("quux", RegexOption.CANON_EQ)
            val rAll = Regex(
                ".*",
                setOf(RegexOption.IGNORE_CASE, RegexOption.MULTILINE,
                      RegexOption.DOT_MATCHES_ALL, RegexOption.LITERAL)
            )
        }
        """
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "All RegexOption combinations should compile without sema errors"
            )
        }
    }

    // MARK: - Local helpers

    private func allExprIDsIn(
        ast: ASTModule,
        where predicate: (ExprID, Expr) -> Bool
    ) -> [ExprID] {
        ast.arena.exprs.indices.compactMap { index -> ExprID? in
            let exprID = ExprID(rawValue: Int32(index))
            guard let expr = ast.arena.expr(exprID), predicate(exprID, expr) else {
                return nil
            }
            return exprID
        }
    }
}
