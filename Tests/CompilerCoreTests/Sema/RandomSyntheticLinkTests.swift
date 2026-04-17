@testable import CompilerCore
import Foundation
import XCTest

final class RandomSyntheticLinkTests: XCTestCase {
    func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let sema = try XCTUnwrap(ctx.sema)
            result = (sema, ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    private func externalLinks(
        for member: String,
        sema: SemaModule,
        interner: StringInterner
    ) -> [String] {
        let fq = ["kotlin", "random", "Random", member].map { interner.intern($0) }
        let symbols = sema.symbols.lookupAll(fqName: fq)
        return symbols.compactMap { sema.symbols.externalLinkName(for: $0) }
    }

    func testNextLongStubsHaveCorrectExternalLinks() throws {
        let (sema, interner) = try makeSema()

        let links = externalLinks(for: "nextLong", sema: sema, interner: interner)
        XCTAssertTrue(links.contains("kk_random_nextLong"), "nextLong() stub missing")
        XCTAssertTrue(links.contains("kk_random_nextLong_until"), "nextLong(until) stub missing")
        XCTAssertTrue(links.contains("kk_random_nextLong_range"), "nextLong(from, until) stub missing")
    }

    func testNextFloatStubHasCorrectExternalLink() throws {
        let (sema, interner) = try makeSema()

        let links = externalLinks(for: "nextFloat", sema: sema, interner: interner)
        XCTAssertTrue(links.contains("kk_random_nextFloat"), "nextFloat() stub missing")
        XCTAssertTrue(links.contains("kk_random_nextFloat_until"), "nextFloat(until) stub missing")
    }

    func testNextDoubleStubsHaveCorrectExternalLinks() throws {
        let (sema, interner) = try makeSema()

        let links = externalLinks(for: "nextDouble", sema: sema, interner: interner)
        XCTAssertTrue(links.contains("kk_random_nextDouble"), "nextDouble() stub missing")
        XCTAssertTrue(links.contains("kk_random_nextDouble_until"), "nextDouble(until) stub missing")
        XCTAssertTrue(links.contains("kk_random_nextDouble_range"), "nextDouble(from, until) stub missing")
    }

    func testExistingRandomStubsStillPresent() throws {
        let (sema, interner) = try makeSema()

        let intLinks = externalLinks(for: "nextInt", sema: sema, interner: interner)
        XCTAssertTrue(intLinks.contains("kk_random_nextInt"), "nextInt() stub missing")
        XCTAssertTrue(intLinks.contains("kk_random_nextInt_until"), "nextInt(until) stub missing")
        XCTAssertTrue(intLinks.contains("kk_random_nextInt_range"), "nextInt(from, until) stub missing")

        let doubleLinks = externalLinks(for: "nextDouble", sema: sema, interner: interner)
        XCTAssertTrue(doubleLinks.contains("kk_random_nextDouble"), "nextDouble() stub missing")
        XCTAssertTrue(doubleLinks.contains("kk_random_nextDouble_until"), "nextDouble(until) stub missing")
        XCTAssertTrue(doubleLinks.contains("kk_random_nextDouble_range"), "nextDouble(from, until) stub missing")

        let boolLinks = externalLinks(for: "nextBoolean", sema: sema, interner: interner)
        XCTAssertTrue(boolLinks.contains("kk_random_nextBoolean"), "nextBoolean() stub missing")
    }
}
