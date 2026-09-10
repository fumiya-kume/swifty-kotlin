#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

/// STDLIB-TEXT-TYPE-010 / KSP-486: Validates that the `kotlin.text.MatchResult`
/// public layer (value / range / groupValues / groups / componentN / next /
/// destructured) resolves to the bundled Kotlin source
/// (`__bundled_kotlin/text/MatchResult.kt`) rather than to synthetic stubs wired
/// to `kk_match_result_*` runtime entry points.
@Suite
struct MatchResultTypeTests {

    private static nonisolated(unsafe) var _sharedSema: (SemaModule, StringInterner, CompilationContext)?

    // MARK: - Shared sema fixture

    private func sharedSema() throws -> (SemaModule, StringInterner, CompilationContext) {
        if let cached = Self._sharedSema { return cached }
        var result: (SemaModule, StringInterner, CompilationContext)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try #require(ctx.sema)
            result = (sema, ctx.interner, ctx)
        }
        let triple = try #require(result)
        Self._sharedSema = triple
        return triple
    }

    private static let bundledSourcePath = "__bundled_kotlin/text/MatchResult.kt"

    private static let sharedUsageSources = [
        #"""
        package sample0

        fun probe(input: String): String? {
            val match = Regex("(a)(b)(c)(d)(e)(f)(g)(h)(i)").find(input) ?: return null
            val value = match.value
            val range = match.range
            val groupValues = match.groupValues
            val groups = match.groups
            val first = match.component1()
            val second = match.component2()
            val nextMatch = match.next()
            val destructured = match.destructured
            val (one, two, three, four, five, six, seven, eight, nine) = destructured
            val directThree = destructured.component3()
            val directFour = destructured.component4()
            val directFive = destructured.component5()
            val directSix = destructured.component6()
            val directSeven = destructured.component7()
            val directEight = destructured.component8()
            val directNine = destructured.component9()
            return value + range.first + groupValues.size + groups.size +
                first + second +
                one + two + three + four + five + six + seven + eight + nine +
                directThree + directFour + directFive + directSix + directSeven + directEight + directNine +
                destructured.component1() + destructured.match.value +
                (nextMatch?.value ?: "")
        }
        """#,
        #"""
        package sample1

        fun probe(): Int {
            val regex = Regex("(?<a>x)")
            return regex.pattern.length + regex.options.size + regex.groupNames.size
        }
        """#,
        #"""
        package sample2

        fun extractFirstNumber(input: String): String? {
            val regex = Regex("(\\d+)")
            val match = regex.find(input)
            return match?.value
        }
        """#,
        #"""
        package sample3

        fun extractGroups(input: String): String? {
            val regex = Regex("(\\w+)\\s+(\\w+)")
            val match = regex.find(input)
            val d = match?.destructured
            return d?.component1()
        }
        """#,
        #"""
        package sample4

        fun allMatches(input: String): List<String> {
            val regex = Regex("\\d+")
            var match = regex.find(input)
            val results = mutableListOf<String>()
            while (match != null) {
                results.add(match.value)
                match = match.next()
            }
            return results
        }
        """#,
    ]

    private static nonisolated(unsafe) var _sharedUsage: (CompilationContext, [String])?

    private func sharedUsage() throws -> (CompilationContext, [String]) {
        if let cached = Self._sharedUsage { return cached }
        var result: (CompilationContext, [String])?
        try withTemporaryFiles(contents: Self.sharedUsageSources) { paths in
            let ctx = makeCompilationContext(inputs: paths)
            try runSema(ctx)
            result = (ctx, paths)
        }
        let shared = try #require(result)
        Self._sharedUsage = shared
        return shared
    }

    private func diagnosticsForPath(
        _ path: String,
        in ctx: CompilationContext
    ) -> [Diagnostic] {
        guard let fileID = ctx.sourceManager.fileID(forPath: path) else { return [] }
        return ctx.diagnostics.diagnostics.filter { $0.primaryRange?.start.file == fileID }
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
            guard let range = ast.arena.exprRange(exprID),
                  ctx.sourceManager.path(of: range.start.file) == path else { continue }
            if predicate(exprID, expr) { return exprID }
        }
        return nil
    }

    private func sourcePath(
        for symbol: SymbolID,
        sema: SemaModule,
        ctx: CompilationContext
    ) -> String? {
        let fileID = sema.symbols.sourceFileID(for: symbol)
            ?? sema.symbols.symbol(symbol)?.declSite?.start.file
        guard let fileID else { return nil }
        return ctx.sourceManager.path(of: fileID)
    }

    /// Resolves the symbol a `receiver.member` read/call in `source` binds to.
    private func memberSymbol(
        _ memberName: String,
        in path: String,
        in ctx: CompilationContext
    ) throws -> SymbolID {
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let exprID = try #require(firstExprID(in: ast, path: path, ctx: ctx) { _, expr in
            guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
            return ctx.interner.resolve(callee) == memberName
        }, "Expected a `.\(memberName)` member access in the test source")
        if let callee = sema.bindings.callBinding(for: exprID)?.chosenCallee {
            return callee
        }
        return try #require(sema.bindings.identifierSymbol(for: exprID))
    }

    // MARK: - 1. MatchResult interface symbol

    @Test func testMatchResultInterfaceSymbolIsRegistered() throws {
        let (sema, interner, ctx) = try sharedSema()
        let fq = ["kotlin", "text", "MatchResult"].map { interner.intern($0) }
        let sym = try #require(
            sema.symbols.lookup(fqName: fq),
            "kotlin.text.MatchResult interface symbol must be registered by sema"
        )
        let info = try #require(sema.symbols.symbol(sym))
        #expect(info.kind == .interface,
                       "MatchResult should be registered with kind=interface")
        #expect(!info.flags.contains(.synthetic),
                "MatchResult must not depend on a synthetic nominal anchor")
        #expect(
            sourcePath(for: sym, sema: sema, ctx: ctx)?.contains(Self.bundledSourcePath) == true,
            "MatchResult must be backed by the bundled Kotlin source"
        )
    }

    // MARK: - 2. MatchResult.Destructured nested class

    @Test func testMatchResultDestructuredClassSymbolIsRegistered() throws {
        let (sema, interner, ctx) = try sharedSema()
        let fq = ["kotlin", "text", "MatchResult", "Destructured"].map { interner.intern($0) }
        let sym = try #require(
            sema.symbols.lookup(fqName: fq),
            "kotlin.text.MatchResult.Destructured nested class must be registered by sema"
        )
        let info = try #require(sema.symbols.symbol(sym))
        #expect(info.kind == .class,
                       "MatchResult.Destructured should be registered with kind=class")
        #expect(!info.flags.contains(.synthetic),
                "MatchResult.Destructured must not depend on a synthetic nominal anchor")
        #expect(
            sourcePath(for: sym, sema: sema, ctx: ctx)?.contains(Self.bundledSourcePath) == true,
            "MatchResult.Destructured must be backed by the bundled Kotlin source"
        )

        let matchResultFQName = ["kotlin", "text", "MatchResult"].map { interner.intern($0) }
        #expect(
            sema.symbols.parentSymbol(for: sym) == sema.symbols.lookup(fqName: matchResultFQName),
            "Destructured must be owned by MatchResult"
        )
        let constructorFQName = fq + [interner.intern("<init>")]
        let constructor = try #require(
            sema.symbols.lookup(fqName: constructorFQName),
            "MatchResult.Destructured must have a constructor symbol"
        )
        let constructorInfo = try #require(sema.symbols.symbol(constructor))
        #expect(constructorInfo.kind == .constructor)
        #expect(constructorInfo.visibility == .internal,
                "Destructured's opaque-handle constructor must remain internal")
        #expect(sema.symbols.parentSymbol(for: constructor) == sym,
                "Destructured constructor must be owned by Destructured")
    }

    // MARK: - 3. Public members resolve to bundled Kotlin source

    @Test func testMatchResultMembersResolveToBundledKotlinSource() throws {
        let (ctx, paths) = try sharedUsage()
        let path = paths[0]
        let errors = diagnosticsForPath(path, in: ctx).filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected MatchResult members to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )

        let sema = try #require(ctx.sema)
        let members = [
            "value", "range", "groupValues", "groups",
            "component1", "component2", "component3", "component4", "component5",
            "component6", "component7", "component8", "component9",
            "next", "destructured", "match",
        ]
        for member in members {
            let symbol = try memberSymbol(member, in: path, in: ctx)
            #expect(
                sema.symbols.externalLinkName(for: symbol) == nil,
                "MatchResult.\(member) must not be wired to a kk_* runtime entry point"
            )
            #expect(
                sourcePath(for: symbol, sema: sema, ctx: ctx)?.contains(Self.bundledSourcePath) == true,
                "MatchResult.\(member) must resolve to the bundled Kotlin source"
            )
        }
    }

    // MARK: - 4. Regex accessors resolve to bundled Kotlin source

    @Test func testRegexAccessorsResolveToBundledKotlinSource() throws {
        let (ctx, paths) = try sharedUsage()
        let path = paths[1]
        let errors = diagnosticsForPath(path, in: ctx).filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Expected Regex accessors to type-check, got: \(errors.map { "\($0.code): \($0.message)" })"
        )

        let sema = try #require(ctx.sema)
        for member in ["pattern", "options", "groupNames"] {
            let symbol = try memberSymbol(member, in: path, in: ctx)
            #expect(
                sema.symbols.externalLinkName(for: symbol) == nil,
                "Regex.\(member) must not be wired to a kk_* runtime entry point"
            )
            #expect(
                sourcePath(for: symbol, sema: sema, ctx: ctx)?.contains(Self.bundledSourcePath) == true,
                "Regex.\(member) must resolve to the bundled Kotlin source"
            )
        }
    }

    // MARK: - 5. Source-level usage: basic MatchResult access type-checks

    @Test func testBasicMatchResultAccessTypeChecks() throws {
        let (ctx, paths) = try sharedUsage()
        let errors = diagnosticsForPath(paths[2], in: ctx).filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "Basic MatchResult access should type-check without errors: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    // MARK: - 6. Source-level usage: MatchResult.destructured access type-checks

    @Test func testDestructuredPropertyAccessTypeChecks() throws {
        let (ctx, paths) = try sharedUsage()
        let errors = diagnosticsForPath(paths[3], in: ctx).filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "MatchResult.destructured access should type-check without errors: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }

    // MARK: - 7. Source-level usage: MatchResult.next() chaining type-checks

    @Test func testMatchResultNextChainingTypeChecks() throws {
        let (ctx, paths) = try sharedUsage()
        let errors = diagnosticsForPath(paths[4], in: ctx).filter { $0.severity == .error }
        #expect(
            errors.isEmpty,
            "MatchResult.next() chaining should type-check without errors: \(errors.map { "\($0.code): \($0.message)" })"
        )
    }
}
#endif
