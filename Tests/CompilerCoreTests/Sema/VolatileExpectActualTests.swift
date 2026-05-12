@testable import CompilerCore
import XCTest

final class VolatileExpectActualTests: XCTestCase {
    func testJvmVolatileExpectActualTypealiasLinks() throws {
        let sources = [
            """
            package volatile.expect.test.jvm
            annotation class Volatile
            """,
            """
            package volatile.expect.test.concurrent
            actual typealias Volatile = kotlin.jvm.Volatile
            """,
            """
            package volatile.expect.test.concurrent
            expect annotation class Volatile
            """,
        ]

        let ctx = makeContextFromSources(sources)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { diagnostic in
            if case .error = diagnostic.severity {
                return true
            }
            return false
        }
        XCTAssertTrue(errors.isEmpty, "Expected no semantic errors, got: \(errors)")

        let sema = try XCTUnwrap(ctx.sema)
        let fqName = [
            ctx.interner.intern("volatile"),
            ctx.interner.intern("expect"),
            ctx.interner.intern("test"),
            ctx.interner.intern("concurrent"),
            ctx.interner.intern("Volatile")
        ]
        let symbols = sema.symbols.lookupAll(fqName: fqName).compactMap { sema.symbols.symbol($0) }
        let expectSymbol = try XCTUnwrap(symbols.first { symbol in
            symbol.kind == .annotationClass && symbol.flags.contains(.expectDeclaration)
        })
        let actualSymbol = try XCTUnwrap(symbols.first { symbol in
            symbol.kind == .typeAlias && symbol.flags.contains(.actualDeclaration)
        })

        XCTAssertEqual(sema.symbols.actualSymbol(for: expectSymbol.id), actualSymbol.id)
    }

    func testNativeVolatileExpectActualAnnotationClassLinks() throws {
        let sources = [
            """
            package kotlin.concurrent
            actual annotation class Volatile
            """,
            """
            package kotlin.concurrent
            expect annotation class Volatile
            """,
        ]

        let ctx = makeContextFromSources(sources)
        try runSema(ctx)

        let errors = ctx.diagnostics.diagnostics.filter { diagnostic in
            if case .error = diagnostic.severity {
                return true
            }
            return false
        }
        XCTAssertTrue(errors.isEmpty, "Expected no semantic errors, got: \(errors)")

        let sema = try XCTUnwrap(ctx.sema)
        let fqName = [
            ctx.interner.intern("kotlin"),
            ctx.interner.intern("concurrent"),
            ctx.interner.intern("Volatile")
        ]
        let symbols = sema.symbols.lookupAll(fqName: fqName).compactMap { sema.symbols.symbol($0) }
        let expectSymbol = try XCTUnwrap(symbols.first { symbol in
            symbol.kind == .annotationClass && symbol.flags.contains(.expectDeclaration)
        })
        let actualSymbol = try XCTUnwrap(symbols.first { symbol in
            symbol.kind == .annotationClass && symbol.flags.contains(.actualDeclaration)
        })

        XCTAssertEqual(sema.symbols.actualSymbol(for: expectSymbol.id), actualSymbol.id)
    }
    
    func testExpectActualLinkValidation() throws {
        let sources = [
            """
            package volatile.expect.validation.jvm
            annotation class Volatile
            """,
            """
            package volatile.expect.validation.concurrent
            actual typealias Volatile = kotlin.jvm.Volatile
            """,
            """
            package volatile.expect.validation.concurrent
            expect annotation class Volatile
            """,
        ]

        let ctx = makeContextFromSources(sources)
        try runSema(ctx)

        let sema = try XCTUnwrap(ctx.sema)
        
        // Test validation functionality
        let issues = sema.symbols.validateExpectActualLinks()
        XCTAssertTrue(issues.isEmpty, "Expect/actual link validation failed: \(issues)")
        
        // Test that links are properly established
        let fqName = [
            ctx.interner.intern("volatile"),
            ctx.interner.intern("expect"),
            ctx.interner.intern("validation"),
            ctx.interner.intern("concurrent"),
            ctx.interner.intern("Volatile")
        ]
        let symbols = sema.symbols.lookupAll(fqName: fqName).compactMap { sema.symbols.symbol($0) }
        let expectSymbol = try XCTUnwrap(symbols.first { symbol in
            symbol.kind == .annotationClass && symbol.flags.contains(.expectDeclaration)
        })
        
        // Verify the link exists and is correct
        let linkedActual = sema.symbols.actualSymbol(for: expectSymbol.id)
        XCTAssertNotNil(linkedActual, "Expect symbol should have an actual link")
        
        if let actualId = linkedActual {
            let actualSymbol = try XCTUnwrap(sema.symbols.symbol(actualId))
            XCTAssertTrue(actualSymbol.flags.contains(.actualDeclaration), "Linked symbol should be an actual declaration")
        }
    }
}
