@testable import CompilerCore
import XCTest

final class LockSyntheticMemberLinkTests: XCTestCase {
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

    private func externalLinks(
        for member: String,
        sema: SemaModule,
        interner: StringInterner
    ) -> [String] {
        let fq = ["kotlin", "concurrent", "Lock", member].map { interner.intern($0) }
        return sema.symbols.lookupAll(fqName: fq).compactMap { sema.symbols.externalLinkName(for: $0) }
    }

    func testLockWithLockMemberHasCorrectExternalLink() throws {
        let (sema, interner) = try makeSema()

        let links = externalLinks(for: "withLock", sema: sema, interner: interner)
        XCTAssertTrue(links.contains("kk_lock_withLock"), "Lock.withLock() stub missing")
    }
}
