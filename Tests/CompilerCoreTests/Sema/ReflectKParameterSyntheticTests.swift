@testable import CompilerCore
import XCTest

final class ReflectKParameterSyntheticTests: XCTestCase {
    private func makeSema(
        source: String = "fun noop() {}"
    ) throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
            XCTAssertFalse(ctx.diagnostics.hasError, "Expected KParameter surface to resolve cleanly, got: \(diagnostics)")
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testKParameterSurfaceIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let reflectPackage = ["kotlin", "reflect"].map { interner.intern($0) }

        let kAnnotatedElementSymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: reflectPackage + [interner.intern("KAnnotatedElement")]
        ))
        let kTypeSymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: reflectPackage + [interner.intern("KType")]
        ))
        let kParameterSymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: reflectPackage + [interner.intern("KParameter")]
        ))

        let kParameterInfo = try XCTUnwrap(sema.symbols.symbol(kParameterSymbol))
        XCTAssertEqual(kParameterInfo.kind, .interface)
        XCTAssertTrue(kParameterInfo.flags.contains(.synthetic))
        XCTAssertTrue(sema.symbols.directSupertypes(for: kParameterSymbol).contains(kAnnotatedElementSymbol))

        let kTypeType = sema.types.make(.classType(ClassType(
            classSymbol: kTypeSymbol,
            args: [],
            nullability: .nonNull
        )))
        let nullableStringType = sema.types.make(.primitive(.string, .nullable))
        let propertyExpectations: [(name: String, type: TypeID, externalLinkName: String)] = [
            ("index", sema.types.intType, "kk_kparameter_get_index"),
            ("name", nullableStringType, "kk_kparameter_get_name"),
            ("type", kTypeType, "kk_kparameter_get_type"),
            ("isOptional", sema.types.booleanType, "kk_kparameter_is_optional"),
            ("kind", sema.types.intType, "kk_kparameter_get_kind"),
        ]

        for expectation in propertyExpectations {
            let propertySymbol = try XCTUnwrap(sema.symbols.lookup(
                fqName: reflectPackage + [interner.intern("KParameter"), interner.intern(expectation.name)]
            ))
            XCTAssertEqual(sema.symbols.parentSymbol(for: propertySymbol), kParameterSymbol)
            XCTAssertEqual(sema.symbols.propertyType(for: propertySymbol), expectation.type)
            XCTAssertEqual(sema.symbols.externalLinkName(for: propertySymbol), expectation.externalLinkName)
        }
    }

    func testKParameterPropertiesResolveInSource() throws {
        let source = """
        import kotlin.reflect.KAnnotatedElement
        import kotlin.reflect.KParameter
        import kotlin.reflect.KType

        fun annotated(parameter: KParameter): KAnnotatedElement = parameter

        fun inspect(parameter: KParameter): KType {
            val index: Int = parameter.index
            val name: String? = parameter.name
            val optional: Boolean = parameter.isOptional
            val kind: Int = parameter.kind
            return parameter.type
        }
        """

        _ = try makeSema(source: source)
    }
}
