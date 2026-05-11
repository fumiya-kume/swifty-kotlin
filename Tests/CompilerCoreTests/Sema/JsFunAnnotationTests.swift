@testable import CompilerCore
import XCTest

final class JsFunAnnotationTests: XCTestCase {
    private func makeSema(
        source: String = "fun noop() {}"
    ) throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            let diagnostics = ctx.diagnostics.diagnostics
                .map { "\($0.code): \($0.message)" }
                .joined(separator: " | ")
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected JsFun annotation surface to resolve cleanly, got: \(diagnostics)"
            )
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testJsFunAnnotationIsRegisteredInKotlinPackage() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "JsFun"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: fqName),
            "kotlin.JsFun must be registered"
        )
        let info = try XCTUnwrap(sema.symbols.symbol(symbol))

        XCTAssertEqual(info.kind, .annotationClass)
        XCTAssertEqual(info.visibility, .public)
        XCTAssertTrue(info.flags.contains(.synthetic))
    }

    func testJsFunCarriesExpectedMetadata() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "JsFun"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: fqName))
        let target = try XCTUnwrap(
            sema.symbols.annotations(for: symbol).first { $0.annotationFQName == "kotlin.annotation.Target" },
            "JsFun must carry @Target metadata"
        )

        XCTAssertEqual(
            Set(target.arguments),
            Set([
                "AnnotationTarget.FUNCTION",
                "AnnotationTarget.PROPERTY_GETTER",
                "AnnotationTarget.PROPERTY_SETTER",
            ])
        )
        XCTAssertTrue(
            sema.symbols.annotations(for: symbol).contains {
                $0.annotationFQName == "kotlin.js.ExperimentalWasmJsInterop"
            },
            "JsFun must carry ExperimentalWasmJsInterop metadata"
        )
    }

    func testJsFunCodePropertyAndConstructorAreRegistered() throws {
        let (sema, interner) = try makeSema()
        let baseFQName = ["kotlin", "JsFun"].map { interner.intern($0) }
        let annotationSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: baseFQName))
        let propertySymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: baseFQName + [interner.intern("code")]),
            "JsFun.code property must be registered"
        )
        let constructorSymbol = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: baseFQName + [interner.intern("<init>")]).first { symbolID in
                sema.symbols.symbol(symbolID)?.kind == .constructor
            },
            "JsFun String constructor must be registered"
        )
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: constructorSymbol))
        let propertyInfo = try XCTUnwrap(sema.symbols.symbol(propertySymbol))

        XCTAssertEqual(propertyInfo.kind, .property)
        XCTAssertEqual(sema.symbols.parentSymbol(for: propertySymbol), annotationSymbol)
        XCTAssertEqual(signature.parameterTypes, [sema.types.stringType])
        XCTAssertEqual(signature.returnType, sema.types.make(.classType(ClassType(
            classSymbol: annotationSymbol,
            args: [],
            nullability: .nonNull
        ))))
    }
}
