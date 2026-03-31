@testable import CompilerCore
import Foundation
import XCTest

final class TestFrameworkSyntheticStubTests: XCTestCase {
    private func makeSema() throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    private func externalLinks(
        for member: String,
        sema: SemaModule,
        interner: StringInterner
    ) -> [String] {
        let fq = ["kotlin", "test", member].map { interner.intern($0) }
        let symbols = sema.symbols.lookupAll(fqName: fq)
        return symbols.compactMap { sema.symbols.externalLinkName(for: $0) }
    }

    func testTestAnnotationsAreRegisteredAsAnnotationClasses() throws {
        let (sema, interner) = try makeSema()

        for name in ["Test", "Before", "After"] {
            let fq = ["kotlin", "test", name].map { interner.intern($0) }
            let symbol = try XCTUnwrap(
                sema.symbols.lookup(fqName: fq),
                "Expected kotlin.test.\(name) to be registered"
            )
            let resolved = try XCTUnwrap(sema.symbols.symbol(symbol))
            XCTAssertEqual(resolved.kind, .annotationClass)
        }
    }

    func testAssertionStubsExposeAllExpectedExternalLinks() throws {
        let (sema, interner) = try makeSema()

        let expected: [String: [String]] = [
            "assertEquals": ["kk_test_assertEquals", "kk_test_assertEquals_message"],
            "assertTrue": ["kk_test_assertTrue", "kk_test_assertTrue_message"],
            "assertNull": ["kk_test_assertNull", "kk_test_assertNull_message"],
        ]

        for (member, links) in expected {
            let actualLinks = Set(externalLinks(for: member, sema: sema, interner: interner))
            for link in links {
                XCTAssertTrue(
                    actualLinks.contains(link),
                    "kotlin.test.\(member) should expose \(link)"
                )
            }
        }
    }

    func testAssertionsAndAnnotationsResolveInSource() throws {
        let source = """
        import kotlin.test.After
        import kotlin.test.Before
        import kotlin.test.Test
        import kotlin.test.assertEquals
        import kotlin.test.assertNull
        import kotlin.test.assertTrue

        class TestFrameworkBasicSuite {
            @Before
            fun setUp() {}

            @After
            fun tearDown() {}

            @Test
            fun testAssertions() {
                assertEquals(1, 1)
                assertEquals("hello", "he" + "llo")
                assertTrue(true)
                assertNull(null)
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)

            let ast = try XCTUnwrap(ctx.ast)
            let sema = try XCTUnwrap(ctx.sema)

            let expectedLinks: [String: String] = [
                "assertEquals": "kk_test_assertEquals",
                "assertTrue": "kk_test_assertTrue",
                "assertNull": "kk_test_assertNull",
            ]

            for (memberName, expectedLinkName) in expectedLinks {
                let callExpr = try XCTUnwrap(firstExprID(in: ast) { _, expr in
                    guard case let .call(calleeExpr, _, _, _) = expr,
                          case let .nameRef(calleeName, _) = ast.arena.expr(calleeExpr)
                    else {
                        return false
                    }
                    return ctx.interner.resolve(calleeName) == memberName
                }, "Expected call to \(memberName) in AST")

                let chosenCallee = try XCTUnwrap(
                    sema.bindings.callBinding(for: callExpr)?.chosenCallee,
                    "Expected \(memberName) to resolve"
                )
                XCTAssertEqual(
                    sema.symbols.externalLinkName(for: chosenCallee),
                    expectedLinkName
                )
            }
        }
    }

    private func lookupTestSymbols(
        sema: SemaModule,
        interner: StringInterner,
        name: String
    ) -> [SymbolID] {
        let fq = ["kotlin", "test", name].map { interner.intern($0) }
        return sema.symbols.lookupAll(fqName: fq)
    }

    func testSyntheticAnnotationsAreRegistered() throws {
        let (sema, interner) = try makeSema()

        for annotationName in ["Test", "Before", "After"] {
            let symbols = lookupTestSymbols(sema: sema, interner: interner, name: annotationName)
            let symbol = try XCTUnwrap(symbols.first, "Expected kotlin.test.\(annotationName)")
            XCTAssertEqual(sema.symbols.symbol(symbol)?.kind, .annotationClass)
        }
    }

    func testSyntheticAssertionStubsHaveExpectedLinks() throws {
        let (sema, interner) = try makeSema()

        let expectedLinks: [(name: String, arity: Int, link: String)] = [
            ("assertEquals", 2, "kk_test_assertEquals"),
            ("assertEquals", 3, "kk_test_assertEquals_message"),
            ("assertTrue", 1, "kk_test_assertTrue"),
            ("assertTrue", 2, "kk_test_assertTrue_message"),
            ("assertNull", 1, "kk_test_assertNull"),
            ("assertNull", 2, "kk_test_assertNull_message"),
        ]

        for entry in expectedLinks {
            let symbols = lookupTestSymbols(sema: sema, interner: interner, name: entry.name)
            let matching = symbols.first { symbolID in
                guard let sig = sema.symbols.functionSignature(for: symbolID) else { return false }
                return sig.parameterTypes.count == entry.arity
                    && sig.returnType == sema.types.unitType
            }
            let symbol = try XCTUnwrap(matching, "Expected kotlin.test.\(entry.name) with arity \(entry.arity)")
            XCTAssertEqual(sema.symbols.externalLinkName(for: symbol), entry.link)
        }
    }
}
