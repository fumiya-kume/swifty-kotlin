/// Sema coverage for STDLIB-RANDOM-FN-002:
/// `fun java.util.Random.asKotlinRandom(): Random` extension function.
///
/// The function is a top-level extension in the `kotlin.random` package with
/// `java.util.Random` as its receiver and `kotlin.random.Random` as its return
/// type (Sources/CompilerCore/Stdlib/kotlin/random/PlatformRandom.kt). KSP-466:
/// real Kotlin source (`this.delegate`), not a native bridge.

#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct RandomAsKotlinRandomFunctionTests {
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

    /// `asKotlinRandom` lives at `kotlin.random.asKotlinRandom` (top-level
    /// extension), not as a member of `java.util.Random`.
    @Test func testAsKotlinRandomIsRegisteredAsTopLevelExtension() throws {
        let (sema, interner) = try sharedSema()

        let fq = ["kotlin", "random", "asKotlinRandom"].map { interner.intern($0) }
        let candidates = sema.symbols.lookupAll(fqName: fq)
        #expect(!candidates.isEmpty,
                "asKotlinRandom must be registered as a top-level extension in kotlin.random")
    }

    /// The registered overload accepts no value parameters. KSP-466: asKotlinRandom
    /// is real Kotlin source now (PlatformRandom.kt: `this.delegate`), not a
    /// native bridge — a raw pointer passthrough stopped being safe once
    /// kotlin.random.Random became a genuine compiled object.
    @Test func testAsKotlinRandomLinksToRuntimeStub() throws {
        let (sema, interner) = try sharedSema()

        let fq = ["kotlin", "random", "asKotlinRandom"].map { interner.intern($0) }
        let candidates = sema.symbols.lookupAll(fqName: fq)

        let arity0 = candidates.first { id in
            sema.symbols.functionSignature(for: id)?.parameterTypes.isEmpty == true
        }
        let candidateSym = try #require(arity0,
                                        "asKotlinRandom must expose an arity-0 (value parameters) overload")
        #expect(sema.symbols.externalLinkName(for: candidateSym) == nil,
                "asKotlinRandom is real Kotlin, not a native bridge")
    }

    /// The receiver type must be `java.util.Random` so that
    /// `JavaRandom(42).asKotlinRandom()` resolves through the extension.
    @Test func testAsKotlinRandomReceiverIsJavaUtilRandom() throws {
        let (sema, interner) = try sharedSema()

        let javaRandomFQ = ["java", "util", "Random"].map { interner.intern($0) }
        let javaRandomSymbol = try #require(sema.symbols.lookup(fqName: javaRandomFQ),
                                            "java.util.Random shim must be registered")
        let expectedReceiver = sema.types.make(.classType(ClassType(
            classSymbol: javaRandomSymbol,
            args: [],
            nullability: .nonNull
        )))

        let fq = ["kotlin", "random", "asKotlinRandom"].map { interner.intern($0) }
        let candidates = sema.symbols.lookupAll(fqName: fq)
        let asKotlinRandom = candidates.first { id in
            sema.symbols.functionSignature(for: id)?.receiverType == expectedReceiver
        }
        #expect(asKotlinRandom != nil,
                "asKotlinRandom must have java.util.Random as its receiver type")
    }

    /// The return type must be `kotlin.random.Random` (the standard library
    /// Random type, not the synthetic `java.util.Random` shim).
    @Test func testAsKotlinRandomReturnsKotlinRandom() throws {
        let (sema, interner) = try sharedSema()

        let randomFQ = ["kotlin", "random", "Random"].map { interner.intern($0) }
        let randomSymbol = try #require(sema.symbols.lookup(fqName: randomFQ),
                                        "kotlin.random.Random must be registered")
        let expectedReturn = sema.types.make(.classType(ClassType(
            classSymbol: randomSymbol,
            args: [],
            nullability: .nonNull
        )))

        let fq = ["kotlin", "random", "asKotlinRandom"].map { interner.intern($0) }
        let candidates = sema.symbols.lookupAll(fqName: fq)
        let asKotlinRandom = candidates.first { id in
            sema.symbols.functionSignature(for: id)?.returnType == expectedReturn
        }
        #expect(asKotlinRandom != nil,
                "asKotlinRandom must return kotlin.random.Random")
    }

    /// The synthetic `java.util.Random` shim must expose a seeded constructor that
    /// allows user code such as `JavaRandom(42).asKotlinRandom()` to resolve.
    @Test func testJavaUtilRandomShimHasConstructorsForAsKotlinRandomCallSites() throws {
        let (sema, interner) = try sharedSema()

        let initFQ = ["java", "util", "Random", "<init>"].map { interner.intern($0) }
        let ctors = sema.symbols.lookupAll(fqName: initFQ)
        #expect(!ctors.isEmpty, "java.util.Random must expose synthetic constructors")

        let arities = ctors.compactMap { id -> Int? in
            sema.symbols.functionSignature(for: id).map { $0.parameterTypes.count }
        }
        #expect(arities.contains(1),
                "java.util.Random must expose a seeded constructor")
    }
}
#endif
