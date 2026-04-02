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
        for owner: String,
        member: String,
        sema: SemaModule,
        interner: StringInterner
    ) -> [String] {
        let fq = ["kotlin", "concurrent", owner, member].map { interner.intern($0) }
        return sema.symbols.lookupAll(fqName: fq).compactMap { sema.symbols.externalLinkName(for: $0) }
    }

    func testLockWithLockMemberHasCorrectExternalLink() throws {
        let (sema, interner) = try makeSema()

        let links = externalLinks(for: "Lock", member: "withLock", sema: sema, interner: interner)
        XCTAssertTrue(links.contains("kk_lock_withLock"), "Lock.withLock() stub missing")
    }

    func testReadWriteLockMembersHaveCorrectExternalLinks() throws {
        let (sema, interner) = try makeSema()

        let factoryFq = ["kotlin", "concurrent", "readWriteLock"].map { interner.intern($0) }
        let factoryLinks = sema.symbols.lookupAll(fqName: factoryFq).compactMap { sema.symbols.externalLinkName(for: $0) }
        XCTAssertTrue(factoryLinks.contains("kk_read_write_lock_create"), "readWriteLock() stub missing")

        let readLinks = externalLinks(for: "ReentrantReadWriteLock", member: "read", sema: sema, interner: interner)
        XCTAssertTrue(readLinks.contains("kk_read_write_lock_read"), "ReentrantReadWriteLock.read() stub missing")

        let writeLinks = externalLinks(for: "ReentrantReadWriteLock", member: "write", sema: sema, interner: interner)
        XCTAssertTrue(writeLinks.contains("kk_read_write_lock_write"), "ReentrantReadWriteLock.write() stub missing")
    }
}
