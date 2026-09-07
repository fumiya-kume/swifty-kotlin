/// Sema coverage for STDLIB-RANDOM-FN-001:
/// `fun Random.asJavaRandom(): java.util.Random` extension function.
///
/// The function is a top-level extension in the `kotlin.random` package with
/// `kotlin.random.Random` as its receiver and `java.util.Random` as its return
/// type (Sources/CompilerCore/Stdlib/kotlin/random/PlatformRandom.kt). KSP-466:
/// real Kotlin source (`java.util.Random(this)`), not a native bridge.

#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing

@Suite
struct RandomAsJavaRandomFunctionTests {
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

    /// `asJavaRandom` lives at `kotlin.random.asJavaRandom` (top-level extension),
    /// not as a member of `Random`.
    @Test func testAsJavaRandomIsRegisteredAsTopLevelExtension() throws {
        let (sema, interner) = try sharedSema()

        let fq = ["kotlin", "random", "asJavaRandom"].map { interner.intern($0) }
        let candidates = sema.symbols.lookupAll(fqName: fq)
        #expect(!candidates.isEmpty,
                "asJavaRandom must be registered as a top-level extension in kotlin.random")
    }

    /// The registered overload accepts no value parameters. KSP-466: asJavaRandom
    /// is real Kotlin source now (PlatformRandom.kt: `java.util.Random(this)`),
    /// not a native bridge.
    @Test func testAsJavaRandomLinksToRuntimeStub() throws {
        let (sema, interner) = try sharedSema()

        let fq = ["kotlin", "random", "asJavaRandom"].map { interner.intern($0) }
        let candidates = sema.symbols.lookupAll(fqName: fq)

        let arity0 = candidates.first { id in
            sema.symbols.functionSignature(for: id)?.parameterTypes.isEmpty == true
        }
        let candidateSym = try #require(arity0,
                                        "asJavaRandom must expose an arity-0 (value parameters) overload")
        #expect(sema.symbols.externalLinkName(for: candidateSym) == nil,
                "asJavaRandom is real Kotlin, not a native bridge")
    }

    /// The receiver type must be `kotlin.random.Random` so that
    /// `Random(42).asJavaRandom()` resolves through the extension.
    @Test func testAsJavaRandomReceiverIsKotlinRandom() throws {
        let (sema, interner) = try sharedSema()

        let randomFQ = ["kotlin", "random", "Random"].map { interner.intern($0) }
        let randomSymbol = try #require(sema.symbols.lookup(fqName: randomFQ),
                                        "kotlin.random.Random must be registered")
        let expectedReceiver = sema.types.make(.classType(ClassType(
            classSymbol: randomSymbol,
            args: [],
            nullability: .nonNull
        )))

        let fq = ["kotlin", "random", "asJavaRandom"].map { interner.intern($0) }
        let candidates = sema.symbols.lookupAll(fqName: fq)
        let asJavaRandom = candidates.first { id in
            sema.symbols.functionSignature(for: id)?.receiverType == expectedReceiver
        }
        #expect(asJavaRandom != nil,
                "asJavaRandom must have kotlin.random.Random as its receiver type")
    }

    /// The return type must be `java.util.Random` (the synthetic shim class
    /// registered alongside the function).
    @Test func testAsJavaRandomReturnsJavaUtilRandom() throws {
        let (sema, interner) = try sharedSema()

        let javaRandomFQ = ["java", "util", "Random"].map { interner.intern($0) }
        let javaRandomSymbol = try #require(sema.symbols.lookup(fqName: javaRandomFQ),
                                            "java.util.Random shim must be registered")
        let expectedReturn = sema.types.make(.classType(ClassType(
            classSymbol: javaRandomSymbol,
            args: [],
            nullability: .nonNull
        )))

        let fq = ["kotlin", "random", "asJavaRandom"].map { interner.intern($0) }
        let candidates = sema.symbols.lookupAll(fqName: fq)
        let asJavaRandom = candidates.first { id in
            sema.symbols.functionSignature(for: id)?.returnType == expectedReturn
        }
        #expect(asJavaRandom != nil,
                "asJavaRandom must return java.util.Random")
    }

    /// The synthetic `java.util.Random` shim must expose a seeded constructor so
    /// user code such as `import java.util.Random as JavaRandom; JavaRandom(42).asKotlinRandom()`
    /// can resolve.
    @Test func testJavaUtilRandomShimHasConstructors() throws {
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
