/// Sema coverage for STDLIB-RANDOM-FN-002:
/// `fun java.util.Random.asKotlinRandom(): Random` extension function.
///
/// The function is registered as a synthetic top-level extension in the
/// `kotlin.random` package with `java.util.Random` as its receiver and
/// `kotlin.random.Random` as its return type. It is linked to the runtime
/// entry `kk_random_asKotlinRandom`.

@testable import CompilerCore
import Foundation
import XCTest

final class RandomAsKotlinRandomFunctionTests: XCTestCase {
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

    /// `asKotlinRandom` lives at `kotlin.random.asKotlinRandom` (top-level
    /// extension), not as a member of `java.util.Random`.
    func testAsKotlinRandomIsRegisteredAsTopLevelExtension() throws {
        let (sema, interner) = try makeSema()

        let fq = ["kotlin", "random", "asKotlinRandom"].map { interner.intern($0) }
        let candidates = sema.symbols.lookupAll(fqName: fq)
        XCTAssertFalse(candidates.isEmpty,
                       "asKotlinRandom must be registered as a top-level extension in kotlin.random")
    }

    /// The registered overload accepts no value parameters and links to
    /// `kk_random_asKotlinRandom`.
    func testAsKotlinRandomLinksToRuntimeStub() throws {
        let (sema, interner) = try makeSema()

        let fq = ["kotlin", "random", "asKotlinRandom"].map { interner.intern($0) }
        let candidates = sema.symbols.lookupAll(fqName: fq)

        let arity0 = candidates.first { id in
            sema.symbols.functionSignature(for: id)?.parameterTypes.isEmpty == true
        }
        let candidateSym = try XCTUnwrap(arity0,
                                         "asKotlinRandom must expose an arity-0 (value parameters) overload")
        XCTAssertEqual(sema.symbols.externalLinkName(for: candidateSym),
                       "kk_random_asKotlinRandom",
                       "asKotlinRandom must link to kk_random_asKotlinRandom")
    }

    /// The receiver type must be `java.util.Random` so that
    /// `JavaRandom(42).asKotlinRandom()` resolves through the extension.
    func testAsKotlinRandomReceiverIsJavaUtilRandom() throws {
        let (sema, interner) = try makeSema()

        let javaRandomFQ = ["java", "util", "Random"].map { interner.intern($0) }
        let javaRandomSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: javaRandomFQ),
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
        XCTAssertNotNil(asKotlinRandom,
                        "asKotlinRandom must have java.util.Random as its receiver type")
    }

    /// The return type must be `kotlin.random.Random` (the standard library
    /// Random type, not the synthetic `java.util.Random` shim).
    func testAsKotlinRandomReturnsKotlinRandom() throws {
        let (sema, interner) = try makeSema()

        let randomFQ = ["kotlin", "random", "Random"].map { interner.intern($0) }
        let randomSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: randomFQ),
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
        XCTAssertNotNil(asKotlinRandom,
                        "asKotlinRandom must return kotlin.random.Random")
    }

    /// The synthetic `java.util.Random` shim must expose constructors that
    /// allow user code such as `JavaRandom().asKotlinRandom()` or
    /// `JavaRandom(42).asKotlinRandom()` to resolve.
    func testJavaUtilRandomShimHasConstructorsForAsKotlinRandomCallSites() throws {
        let (sema, interner) = try makeSema()

        let initFQ = ["java", "util", "Random", "<init>"].map { interner.intern($0) }
        let ctors = sema.symbols.lookupAll(fqName: initFQ)
        XCTAssertFalse(ctors.isEmpty, "java.util.Random must expose synthetic constructors")

        let arities = ctors.compactMap { id -> Int? in
            sema.symbols.functionSignature(for: id).map { $0.parameterTypes.count }
        }
        XCTAssertTrue(arities.contains(0),
                      "java.util.Random must expose a no-arg constructor")
        XCTAssertTrue(arities.contains(1),
                      "java.util.Random must expose a seeded constructor")
    }
}
