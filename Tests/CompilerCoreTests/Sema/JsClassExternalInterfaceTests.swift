@testable import CompilerCore
import XCTest

final class JsClassExternalInterfaceTests: XCTestCase {
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
                "Expected JsClass external interface surface to resolve cleanly, got: \(diagnostics)"
            )
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testJsClassInterfaceIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "js", "JsClass"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: fqName),
            "kotlin.js.JsClass must be registered"
        )
        let info = try XCTUnwrap(sema.symbols.symbol(symbol))

        XCTAssertEqual(info.kind, .interface)
        XCTAssertEqual(info.visibility, .public)
        XCTAssertTrue(info.flags.contains(.synthetic))
        XCTAssertNotNil(sema.symbols.propertyType(for: symbol))
    }

    func testJsClassTypeParameterIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "js", "JsClass"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: fqName))
        let typeParam = try XCTUnwrap(
            sema.symbols.lookup(fqName: fqName + [interner.intern("T")]),
            "JsClass.T type parameter must be registered"
        )

        XCTAssertEqual(sema.symbols.symbol(typeParam)?.kind, .typeParameter)
        XCTAssertEqual(sema.types.nominalTypeParameterSymbols(for: symbol), [typeParam])
        XCTAssertEqual(sema.types.nominalTypeParameterVariances(for: symbol), [.invariant])
        XCTAssertEqual(sema.symbols.typeParameterUpperBounds(for: typeParam), [sema.types.anyType])

        let type = try XCTUnwrap(sema.symbols.propertyType(for: symbol))
        guard case let .classType(classType) = sema.types.kind(of: type) else {
            return XCTFail("JsClass type must be a class type")
        }
        XCTAssertEqual(classType.classSymbol, symbol)
        XCTAssertEqual(classType.args.count, 1)
        guard case let .invariant(typeArg) = classType.args[0] else {
            return XCTFail("JsClass.T must be invariant")
        }
        guard case let .typeParam(typeParamType) = sema.types.kind(of: typeArg) else {
            return XCTFail("JsClass.T argument must be a type parameter")
        }
        XCTAssertEqual(typeParamType.symbol, typeParam)
    }

    func testNamePropertyIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "js", "JsClass"].map { interner.intern($0) }
        let owner = try XCTUnwrap(sema.symbols.lookup(fqName: fqName))
        let property = try XCTUnwrap(
            sema.symbols.lookup(fqName: fqName + [interner.intern("name")]),
            "JsClass.name property must be registered"
        )
        let info = try XCTUnwrap(sema.symbols.symbol(property))

        XCTAssertEqual(info.kind, .property)
        XCTAssertEqual(info.visibility, .public)
        XCTAssertTrue(info.flags.contains(.synthetic))
        XCTAssertEqual(sema.symbols.parentSymbol(for: property), owner)
        XCTAssertEqual(sema.symbols.propertyType(for: property), sema.types.stringType)
        XCTAssertNil(sema.symbols.externalLinkName(for: property))
    }

    func testKClassJsPropertyIsRegistered() throws {
        let (sema, interner) = try makeSema()

        let jsClassSymbol = try XCTUnwrap(sema.symbols.lookup(fqName: ["kotlin", "js", "JsClass"].map { interner.intern($0) }))
        let propertySymbol = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: ["kotlin", "js", "js"].map { interner.intern($0) }).first { symbolID in
                sema.symbols.symbol(symbolID)?.kind == .property
                    && sema.symbols.extensionPropertyReceiverType(for: symbolID) != nil
            },
            "KClass<T>.js property must be registered"
        )
        XCTAssertEqual(sema.symbols.externalLinkName(for: propertySymbol), "kk_kclass_js")

        let getterSymbol = try XCTUnwrap(sema.symbols.extensionPropertyGetterAccessor(for: propertySymbol))
        XCTAssertEqual(sema.symbols.externalLinkName(for: getterSymbol), "kk_kclass_js")

        let getterSignature = try XCTUnwrap(sema.symbols.functionSignature(for: getterSymbol))
        XCTAssertEqual(getterSignature.parameterTypes, [])
        XCTAssertEqual(getterSignature.typeParameterSymbols.count, 1)
        XCTAssertEqual(getterSignature.classTypeParameterCount, 0)

        let receiverType = try XCTUnwrap(getterSignature.receiverType)
        guard case let .classType(receiverClassType) = sema.types.kind(of: receiverType) else {
            return XCTFail("Expected KClass<T> receiver, got \(sema.types.renderType(receiverType))")
        }
        XCTAssertEqual(receiverClassType.classSymbol, try XCTUnwrap(sema.types.kClassInterfaceSymbol))

        guard case let .classType(returnClassType) = sema.types.kind(of: getterSignature.returnType) else {
            return XCTFail("Expected JsClass<T> return type, got \(sema.types.renderType(getterSignature.returnType))")
        }
        XCTAssertEqual(returnClassType.classSymbol, jsClassSymbol)
        XCTAssertEqual(returnClassType.args, receiverClassType.args)
        XCTAssertEqual(sema.symbols.propertyType(for: propertySymbol), getterSignature.returnType)
        XCTAssertEqual(sema.symbols.extensionPropertyReceiverType(for: propertySymbol), receiverType)
    }

    func testKClassJsPropertyResolvesFromSource() throws {
        let source = """
        import kotlin.js.JsClass
        import kotlin.js.*
        import kotlin.reflect.KClass

        fun stringJsClass(): JsClass<String> = String::class.js
        fun <T : Any> jsClassOf(kclass: KClass<T>): JsClass<T> = kclass.js
        """
        let (sema, interner) = try makeSema(source: source)

        for functionName in ["stringJsClass", "jsClassOf"] {
            let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: [interner.intern(functionName)]))
            let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbol))
            guard case .classType = sema.types.kind(of: signature.returnType) else {
                return XCTFail("\(functionName) should return JsClass<T>, got \(sema.types.renderType(signature.returnType))")
            }
        }
    }
}
