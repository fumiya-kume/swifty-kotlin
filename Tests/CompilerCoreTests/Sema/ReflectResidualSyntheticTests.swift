@testable import CompilerCore
import XCTest

final class ReflectResidualSyntheticTests: XCTestCase {
    private func makeSema(
        source: String = "fun noop() {}"
    ) throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
            XCTAssertFalse(ctx.diagnostics.hasError, "Expected reflect surface to resolve cleanly, got: \(diagnostics)")
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testKTypeEqualsAndHashCodeExternalLinksAreRegistered() throws {
        let (sema, interner) = try makeSema()
        let reflectPackage = ["kotlin", "reflect"].map { interner.intern($0) }
        let kTypeSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: reflectPackage + [interner.intern("KType")])
        )
        let kTypeType = sema.types.make(.classType(ClassType(
            classSymbol: kTypeSymbol,
            args: [],
            nullability: .nonNull
        )))

        let equalsSymbol = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: reflectPackage + [interner.intern("KType"), interner.intern("equals")])
                .first { sema.symbols.externalLinkName(for: $0) == "kk_ktype_equals" }
        )
        let equalsSignature = try XCTUnwrap(sema.symbols.functionSignature(for: equalsSymbol))
        XCTAssertEqual(equalsSignature.receiverType, kTypeType)
        XCTAssertEqual(equalsSignature.parameterTypes, [sema.types.nullableAnyType])
        XCTAssertEqual(equalsSignature.returnType, sema.types.booleanType)

        let hashCodeSymbol = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: reflectPackage + [interner.intern("KType"), interner.intern("hashCode")])
                .first { sema.symbols.externalLinkName(for: $0) == "kk_ktype_hashCode" }
        )
        let hashCodeSignature = try XCTUnwrap(sema.symbols.functionSignature(for: hashCodeSymbol))
        XCTAssertEqual(hashCodeSignature.receiverType, kTypeType)
        XCTAssertEqual(hashCodeSignature.parameterTypes, [])
        XCTAssertEqual(hashCodeSignature.returnType, sema.types.intType)
    }

    func testKCallableVisibilitySurfaceIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let reflectPackage = ["kotlin", "reflect"].map { interner.intern($0) }
        let kCallableSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: reflectPackage + [interner.intern("KCallable")])
        )
        let kFunctionSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: reflectPackage + [interner.intern("KFunction")])
        )
        let kVisibilitySymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: reflectPackage + [interner.intern("KVisibility")])
        )
        let visibilitySymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: reflectPackage + [interner.intern("KCallable"), interner.intern("visibility")])
        )
        let expectedVisibilityType = sema.types.makeNullable(sema.types.make(.classType(ClassType(
            classSymbol: kVisibilitySymbol,
            args: [],
            nullability: .nonNull
        ))))

        XCTAssertEqual(sema.symbols.propertyType(for: visibilitySymbol), expectedVisibilityType)
        XCTAssertTrue(sema.symbols.directSupertypes(for: kFunctionSymbol).contains(kCallableSymbol))
    }

    func testReflectResidualMembersResolveInSource() throws {
        let source = """
        import kotlin.reflect.KFunction
        import kotlin.reflect.KType
        import kotlin.reflect.KVisibility

        fun sameType(a: KType, b: Any?): Boolean = a.equals(b)

        fun typeHash(a: KType): Int = a.hashCode()

        fun functionVisibility(function: KFunction): KVisibility? = function.visibility

        fun functionAnnotations(function: KFunction): Int = function.annotations.size
        """

        _ = try makeSema(source: source)
    }
}
