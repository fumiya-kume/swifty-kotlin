@testable import CompilerCore
import Foundation
import Testing

/// Sema-level coverage for the kotlin.system namespace (STDLIB-SYSTEM-001/002).
///
/// The suite runs a small number of consolidated Sema pipelines and verifies
/// symbol registration and call resolution in tabular form. This reduces the
/// per-API pipeline initializations that used to happen for every individual test.
@Suite
struct SystemNamespaceSemaOverloadTests {

    // MARK: - Helpers

    private static nonisolated(unsafe) var _sharedSema: (SemaModule, StringInterner)?

    private func sharedSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = try (#require(ctx.sema), ctx.interner)
        }
        let semaResult = try #require(result)
        Self._sharedSema = semaResult
        return semaResult
    }

    private func systemPkgExternalLink(
        for name: String,
        sema: SemaModule,
        interner: StringInterner
    ) -> String? {
        let fq = ["kotlin", "system", name].map { interner.intern($0) }
        guard let sym = sema.symbols.lookup(fqName: fq) else { return nil }
        return sema.symbols.externalLinkName(for: sym)
    }

    private func systemPkgIsDeclared(
        _ name: String,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let fq = ["kotlin", "system", name].map { interner.intern($0) }
        return !sema.symbols.lookupAll(fqName: fq).isEmpty
    }

    /// All runtime link names registered anywhere in the module, used to assert
    /// that the bundled __kk_system_* bridges exist (KSP-617).
    private func allExternalLinks(sema: SemaModule) -> Set<String> {
        Set(sema.symbols.allSymbols().compactMap { sema.symbols.externalLinkName(for: $0.id) })
    }

    // MARK: - STDLIB-SYSTEM-001: API list / symbol registration

    @Test
    func testKotlinSystemSymbolsAreRegistered() throws {
        let (sema, interner) = try sharedSema()

        // KSP-617: the public surface lives in bundled Kotlin source; the OS
        // entry points are private __kk_system_* bridges.
        let publicTopLevelFunctions = [
            "exitProcess",
            "getTimeMicros",
            "getTimeMillis",
            "getTimeNanos",
            "measureTimeMicros",
            "measureTimeMillis",
            "measureNanoTime",
        ]
        for name in publicTopLevelFunctions {
            #expect(
                systemPkgIsDeclared(name, sema: sema, interner: interner),
                "kotlin.system.\(name) should be declared in bundled Kotlin source"
            )
            #expect(
                systemPkgExternalLink(for: name, sema: sema, interner: interner) == nil,
                "kotlin.system.\(name) must not be an external runtime declaration"
            )
            let fq = ["kotlin", "system", name].map { interner.intern($0) }
            let symbol = try #require(sema.symbols.lookup(fqName: fq))
            #expect(
                sema.symbols.isSourceBackedSymbol(symbol),
                "kotlin.system.\(name) should resolve to bundled Kotlin source"
            )
        }

        let links = allExternalLinks(sema: sema)
        for bridge in [
            "__kk_system_exitProcess",
            "__kk_system_getTimeMicros",
            "__kk_system_getTimeMillis",
            "__kk_system_getTimeNanos",
        ] {
            #expect(links.contains(bridge), "\(bridge) bridge must be declared")
        }

        let systemFQ = ["kotlin", "system", "System"].map { interner.intern($0) }
        let systemSymbol = try #require(
            sema.symbols.lookup(fqName: systemFQ),
            "kotlin.system.System object must be registered"
        )
        let systemName = try #require(sema.symbols.symbol(systemSymbol)?.fqName)
        let expectedSystemMembers = [
            "currentTimeMillis",
            "nanoTime",
            "processStartNanos",
        ]
        for member in expectedSystemMembers {
            let memberFQ = systemName + [interner.intern(member)]
            let memberSymbol = try #require(
                sema.symbols.lookupAll(fqName: memberFQ).first,
                "kotlin.system.System.\(member) should be declared"
            )
            #expect(
                sema.symbols.isSourceBackedSymbol(memberSymbol),
                "kotlin.system.System.\(member) should resolve to bundled Kotlin source"
            )
            #expect(
                sema.symbols.externalLinkName(for: memberSymbol) == nil,
                "kotlin.system.System.\(member) must not expose a runtime link"
            )
        }

        for bridge in [
            "__kk_system_currentTimeMillis",
            "__kk_system_nanoTime",
            "__kk_system_process_start_nanos",
        ] {
            #expect(links.contains(bridge), "\(bridge) bridge must be declared")
        }
    }

    // MARK: - STDLIB-SYSTEM-002: Sema overload resolution

    /// Verifies that calls to kotlin.system top-level functions and System
    /// object members resolve through ordinary source-backed declarations.
    @Test
    func testKotlinSystemCallExpressionsResolve() throws {
        let source = """
        import kotlin.system.*

        fun measureMillisSample(): Long = measureTimeMillis { }
        fun measureMicrosSample(): Long = measureTimeMicros { }
        fun measureNanosSample(): Long = measureNanoTime { }
        fun getMillisSample(): Long = getTimeMillis()
        fun getMicrosSample(): Long = getTimeMicros()
        fun getNanosSample(): Long = getTimeNanos()
        fun exitProcessSample() { exitProcess(0) }
        fun currentTimeMillisSample(): Long = System.currentTimeMillis()
        fun nanoTimeSample(): Long = System.nanoTime()
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        let diagnosticSummary = ctx.diagnostics.diagnostics
            .map { "\($0.code): \($0.message)" }
            .joined(separator: " | ")
        #expect(
            !ctx.diagnostics.hasError,
            "Expected kotlin.system call expressions to resolve cleanly, got: \(diagnosticSummary)"
        )

        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        let interner = ctx.interner

        // Table of ordinary source-backed top-level calls: (name, return type).
        let topLevelCalls: [(String, TypeID)] = [
            ("measureTimeMillis", sema.types.longType),
            ("measureTimeMicros", sema.types.longType),
            ("measureNanoTime", sema.types.longType),
            ("getTimeMillis", sema.types.longType),
            ("getTimeMicros", sema.types.longType),
            ("getTimeNanos", sema.types.longType),
            ("exitProcess", sema.types.nothingType),
        ]

        for (name, expectedReturnType) in topLevelCalls {
            let callExpr = try #require(
                firstExprID(in: ast) { _, expr in
                    guard case let .call(calleeExpr, _, _, _) = expr,
                          case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                    else {
                        return false
                    }
                    return interner.resolve(calleeName) == name
                },
                "Expected call to \(name)"
            )

            #expect(
                sema.bindings.exprTypes[callExpr] == expectedReturnType,
                "\(name) must return \(expectedReturnType)"
            )

            #expect(
                sema.bindings.stdlibSpecialCallKind(for: callExpr) == nil,
                "\(name) must not use a stdlib special-call path"
            )

            let chosenCallee = try #require(
                sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                "Expected a chosen callee for \(name)"
            )
            let fqName = try #require(sema.symbols.symbol(chosenCallee)?.fqName)
                .map { interner.resolve($0) }
            #expect(fqName == ["kotlin", "system", name], "Unexpected callee: \(fqName)")
            #expect(
                sema.symbols.isSourceBackedSymbol(chosenCallee),
                "\(name) must resolve to bundled Kotlin source"
            )
            #expect(
                sema.symbols.externalLinkName(for: chosenCallee) == nil,
                "\(name) must not expose a runtime link"
            )
        }

        // Table of System object member calls: (name, expectedReturnType)
        let systemMemberCalls: [(String, TypeID)] = [
            ("currentTimeMillis", sema.types.longType),
            ("nanoTime", sema.types.longType),
        ]

        for (name, expectedReturnType) in systemMemberCalls {
            let memberCallExpr = try #require(
                firstExprID(in: ast) { _, expr in
                    guard case let .memberCall(_, callee, _, _, _) = expr else { return false }
                    return interner.resolve(callee) == name
                },
                "Expected member call to System.\(name)"
            )

            #expect(
                sema.bindings.exprTypes[memberCallExpr] == expectedReturnType,
                "System.\(name) must return \(expectedReturnType)"
            )
        }
    }

    /// exitProcess must reject a call without an Int argument (wrong arity).
    @Test
    func testExitProcessWithWrongArityProducesDiagnostic() throws {
        let source = """
        import kotlin.system.exitProcess

        fun sample() {
            exitProcess()
        }
        """

        let ctx = makeContextFromSource(source)
        try runSema(ctx)

        #expect(
            ctx.diagnostics.hasError,
            "exitProcess() without arguments must produce a sema error"
        )
    }
}
