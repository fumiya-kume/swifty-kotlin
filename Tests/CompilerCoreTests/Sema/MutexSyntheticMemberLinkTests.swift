@testable import CompilerCore
import XCTest

final class MutexSyntheticMemberLinkTests: XCTestCase {
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
        let fq = ["kotlinx", "coroutines", "sync", "Mutex", member].map { interner.intern($0) }
        return sema.symbols.lookupAll(fqName: fq).compactMap { sema.symbols.externalLinkName(for: $0) }
    }

    func testMutexMembersHaveCorrectExternalLinks() throws {
        let (sema, interner) = try makeSema()

        let expectations: [(member: String, link: String)] = [
            ("lock", "kk_mutex_lock"),
            ("unlock", "kk_mutex_unlock"),
            ("tryLock", "kk_mutex_tryLock"),
            ("isLocked", "kk_mutex_isLocked"),
            ("withLock", "kk_mutex_withLock"),
        ]

        for expectation in expectations {
            let links = externalLinks(for: expectation.member, sema: sema, interner: interner)
            XCTAssertTrue(
                links.contains(expectation.link),
                "Mutex.\(expectation.member)() stub missing"
            )
        }
    }
}
