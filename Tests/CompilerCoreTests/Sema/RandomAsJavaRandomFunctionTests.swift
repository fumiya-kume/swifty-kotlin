/// Sema coverage for STDLIB-RANDOM-FN-001:
/// `fun Random.asJavaRandom(): java.util.Random` extension function.
///
/// The function is registered as a synthetic top-level extension in the
/// `kotlin.random` package with `kotlin.random.Random` as its receiver and
/// `java.util.Random` as its return type. It is linked to the runtime entry
/// `kk_random_asJavaRandom`.

@testable import CompilerCore
import Foundation
import XCTest

final class RandomAsJavaRandomFunctionTests: XCTestCase {
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

    /// `asJavaRandom` lives at `kotlin.random.asJavaRandom` (top-level extension),
    /// not as a member of `Random`.
    func testAsJavaRandomIsRegisteredAsTopLevelExtension() throws {
        let (sema, interner) = try makeSema()

        let fq = ["kotlin", "random", "asJavaRandom"].map { interner.intern($0) }
        let candidates = sema.symbols.lookupAll(fqName: fq)
        XCTAssertFalse(candidates.isEmpty,
                       "asJavaRandom must be registered as a top-level extension in kotlin.random")
    }

    /// The registered overload accepts no value parameters and links to
    /// `kk_random_asJavaRandom`.
    func testAsJavaRandomLinksToRuntimeStub() throws {
        let (sema, interner) = try makeSema()

        let fq = ["kotlin", "random", "asJavaRandom"].map { interner.intern($0) }
        let candidates = sema.symbols.lookupAll(fqName: fq)

        let arity0 = candidates.first { id in
            sema.symbols.functionSignature(for: id)?.parameterTypes.isEmpty == true
        }
        let candidateSym = try XCTUnwrap(arity0,
                                         "asJavaRandom must expose an arity-0 (value parameters) overload")
        XCTAssertEqual(sema.symbols.externalLinkName(for: candidateSym),
                       "kk_random_asJavaRandom",
                       "asJavaRandom must link to kk_random_asJavaRandom")
    }

    /// The receiver type must be `kotlin.random.Random` so that
    /// `Random(42).asJavaRandom()` resolves through the extension.
    func testAsJavaRandomReceiverIsKotlinRandom() throws {
        let (sema, interner) = try makeSema()

        let randomFQ = ["kotlin", "random", "Random"].map { interner.intern($0) }
        let randomSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: randomFQ),
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
        XCTAssertNotNil(asJavaRandom,
                        "asJavaRandom must have kotlin.random.Random as its receiver type")
    }

    /// The return type must be `java.util.Random` (the synthetic shim class
    /// registered alongside the function).
    func testAsJavaRandomReturnsJavaUtilRandom() throws {
        let (sema, interner) = try makeSema()

        let javaRandomFQ = ["java", "util", "Random"].map { interner.intern($0) }
        let javaRandomSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: javaRandomFQ),
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
        XCTAssertNotNil(asJavaRandom,
                        "asJavaRandom must return java.util.Random")
    }

    /// The synthetic `java.util.Random` shim must expose at least a no-arg and
    /// seeded constructor so user code such as
    /// `import java.util.Random as JavaRandom; JavaRandom(42).asKotlinRandom()`
    /// can resolve.
    func testJavaUtilRandomShimHasConstructors() throws {
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
