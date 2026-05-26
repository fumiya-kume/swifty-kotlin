@testable import CompilerCore
import XCTest

final class NativeCInteropStringWcstrPropertyTests: XCTestCase {
    func testStringWcstrPropertySurfaceMatchesNativeShape() throws {
        let ctx = makeContextFromSource("fun noop() {}")
        try runSema(ctx)
        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected String.wcstr surface to compile cleanly, got: \(ctx.diagnostics.diagnostics)"
        )
        let sema = try XCTUnwrap(ctx.sema)
        let interner = ctx.interner
        let cinteropPkg = ["kotlinx", "cinterop"].map { interner.intern($0) }

        func cinteropSymbol(_ path: [String]) throws -> SymbolID {
            try XCTUnwrap(
                sema.symbols.lookup(fqName: cinteropPkg + path.map { interner.intern($0) }),
                "kotlinx.cinterop.\(path.joined(separator: ".")) must be registered"
            )
        }
        func cinteropSymbol(_ path: String...) throws -> SymbolID {
            try cinteropSymbol(path)
        }

        let cValuesSymbol = try cinteropSymbol("CValues")
        let uShortVarSymbol = try cinteropSymbol("UShortVar")
        let uShortVarType = sema.types.make(.classType(ClassType(
            classSymbol: uShortVarSymbol,
            args: [],
            nullability: .nonNull
        )))
        let expectedPropertyType = sema.types.make(.classType(ClassType(
            classSymbol: cValuesSymbol,
            args: [.invariant(uShortVarType)],
            nullability: .nonNull
        )))
        let propertyFQName = cinteropPkg + [interner.intern("wcstr")]
        let propertySymbol = try XCTUnwrap(sema.symbols.lookupAll(fqName: propertyFQName).first { symbolID in
            sema.symbols.symbol(symbolID)?.kind == .property
                && sema.symbols.extensionPropertyReceiverType(for: symbolID) == sema.types.stringType
        })
        let getterSymbol = try XCTUnwrap(sema.symbols.extensionPropertyGetterAccessor(for: propertySymbol))
        let getterSignature = try XCTUnwrap(sema.symbols.functionSignature(for: getterSymbol))
        let flags = try XCTUnwrap(sema.symbols.symbol(propertySymbol)?.flags)

        XCTAssertTrue(flags.contains(.synthetic))
        XCTAssertEqual(sema.symbols.parentSymbol(for: propertySymbol), sema.symbols.lookup(fqName: cinteropPkg))
        XCTAssertEqual(sema.symbols.propertyType(for: propertySymbol), expectedPropertyType)
        XCTAssertEqual(getterSignature.receiverType, sema.types.stringType)
        XCTAssertEqual(getterSignature.parameterTypes, [])
        XCTAssertEqual(getterSignature.returnType, expectedPropertyType)
        XCTAssertEqual(sema.symbols.parentSymbol(for: getterSymbol), propertySymbol)
        XCTAssertEqual(sema.symbols.accessorOwnerProperty(for: getterSymbol), propertySymbol)
    }

    func testStringWcstrPropertyResolvesInSource() throws {
        let ctx = makeContextFromSource("""
        import kotlinx.cinterop.wcstr

        fun encode(value: String): Any {
            return value.wcstr
        }
        """)
        try runSema(ctx)

        XCTAssertFalse(
            ctx.diagnostics.hasError,
            "Expected String.wcstr to resolve, got: \(ctx.diagnostics.diagnostics)"
        )
    }
}
