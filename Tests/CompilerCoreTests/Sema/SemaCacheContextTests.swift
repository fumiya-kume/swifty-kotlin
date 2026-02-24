import XCTest
@testable import CompilerCore

final class SemaCacheContextTests: XCTestCase {

    // MARK: - Helpers

    /// Creates a ``CompilationContext`` from source with the `sema-cache` frontend flag enabled.
    private func makeContextFromSourceWithCache(_ source: String) throws -> CompilationContext {
        let fakePath = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString + ".kt").path
        let options = CompilerOptions(
            moduleName: "TestModule",
            inputs: [fakePath],
            outputPath: FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path,
            emit: .kirDump,
            searchPaths: [],
            target: defaultTargetTriple(),
            frontendFlags: ["sema-cache"]
        )
        let ctx = CompilationContext(
            options: options,
            sourceManager: SourceManager(),
            diagnostics: DiagnosticEngine(),
            interner: StringInterner()
        )
        _ = ctx.sourceManager.addFile(path: fakePath, contents: Data(source.utf8))
        return ctx
    }

    // MARK: - Scope Lookup Cache

    func testScopeLookupCacheReturnsSameResultAsUncached() {
        let setup = makeSemaModule()
        let interner = setup.interner
        let symbols = setup.symbols

        let fooName = interner.intern("foo")
        let sym = symbols.define(
            kind: .function, name: fooName,
            fqName: [interner.intern("test"), interner.intern("foo")],
            declSite: nil, visibility: .public, flags: []
        )

        let scope = BaseScope(parent: nil, symbols: symbols)
        scope.insert(sym)

        let cache = SemaCacheContext()
        let uncachedResult = scope.lookup(fooName)
        let cachedResult = cache.lookupInScope(fooName, scope: scope)

        XCTAssertEqual(uncachedResult, cachedResult, "Cached scope lookup must return the same result as uncached")

        // Second call should return the same result (from cache)
        let cachedResult2 = cache.lookupInScope(fooName, scope: scope)
        XCTAssertEqual(cachedResult, cachedResult2, "Repeated cached lookup must be stable")
    }

    func testScopeLookupCacheReturnsEmptyForUnknownName() {
        let setup = makeSemaModule()
        let interner = setup.interner

        let scope = BaseScope(parent: nil, symbols: setup.symbols)
        let cache = SemaCacheContext()

        let result = cache.lookupInScope(interner.intern("nonexistent"), scope: scope)
        XCTAssertTrue(result.isEmpty)
    }

    func testScopeLookupCacheInvalidation() {
        let setup = makeSemaModule()
        let interner = setup.interner
        let symbols = setup.symbols

        let name = interner.intern("bar")
        let scope = BaseScope(parent: nil, symbols: symbols)

        let cache = SemaCacheContext()
        let before = cache.lookupInScope(name, scope: scope)
        XCTAssertTrue(before.isEmpty)

        let sym = symbols.define(
            kind: .function, name: name,
            fqName: [interner.intern("test"), interner.intern("bar")],
            declSite: nil, visibility: .public, flags: []
        )
        scope.insert(sym)

        // Invalidate and re-lookup
        cache.invalidateScope(scope)
        let after = cache.lookupInScope(name, scope: scope)
        XCTAssertEqual(after, [sym])
    }

    // MARK: - Symbol Lookup Cache

    func testSymbolLookupCacheReturnsSameResultAsUncached() {
        let setup = makeSemaModule()
        let interner = setup.interner
        let symbols = setup.symbols

        let sym = symbols.define(
            kind: .function, name: interner.intern("fn"),
            fqName: [interner.intern("test"), interner.intern("fn")],
            declSite: nil, visibility: .public, flags: []
        )

        let cache = SemaCacheContext()
        let uncached = symbols.symbol(sym)
        let cached = cache.symbol(sym, in: symbols)

        XCTAssertEqual(uncached?.id, cached?.id)
        XCTAssertEqual(uncached?.kind, cached?.kind)

        // Second call
        let cached2 = cache.symbol(sym, in: symbols)
        XCTAssertEqual(cached?.id, cached2?.id)
    }

    func testSymbolLookupCacheReturnsNilForInvalidID() {
        let setup = makeSemaModule()
        let cache = SemaCacheContext()

        let invalidID = SymbolID(rawValue: 9999)
        let result = cache.symbol(invalidID, in: setup.symbols)
        XCTAssertNil(result)

        // Second call should also return nil (miss cache)
        let result2 = cache.symbol(invalidID, in: setup.symbols)
        XCTAssertNil(result2)
    }

    // MARK: - Call Resolution Cache

    func testCallResolutionCacheReturnsSameResultAsUncached() {
        let setup = makeSemaModule()
        let interner = setup.interner
        let symbols = setup.symbols
        let types = setup.types

        let intType = types.make(.primitive(.int, .nonNull))

        let fn = symbols.define(
            kind: .function, name: interner.intern("add"),
            fqName: [interner.intern("test"), interner.intern("add")],
            declSite: nil, visibility: .public, flags: []
        )
        symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [intType], returnType: intType),
            for: fn
        )

        let call = CallExpr(
            range: makeRange(start: 0, end: 10),
            calleeName: interner.intern("add"),
            args: [CallArg(type: intType)]
        )

        // Resolve without cache
        let resolverNoCache = OverloadResolver()
        let uncached = resolverNoCache.resolveCall(
            candidates: [fn], call: call, expectedType: intType, ctx: setup.ctx
        )

        // Resolve with cache
        let resolverWithCache = OverloadResolver()
        let cache = SemaCacheContext()
        resolverWithCache.cacheContext = cache
        let cached = resolverWithCache.resolveCall(
            candidates: [fn], call: call, expectedType: intType, ctx: setup.ctx
        )

        // Verify identical results
        XCTAssertEqual(uncached.chosenCallee, cached.chosenCallee)
        XCTAssertEqual(uncached.substitutedTypeArguments, cached.substitutedTypeArguments)
        XCTAssertEqual(uncached.parameterMapping, cached.parameterMapping)
        XCTAssertEqual(uncached.diagnostic, cached.diagnostic)

        // Second call should be a cache hit
        let cached2 = resolverWithCache.resolveCall(
            candidates: [fn], call: call, expectedType: intType, ctx: setup.ctx
        )
        XCTAssertEqual(cached.chosenCallee, cached2.chosenCallee)
        XCTAssertEqual(cached.parameterMapping, cached2.parameterMapping)
        XCTAssertEqual(cache.callResolutionHits, 1, "Second call should be a cache hit")
        XCTAssertEqual(cache.callResolutionMisses, 1, "First call should be a cache miss")
    }

    func testCallResolutionCacheKeyDistinguishesDifferentCandidates() {
        let setup = makeSemaModule()
        let interner = setup.interner
        let symbols = setup.symbols
        let types = setup.types

        let intType = types.make(.primitive(.int, .nonNull))
        let boolType = types.make(.primitive(.boolean, .nonNull))

        let fnA = symbols.define(
            kind: .function, name: interner.intern("f"),
            fqName: [interner.intern("test"), interner.intern("fA")],
            declSite: nil, visibility: .public, flags: []
        )
        symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [intType], returnType: intType),
            for: fnA
        )

        let fnB = symbols.define(
            kind: .function, name: interner.intern("f"),
            fqName: [interner.intern("test"), interner.intern("fB")],
            declSite: nil, visibility: .public, flags: []
        )
        symbols.setFunctionSignature(
            FunctionSignature(parameterTypes: [intType], returnType: boolType),
            for: fnB
        )

        let call = CallExpr(
            range: makeRange(start: 10, end: 20),
            calleeName: interner.intern("f"),
            args: [CallArg(type: intType)]
        )

        let resolver = OverloadResolver()
        let cache = SemaCacheContext()
        resolver.cacheContext = cache

        let resultA = resolver.resolveCall(
            candidates: [fnA], call: call, expectedType: nil, ctx: setup.ctx
        )
        let resultB = resolver.resolveCall(
            candidates: [fnB], call: call, expectedType: nil, ctx: setup.ctx
        )

        // Different candidates should produce different results
        XCTAssertEqual(resultA.chosenCallee, fnA)
        XCTAssertEqual(resultB.chosenCallee, fnB)
        XCTAssertEqual(cache.callResolutionMisses, 2, "Different candidate sets must be separate cache entries")
    }

    // MARK: - Differential Verification (cache ON vs OFF produce same diagnostics)

    func testDifferentialVerificationSimpleFunction() throws {
        let source = """
        fun add(a: Int, b: Int): Int = a + b
        fun main() {
            val result = add(1, 2)
        }
        """

        // Without cache
        let ctxNoCache = try makeContextFromSource(source)
        try runSema(ctxNoCache)
        let diagsNoCache = ctxNoCache.diagnostics.diagnostics

        // With cache
        let ctxCached = try makeContextFromSourceWithCache(source)
        try runSema(ctxCached)
        let diagsCached = ctxCached.diagnostics.diagnostics

        XCTAssertEqual(
            diagsNoCache.map(\.code).sorted(),
            diagsCached.map(\.code).sorted(),
            "Diagnostic codes must be identical with and without sema-cache"
        )
    }

    func testDifferentialVerificationUnresolvedFunction() throws {
        let source = """
        fun main() {
            val x = unknown(42)
        }
        """

        let ctxNoCache = try makeContextFromSource(source)
        try runSema(ctxNoCache)
        let diagsNoCache = ctxNoCache.diagnostics.diagnostics

        let ctxCached = try makeContextFromSourceWithCache(source)
        try runSema(ctxCached)
        let diagsCached = ctxCached.diagnostics.diagnostics

        XCTAssertEqual(
            diagsNoCache.map(\.code).sorted(),
            diagsCached.map(\.code).sorted(),
            "Diagnostics must match for unresolved function with and without cache"
        )
    }

    func testDifferentialVerificationClassAndMemberCall() throws {
        let source = """
        class Foo {
            fun bar(): Int = 42
        }
        fun main() {
            val f = Foo()
            val x = f.bar()
        }
        """

        let ctxNoCache = try makeContextFromSource(source)
        try runSema(ctxNoCache)
        let diagsNoCache = ctxNoCache.diagnostics.diagnostics

        let ctxCached = try makeContextFromSourceWithCache(source)
        try runSema(ctxCached)
        let diagsCached = ctxCached.diagnostics.diagnostics

        XCTAssertEqual(
            diagsNoCache.map(\.code).sorted(),
            diagsCached.map(\.code).sorted(),
            "Diagnostics must match for class member calls with and without cache"
        )
    }

    func testDifferentialVerificationBinaryOperator() throws {
        let source = """
        fun main() {
            val a = 1 + 2
            val b = "hello" + " world"
            val c = a > 0
        }
        """

        let ctxNoCache = try makeContextFromSource(source)
        try runSema(ctxNoCache)
        let diagsNoCache = ctxNoCache.diagnostics.diagnostics

        let ctxCached = try makeContextFromSourceWithCache(source)
        try runSema(ctxCached)
        let diagsCached = ctxCached.diagnostics.diagnostics

        XCTAssertEqual(
            diagsNoCache.map(\.code).sorted(),
            diagsCached.map(\.code).sorted(),
            "Diagnostics must match for binary operators with and without cache"
        )
    }

    func testDifferentialVerificationMultipleOverloads() throws {
        let source = """
        fun greet(name: String): String = "Hello, " + name
        fun greet(count: Int): String = "Hello #" + count.toString()
        fun main() {
            val a = greet("world")
            val b = greet(42)
        }
        """

        let ctxNoCache = try makeContextFromSource(source)
        try runSema(ctxNoCache)
        let diagsNoCache = ctxNoCache.diagnostics.diagnostics

        let ctxCached = try makeContextFromSourceWithCache(source)
        try runSema(ctxCached)
        let diagsCached = ctxCached.diagnostics.diagnostics

        XCTAssertEqual(
            diagsNoCache.map(\.code).sorted(),
            diagsCached.map(\.code).sorted(),
            "Diagnostics must match for overloaded functions with and without cache"
        )
    }

    // MARK: - Diagnostic Source-Range Correctness

    func testDiagnosticSourceRangesCorrectWithCache() throws {
        // Two identical failing calls at different lines must produce diagnostics
        // that point to their respective (different) source locations.
        let source = """
        fun main() {
            val x = unknownFn(1)
            val y = unknownFn(1)
        }
        """

        let ctxCached = try makeContextFromSourceWithCache(source)
        try runSema(ctxCached)
        let diags = ctxCached.diagnostics.diagnostics

        // There should be at least two diagnostics for the two unresolved calls
        let unresolvedDiags = diags.filter { $0.code == "KSWIFTK-SEMA-0023" }
        XCTAssertGreaterThanOrEqual(
            unresolvedDiags.count, 2,
            "Should have at least 2 unresolved function diagnostics"
        )
        if unresolvedDiags.count >= 2 {
            // The two diagnostics must have different source ranges (different lines)
            let ranges = unresolvedDiags.compactMap(\.primaryRange)
            XCTAssertEqual(ranges.count, unresolvedDiags.count, "All diagnostics should have a primaryRange")
            if ranges.count >= 2 {
                XCTAssertNotEqual(
                    ranges[0], ranges[1],
                    "Two identical failing calls at different locations must produce diagnostics with different source ranges"
                )
            }
        }
    }

    // MARK: - Inheritance / Super Call with Cache

    func testDifferentialVerificationInheritance() throws {
        let source = """
        open class Animal {
            open fun speak(): String = "..."
        }
        class Dog : Animal() {
            override fun speak(): String = "Woof"
        }
        fun main() {
            val d: Animal = Dog()
            val s = d.speak()
        }
        """

        let ctxNoCache = try makeContextFromSource(source)
        try runSema(ctxNoCache)
        let diagsNoCache = ctxNoCache.diagnostics.diagnostics

        let ctxCached = try makeContextFromSourceWithCache(source)
        try runSema(ctxCached)
        let diagsCached = ctxCached.diagnostics.diagnostics

        XCTAssertEqual(
            diagsNoCache.map(\.code).sorted(),
            diagsCached.map(\.code).sorted(),
            "Diagnostics must match for inheritance with and without cache"
        )
    }

    // MARK: - Callable Reference with Cache

    func testDifferentialVerificationCallableReference() throws {
        let source = """
        fun double(x: Int): Int = x * 2
        fun main() {
            val fn = ::double
        }
        """

        let ctxNoCache = try makeContextFromSource(source)
        try runSema(ctxNoCache)
        let diagsNoCache = ctxNoCache.diagnostics.diagnostics

        let ctxCached = try makeContextFromSourceWithCache(source)
        try runSema(ctxCached)
        let diagsCached = ctxCached.diagnostics.diagnostics

        XCTAssertEqual(
            diagsNoCache.map(\.code).sorted(),
            diagsCached.map(\.code).sorted(),
            "Diagnostics must match for callable references with and without cache"
        )
    }

    // MARK: - Scope Cache Statistics

    func testScopeCacheStatisticsAreTracked() {
        let setup = makeSemaModule()
        let interner = setup.interner
        let symbols = setup.symbols

        let fooName = interner.intern("foo")
        let sym = symbols.define(
            kind: .function, name: fooName,
            fqName: [interner.intern("test"), interner.intern("foo")],
            declSite: nil, visibility: .public, flags: []
        )

        let scope = BaseScope(parent: nil, symbols: symbols)
        scope.insert(sym)

        let cache = SemaCacheContext()

        XCTAssertEqual(cache.scopeHits, 0)
        XCTAssertEqual(cache.scopeMisses, 0)

        // First lookup: cache miss
        _ = cache.lookupInScope(fooName, scope: scope)
        XCTAssertEqual(cache.scopeHits, 0, "First lookup should be a miss")
        XCTAssertEqual(cache.scopeMisses, 1, "First lookup should be a miss")

        // Second lookup: cache hit
        _ = cache.lookupInScope(fooName, scope: scope)
        XCTAssertEqual(cache.scopeHits, 1, "Second lookup should be a hit")
        XCTAssertEqual(cache.scopeMisses, 1, "Miss count should not change")

        // Third lookup (different name): cache miss
        let barName = interner.intern("bar")
        _ = cache.lookupInScope(barName, scope: scope)
        XCTAssertEqual(cache.scopeHits, 1, "Unknown name should be a miss")
        XCTAssertEqual(cache.scopeMisses, 2, "Miss count should increment")
    }

    // MARK: - Lambda with Cache

    func testDifferentialVerificationLambda() throws {
        let source = """
        fun apply(f: (Int) -> Int, x: Int): Int = f(x)
        fun main() {
            val result = apply({ it * 2 }, 5)
        }
        """

        let ctxNoCache = try makeContextFromSource(source)
        try runSema(ctxNoCache)
        let diagsNoCache = ctxNoCache.diagnostics.diagnostics

        let ctxCached = try makeContextFromSourceWithCache(source)
        try runSema(ctxCached)
        let diagsCached = ctxCached.diagnostics.diagnostics

        XCTAssertEqual(
            diagsNoCache.map(\.code).sorted(),
            diagsCached.map(\.code).sorted(),
            "Diagnostics must match for lambda expressions with and without cache"
        )
    }
}
