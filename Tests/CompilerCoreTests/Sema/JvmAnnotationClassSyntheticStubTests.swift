@testable import CompilerCore
import XCTest

final class JvmAnnotationClassSyntheticStubTests: XCTestCase {
    private func makeSema(source: String = "fun noop() {}") throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected Annotation.annotationClass source to type-check, got: \(ctx.diagnostics.diagnostics)"
            )
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testAnnotationClassPropertySurfaceIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let propertyFQName = ["kotlin", "jvm", "annotationClass"].map { interner.intern($0) }
        let propertySymbol = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: propertyFQName).first { symbolID in
                sema.symbols.symbol(symbolID)?.kind == .property
                    && sema.symbols.extensionPropertyReceiverType(for: symbolID) != nil
            },
            "Expected kotlin.jvm.annotationClass extension property"
        )
        XCTAssertEqual(sema.symbols.externalLinkName(for: propertySymbol), "kk_annotation_get_class")

        let getterSymbol = try XCTUnwrap(sema.symbols.extensionPropertyGetterAccessor(for: propertySymbol))
        XCTAssertEqual(sema.symbols.externalLinkName(for: getterSymbol), "kk_annotation_get_class")

        let getterSignature = try XCTUnwrap(sema.symbols.functionSignature(for: getterSymbol))
        XCTAssertEqual(getterSignature.parameterTypes, [])
        XCTAssertEqual(getterSignature.typeParameterSymbols.count, 1)
        XCTAssertEqual(getterSignature.classTypeParameterCount, 0)

        let typeParamSymbol = try XCTUnwrap(getterSignature.typeParameterSymbols.first)
        let annotationSymbol = try XCTUnwrap(sema.types.annotationInterfaceSymbol)
        let annotationType = sema.types.make(.classType(ClassType(
            classSymbol: annotationSymbol,
            args: [],
            nullability: .nonNull
        )))
        XCTAssertEqual(getterSignature.typeParameterUpperBoundsList, [[annotationType]])
        XCTAssertEqual(sema.symbols.typeParameterUpperBounds(for: typeParamSymbol), [annotationType])

        let receiverType = try XCTUnwrap(getterSignature.receiverType)
        guard case let .typeParam(receiverTypeParam) = sema.types.kind(of: receiverType) else {
            return XCTFail("Expected T : Annotation receiver, got \(sema.types.renderType(receiverType))")
        }
        XCTAssertEqual(receiverTypeParam.symbol, typeParamSymbol)

        guard case let .classType(returnClassType) = sema.types.kind(of: getterSignature.returnType) else {
            return XCTFail("Expected KClass<out T> return type, got \(sema.types.renderType(getterSignature.returnType))")
        }
        let kClassSymbol = try XCTUnwrap(sema.types.kClassInterfaceSymbol)
        XCTAssertEqual(returnClassType.classSymbol, kClassSymbol)
        XCTAssertEqual(returnClassType.args, [.out(receiverType)])
        XCTAssertEqual(sema.symbols.propertyType(for: propertySymbol), getterSignature.returnType)
        XCTAssertEqual(sema.symbols.extensionPropertyReceiverType(for: propertySymbol), receiverType)
    }

    func testAnnotationClassPropertyResolvesFromSource() throws {
        let source = """
        import kotlin.jvm.*
        import kotlin.reflect.KClass

        annotation class Marker

        fun markerClass(marker: Marker): KClass<out Marker> = marker.annotationClass
        fun baseClass(ann: Annotation): KClass<out Annotation> = ann.annotationClass
        """

        let (sema, interner) = try makeSema(source: source)
        for functionName in ["markerClass", "baseClass"] {
            let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: [interner.intern(functionName)]))
            let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbol))
            guard case let .classType(classType) = sema.types.kind(of: signature.returnType) else {
                return XCTFail("\(functionName) should return KClass<out T>, got \(sema.types.renderType(signature.returnType))")
            }
            XCTAssertEqual(classType.classSymbol, sema.types.kClassInterfaceSymbol)
        }
    }
}
