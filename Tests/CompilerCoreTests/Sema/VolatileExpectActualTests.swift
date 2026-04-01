@testable import CompilerCore
import XCTest

final class VolatileExpectActualTests: XCTestCase {
    func testJvmVolatileExpectActualTypealiasLinks() throws {
        let sources = [
            """
            package kotlin.jvm
            annotation class Volatile
            """,
            """
            package kotlin.concurrent
            actual typealias Volatile = kotlin.jvm.Volatile
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
}
