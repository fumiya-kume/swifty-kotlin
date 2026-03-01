import XCTest
@testable import CompilerCore


extension SemaCacheContextTests {
    func testDifferentialVerificationUnresolvedFunction() throws {
        let source = """
        fun main() {
            val x = unknown(42)
        }
        """

        let ctxNoCache = makeContextFromSource(source)
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

        let ctxNoCache = makeContextFromSource(source)
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

        let ctxNoCache = makeContextFromSource(source)
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

        let ctxNoCache = makeContextFromSource(source)
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

        let ctxNoCache = makeContextFromSource(source)
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

        let ctxNoCache = makeContextFromSource(source)
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

        let ctxNoCache = makeContextFromSource(source)
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
