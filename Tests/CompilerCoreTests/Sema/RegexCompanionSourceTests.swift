#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct RegexCompanionSourceTests {
    private static nonisolated(unsafe) var _sharedSema: (SemaModule, StringInterner)?

    private func sharedSema() throws -> (SemaModule, StringInterner) {
        if let cached = Self._sharedSema { return cached }
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = (try #require(ctx.sema), ctx.interner)
        }
        let semaResult = try #require(result)
        Self._sharedSema = semaResult
        return semaResult
    }

    @Test
    func testCompanionFunctionsAreSourceBacked() throws {
        let (sema, interner) = try sharedSema()
        let regexSymbol = try #require(sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("text"),
            interner.intern("Regex"),
        ]))
        let companionSymbol = try #require(sema.symbols.companionObjectSymbol(for: regexSymbol))
        let companionType = sema.types.make(.classType(ClassType(
            classSymbol: companionSymbol,
            args: [],
            nullability: .nonNull
        )))

        for name in ["escape", "escapeReplacement"] {
            let symbol = try #require(
                sema.symbols.lookupAll(fqName: [
                    interner.intern("kotlin"),
                    interner.intern("text"),
                    interner.intern(name),
                ]).first { candidate in
                    guard let signature = sema.symbols.functionSignature(for: candidate) else {
                        return false
                    }
                    return signature.receiverType == companionType
                        && signature.parameterTypes == [sema.types.stringType]
                        && signature.returnType == sema.types.stringType
                },
                "Regex.Companion.\(name) should be a source-backed extension"
            )
            #expect(sema.symbols.isSourceBackedSymbol(symbol))
            #expect(sema.symbols.symbol(symbol)?.declSite != nil)
            #expect(sema.symbols.externalLinkName(for: symbol) == nil)
        }
    }

    @Test
    func testCompanionCallsResolveWithoutRegexRuntimeBridge() throws {
        let source = #"""
        fun main() {
            println(Regex.escape("a.b"))
            println(Regex.escapeReplacement("a\$b\\c"))
        }
        """#

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path], emit: .kirDump)
            try runToLowering(ctx)
            #expect(!ctx.diagnostics.hasError, "Regex.Companion calls should type-check: \(ctx.diagnostics.diagnostics)")

            let module = try #require(ctx.kir)
            let body = try findKIRFunctionBody(named: "main", in: module, interner: ctx.interner)
            let callees = extractCallees(from: body, interner: ctx.interner)
            #expect(callees.contains("escape"), "Expected source-backed escape call, got: \(callees)")
            #expect(callees.contains("escapeReplacement"), "Expected source-backed escapeReplacement call, got: \(callees)")
            #expect(!callees.contains(where: { $0.contains("regex_escape") }))
            #expect(!callees.contains(where: { $0.contains("regex_escapeReplacement") }))
        }
    }
}
#endif
