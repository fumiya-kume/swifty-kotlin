@testable import CompilerCore
import XCTest

final class InstantDistantPropertiesSyntheticTests: XCTestCase {
    private func makeSema(source: String = "fun noop() {}") throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
            XCTAssertFalse(ctx.diagnostics.hasError, "Expected Instant distant properties to resolve cleanly, got: \(diagnostics)")
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testInstantDistantExtensionPropertiesAreRegistered() throws {
        let (sema, interner) = try makeSema()
        let kotlinTime = ["kotlin", "time"].map { interner.intern($0) }
        let instantSymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: kotlinTime + [interner.intern("Instant")]
        ))
        let instantType = sema.types.make(.classType(ClassType(
            classSymbol: instantSymbol,
            args: [],
            nullability: .nonNull
        )))
        let boolType = sema.types.make(.primitive(.boolean, .nonNull))

        for property in [
            (name: "isDistantPast", linkName: "kk_instant_is_distant_past"),
            (name: "isDistantFuture", linkName: "kk_instant_is_distant_future"),
        ] {
            let propertySymbol = try XCTUnwrap(
                sema.symbols.lookupAll(fqName: kotlinTime + [interner.intern(property.name)]).first { symbolID in
                    sema.symbols.symbol(symbolID)?.kind == .property
                        && sema.symbols.extensionPropertyReceiverType(for: symbolID) == instantType
                },
                "Expected kotlin.time.Instant.\(property.name) extension property"
            )
            let getterSymbol = try XCTUnwrap(sema.symbols.extensionPropertyGetterAccessor(for: propertySymbol))

            XCTAssertEqual(sema.symbols.propertyType(for: propertySymbol), boolType)
            XCTAssertEqual(sema.symbols.externalLinkName(for: propertySymbol), property.linkName)
            XCTAssertEqual(sema.symbols.externalLinkName(for: getterSymbol), property.linkName)
            XCTAssertEqual(sema.symbols.functionSignature(for: getterSymbol)?.receiverType, instantType)
            XCTAssertEqual(sema.symbols.functionSignature(for: getterSymbol)?.returnType, boolType)
        }
    }

    func testInstantDistantPropertiesResolveInSource() throws {
        let source = """
        import kotlin.time.*

        fun flags(instant: Instant): Boolean {
            return instant.isDistantPast || instant.isDistantFuture
        }
        """

        let (sema, interner) = try makeSema(source: source)
        let flagsSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: [interner.intern("flags")]))
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: flagsSymbol))
        XCTAssertEqual(signature.returnType, sema.types.make(.primitive(.boolean, .nonNull)))
    }
}
