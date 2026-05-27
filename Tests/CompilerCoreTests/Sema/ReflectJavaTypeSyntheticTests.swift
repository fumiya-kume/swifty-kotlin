@testable import CompilerCore
import XCTest

final class ReflectJavaTypeSyntheticTests: XCTestCase {
    private func makeSema(
        source: String = "fun noop() {}"
    ) throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics.map { "\($0.code): \($0.message)" }.joined(separator: " | ")
            XCTAssertFalse(ctx.diagnostics.hasError, "Expected javaType surface to resolve cleanly, got: \(diagnostics)")
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testKTypeJavaTypeExtensionPropertyIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let kotlinReflectPackage = ["kotlin", "reflect"].map { interner.intern($0) }
        let kotlinReflectJvmPackage = ["kotlin", "reflect", "jvm"].map { interner.intern($0) }
        let javaLangReflectPackage = ["java", "lang", "reflect"].map { interner.intern($0) }

        let kTypeSymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: kotlinReflectPackage + [interner.intern("KType")]
        ))
        let javaTypeSymbol = try XCTUnwrap(sema.symbols.lookup(
            fqName: javaLangReflectPackage + [interner.intern("Type")]
        ))
        XCTAssertEqual(sema.symbols.symbol(javaTypeSymbol)?.kind, .interface)

        let propertySymbol = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: kotlinReflectJvmPackage + [interner.intern("javaType")]).first { symbolID in
                sema.symbols.symbol(symbolID)?.kind == .property
            },
            "Expected kotlin.reflect.jvm.KType.javaType extension property"
        )
        let getterSymbol = try XCTUnwrap(sema.symbols.extensionPropertyGetterAccessor(for: propertySymbol))

        let receiverType = sema.types.make(.classType(ClassType(
            classSymbol: kTypeSymbol,
            args: [],
            nullability: .nonNull
        )))
        let returnType = sema.types.make(.classType(ClassType(
            classSymbol: javaTypeSymbol,
            args: [],
            nullability: .nonNull
        )))
        XCTAssertEqual(sema.symbols.extensionPropertyReceiverType(for: propertySymbol), receiverType)
        XCTAssertEqual(sema.symbols.propertyType(for: propertySymbol), returnType)

        let getterSignature = try XCTUnwrap(sema.symbols.functionSignature(for: getterSymbol))
        XCTAssertEqual(getterSignature.receiverType, receiverType)
        XCTAssertEqual(getterSignature.parameterTypes, [])
        XCTAssertEqual(getterSignature.returnType, returnType)
    }

    func testKTypeJavaTypeResolvesInSource() throws {
        let source = """
        import java.lang.reflect.Type
        import kotlin.reflect.KType
        import kotlin.reflect.jvm.javaType

        fun javaTypeOf(type: KType): Type = type.javaType
        """

        _ = try makeSema(source: source)
    }
}
