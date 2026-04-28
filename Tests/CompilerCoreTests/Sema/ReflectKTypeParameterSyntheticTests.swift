@testable import CompilerCore
import XCTest

final class ReflectKTypeParameterSyntheticTests: XCTestCase {
    private func makeSema(
        source: String = "fun noop() {}"
    ) throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
            XCTAssertFalse(ctx.diagnostics.hasError, "Expected KTypeParameter surface to resolve cleanly, got: \(diagnostics)")
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testKTypeParameterSurfaceIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let reflectPackage = ["kotlin", "reflect"].map { interner.intern($0) }
        let collectionsPackage = ["kotlin", "collections"].map { interner.intern($0) }

        let kClassifierSymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: reflectPackage + [interner.intern("KClassifier")]
        ))
        let kTypeSymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: reflectPackage + [interner.intern("KType")]
        ))
        let kTypeParameterSymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: reflectPackage + [interner.intern("KTypeParameter")]
        ))
        let kVarianceSymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: reflectPackage + [interner.intern("KVariance")]
        ))
        let listSymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: collectionsPackage + [interner.intern("List")]
        ))

        let kTypeParameterInfo = try XCTUnwrap(sema.symbols.symbol(kTypeParameterSymbol))
        XCTAssertEqual(kTypeParameterInfo.kind, .interface)
        XCTAssertTrue(kTypeParameterInfo.flags.contains(.synthetic))
        XCTAssertTrue(sema.symbols.directSupertypes(for: kTypeParameterSymbol).contains(kClassifierSymbol))

        let kVarianceType = sema.types.make(.classType(ClassType(
            classSymbol: kVarianceSymbol,
            args: [],
            nullability: .nonNull
        )))
        let kTypeType = sema.types.make(.classType(ClassType(
            classSymbol: kTypeSymbol,
            args: [],
            nullability: .nonNull
        )))
        let listOfKType = sema.types.make(.classType(ClassType(
            classSymbol: listSymbol,
            args: [.out(kTypeType)],
            nullability: .nonNull
        )))

        let propertyExpectations: [(name: String, type: TypeID)] = [
            ("name", sema.types.stringType),
            ("isReified", sema.types.booleanType),
            ("variance", kVarianceType),
            ("upperBounds", listOfKType),
        ]
        for expectation in propertyExpectations {
            let propertySymbol = try XCTUnwrap(sema.symbols.lookup(
                fqName: reflectPackage + [interner.intern("KTypeParameter"), interner.intern(expectation.name)]
            ))
            XCTAssertEqual(sema.symbols.parentSymbol(for: propertySymbol), kTypeParameterSymbol)
            XCTAssertEqual(sema.symbols.propertyType(for: propertySymbol), expectation.type)
        }
    }

    func testKTypeParameterPropertiesResolveInSource() throws {
        let source = """
        import kotlin.reflect.KClassifier
        import kotlin.reflect.KType
        import kotlin.reflect.KTypeParameter
        import kotlin.reflect.KVariance

        fun classifierOf(parameter: KTypeParameter): KClassifier = parameter

        fun inspect(parameter: KTypeParameter): KVariance {
            val name: String = parameter.name
            val reified: Boolean = parameter.isReified
            val bounds: List<KType> = parameter.upperBounds
            return parameter.variance
        }
        """

        _ = try makeSema(source: source)
    }
}
