@testable import CompilerCore
import XCTest

final class JvmKClassJavaSyntheticStubTests: XCTestCase {
    private func makeSema(source: String = "fun noop() {}") throws -> (SemaModule, StringInterner) {
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: source) { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            XCTAssertFalse(
                ctx.diagnostics.hasError,
                "Expected KClass.java source to type-check, got: \(ctx.diagnostics.diagnostics)"
            )
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    func testKClassJavaPropertySurfaceIsRegistered() throws {
        let (sema, interner) = try makeSema()

        let classFQName = ["java", "lang", "Class"].map { interner.intern($0) }
        let classSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: classFQName),
            "Expected java.lang.Class<T> synthetic class"
        )
        XCTAssertEqual(
            sema.types.nominalTypeParameterSymbols(for: classSymbol).count,
            1,
            "java.lang.Class should be generic"
        )

        let propertyFQName = ["kotlin", "jvm", "java"].map { interner.intern($0) }
        let propertySymbol = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: propertyFQName).first { symbolID in
                sema.symbols.symbol(symbolID)?.kind == .property
                    && sema.symbols.extensionPropertyReceiverType(for: symbolID) != nil
            },
            "Expected kotlin.jvm.java extension property"
        )
        XCTAssertEqual(sema.symbols.externalLinkName(for: propertySymbol), "kk_kclass_java")

        let getterSymbol = try XCTUnwrap(sema.symbols.extensionPropertyGetterAccessor(for: propertySymbol))
        XCTAssertEqual(sema.symbols.externalLinkName(for: getterSymbol), "kk_kclass_java")

        let getterSignature = try XCTUnwrap(sema.symbols.functionSignature(for: getterSymbol))
        XCTAssertEqual(getterSignature.parameterTypes, [])
        XCTAssertEqual(getterSignature.typeParameterSymbols.count, 1)
        XCTAssertEqual(getterSignature.classTypeParameterCount, 0)

        let receiverType = try XCTUnwrap(getterSignature.receiverType)
        guard case let .classType(receiverClassType) = sema.types.kind(of: receiverType) else {
            return XCTFail("Expected KClass<T> receiver, got \(sema.types.renderType(receiverType))")
        }
        let kClassSymbol = try XCTUnwrap(sema.types.kClassInterfaceSymbol)
        XCTAssertEqual(receiverClassType.classSymbol, kClassSymbol)
        guard case let .classType(classType) = sema.types.kind(of: getterSignature.returnType) else {
            return XCTFail("Expected Class<T> return type, got \(sema.types.renderType(getterSignature.returnType))")
        }

        XCTAssertEqual(classType.classSymbol, classSymbol)
        XCTAssertEqual(receiverClassType.args.count, 1)
        XCTAssertEqual(classType.args, receiverClassType.args)
        XCTAssertEqual(sema.symbols.propertyType(for: propertySymbol), getterSignature.returnType)
        XCTAssertEqual(sema.symbols.extensionPropertyReceiverType(for: propertySymbol), receiverType)
    }

    func testKClassJavaPropertyResolvesFromSource() throws {
        let source = """
        import java.lang.Class
        import kotlin.jvm.*
        import kotlin.reflect.KClass

        fun stringClass(): Class<String> = String::class.java
        fun <T : Any> javaClassOf(kclass: KClass<T>): Class<T> = kclass.java
        """
        let (sema, interner) = try makeSema(source: source)

        for functionName in ["stringClass", "javaClassOf"] {
            let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: [interner.intern(functionName)]))
            let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbol))
            guard case .classType = sema.types.kind(of: signature.returnType) else {
                return XCTFail("\(functionName) should return java.lang.Class<T>, got \(sema.types.renderType(signature.returnType))")
            }
        }
    }

    func testKClassJavaClassPropertySurfaceIsRegistered() throws {
        let (sema, interner) = try makeSema()

        let classFQName = ["java", "lang", "Class"].map { interner.intern($0) }
        let classSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: classFQName),
            "Expected java.lang.Class<T> synthetic class"
        )
        let kClassSymbol = try XCTUnwrap(sema.types.kClassInterfaceSymbol)

        let propertyFQName = ["kotlin", "jvm", "javaClass"].map { interner.intern($0) }
        let propertySymbol = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: propertyFQName).first { symbolID in
                sema.symbols.symbol(symbolID)?.kind == .property
                    && sema.symbols.extensionPropertyReceiverType(for: symbolID) != nil
            },
            "Expected kotlin.jvm.javaClass extension property"
        )
        XCTAssertEqual(sema.symbols.externalLinkName(for: propertySymbol), "kk_kclass_javaClass")

        let getterSymbol = try XCTUnwrap(sema.symbols.extensionPropertyGetterAccessor(for: propertySymbol))
        XCTAssertEqual(sema.symbols.externalLinkName(for: getterSymbol), "kk_kclass_javaClass")

        let getterSignature = try XCTUnwrap(sema.symbols.functionSignature(for: getterSymbol))
        XCTAssertEqual(getterSignature.parameterTypes, [])
        XCTAssertEqual(getterSignature.typeParameterSymbols.count, 1)
        XCTAssertEqual(getterSignature.classTypeParameterCount, 0)

        let receiverType = try XCTUnwrap(getterSignature.receiverType)
        guard case let .classType(receiverClassType) = sema.types.kind(of: receiverType) else {
            return XCTFail("Expected KClass<T> receiver, got \(sema.types.renderType(receiverType))")
        }
        guard case let .classType(classType) = sema.types.kind(of: getterSignature.returnType) else {
            return XCTFail("Expected Class<KClass<T>> return type, got \(sema.types.renderType(getterSignature.returnType))")
        }
        guard case let .invariant(returnArgumentType) = classType.args.first,
              case let .classType(returnKClassType) = sema.types.kind(of: returnArgumentType)
        else {
            return XCTFail("Expected invariant KClass<T> return argument")
        }

        XCTAssertEqual(receiverClassType.classSymbol, kClassSymbol)
        XCTAssertEqual(classType.classSymbol, classSymbol)
        XCTAssertEqual(returnKClassType.classSymbol, kClassSymbol)
        XCTAssertEqual(receiverClassType.args.count, 1)
        XCTAssertEqual(returnKClassType.args, receiverClassType.args)
        XCTAssertEqual(sema.symbols.propertyType(for: propertySymbol), getterSignature.returnType)
        XCTAssertEqual(sema.symbols.extensionPropertyReceiverType(for: propertySymbol), receiverType)
    }

    func testClassKotlinPropertySurfaceIsRegistered() throws {
        let (sema, interner) = try makeSema()

        let classFQName = ["java", "lang", "Class"].map { interner.intern($0) }
        let classSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: classFQName),
            "Expected java.lang.Class<T> synthetic class"
        )
        let kClassSymbol = try XCTUnwrap(sema.types.kClassInterfaceSymbol)

        let propertyFQName = ["kotlin", "jvm", "kotlin"].map { interner.intern($0) }
        let propertySymbol = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: propertyFQName).first { symbolID in
                sema.symbols.symbol(symbolID)?.kind == .property
                    && sema.symbols.extensionPropertyReceiverType(for: symbolID) != nil
            },
            "Expected kotlin.jvm.kotlin extension property"
        )
        XCTAssertEqual(sema.symbols.externalLinkName(for: propertySymbol), "kk_class_kotlin")

        let getterSymbol = try XCTUnwrap(sema.symbols.extensionPropertyGetterAccessor(for: propertySymbol))
        XCTAssertEqual(sema.symbols.externalLinkName(for: getterSymbol), "kk_class_kotlin")

        let getterSignature = try XCTUnwrap(sema.symbols.functionSignature(for: getterSymbol))
        XCTAssertEqual(getterSignature.parameterTypes, [])
        XCTAssertEqual(getterSignature.typeParameterSymbols.count, 1)
        XCTAssertEqual(getterSignature.classTypeParameterCount, 0)

        let receiverType = try XCTUnwrap(getterSignature.receiverType)
        guard case let .classType(receiverClassType) = sema.types.kind(of: receiverType) else {
            return XCTFail("Expected Class<T> receiver, got \(sema.types.renderType(receiverType))")
        }
        guard case let .classType(kClassType) = sema.types.kind(of: getterSignature.returnType) else {
            return XCTFail("Expected KClass<T> return type, got \(sema.types.renderType(getterSignature.returnType))")
        }

        XCTAssertEqual(receiverClassType.classSymbol, classSymbol)
        XCTAssertEqual(kClassType.classSymbol, kClassSymbol)
        XCTAssertEqual(receiverClassType.args.count, 1)
        XCTAssertEqual(kClassType.args, receiverClassType.args)
        XCTAssertEqual(sema.symbols.propertyType(for: propertySymbol), getterSignature.returnType)
        XCTAssertEqual(sema.symbols.extensionPropertyReceiverType(for: propertySymbol), receiverType)
    }

    func testKClassJavaPrimitiveTypePropertySurfaceIsRegistered() throws {
        let (sema, interner) = try makeSema()

        let classSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: ["java", "lang", "Class"].map { interner.intern($0) }),
            "Expected java.lang.Class<T> synthetic class"
        )

        let propertyFQName = ["kotlin", "jvm", "javaPrimitiveType"].map { interner.intern($0) }
        let propertySymbol = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: propertyFQName).first { symbolID in
                sema.symbols.symbol(symbolID)?.kind == .property
                    && sema.symbols.extensionPropertyReceiverType(for: symbolID) != nil
            },
            "Expected kotlin.jvm.javaPrimitiveType extension property"
        )
        XCTAssertEqual(sema.symbols.externalLinkName(for: propertySymbol), "kk_kclass_javaPrimitiveType")

        let getterSymbol = try XCTUnwrap(sema.symbols.extensionPropertyGetterAccessor(for: propertySymbol))
        XCTAssertEqual(sema.symbols.externalLinkName(for: getterSymbol), "kk_kclass_javaPrimitiveType")

        let getterSignature = try XCTUnwrap(sema.symbols.functionSignature(for: getterSymbol))
        XCTAssertEqual(getterSignature.parameterTypes, [])
        XCTAssertEqual(getterSignature.typeParameterSymbols.count, 1)
        XCTAssertEqual(getterSignature.classTypeParameterCount, 0)

        let receiverType = try XCTUnwrap(getterSignature.receiverType)
        guard case let .classType(receiverClassType) = sema.types.kind(of: receiverType) else {
            return XCTFail("Expected KClass<T> receiver, got \(sema.types.renderType(receiverType))")
        }
        let kClassSymbol = try XCTUnwrap(sema.types.kClassInterfaceSymbol)
        XCTAssertEqual(receiverClassType.classSymbol, kClassSymbol)
        guard case let .classType(classType) = sema.types.kind(of: getterSignature.returnType) else {
            return XCTFail("Expected nullable Class<T> return type, got \(sema.types.renderType(getterSignature.returnType))")
        }

        XCTAssertEqual(classType.classSymbol, classSymbol)
        XCTAssertEqual(classType.nullability, .nullable)
        XCTAssertEqual(receiverClassType.args.count, 1)
        XCTAssertEqual(classType.args, receiverClassType.args)
        XCTAssertEqual(sema.symbols.propertyType(for: propertySymbol), getterSignature.returnType)
        XCTAssertEqual(sema.symbols.extensionPropertyReceiverType(for: propertySymbol), receiverType)
    }

    func testKClassJavaObjectTypePropertySurfaceIsRegistered() throws {
        let (sema, interner) = try makeSema()

        let classSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: ["java", "lang", "Class"].map { interner.intern($0) }),
            "Expected java.lang.Class<T> synthetic class"
        )

        let propertyFQName = ["kotlin", "jvm", "javaObjectType"].map { interner.intern($0) }
        let propertySymbol = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: propertyFQName).first { symbolID in
                sema.symbols.symbol(symbolID)?.kind == .property
                    && sema.symbols.extensionPropertyReceiverType(for: symbolID) != nil
            },
            "Expected kotlin.jvm.javaObjectType extension property"
        )
        XCTAssertEqual(sema.symbols.externalLinkName(for: propertySymbol), "kk_kclass_javaObjectType")

        let getterSymbol = try XCTUnwrap(sema.symbols.extensionPropertyGetterAccessor(for: propertySymbol))
        XCTAssertEqual(sema.symbols.externalLinkName(for: getterSymbol), "kk_kclass_javaObjectType")

        let getterSignature = try XCTUnwrap(sema.symbols.functionSignature(for: getterSymbol))
        XCTAssertEqual(getterSignature.parameterTypes, [])
        XCTAssertEqual(getterSignature.typeParameterSymbols.count, 1)
        XCTAssertEqual(getterSignature.classTypeParameterCount, 0)

        let receiverType = try XCTUnwrap(getterSignature.receiverType)
        guard case let .classType(receiverClassType) = sema.types.kind(of: receiverType) else {
            return XCTFail("Expected KClass<T> receiver, got \(sema.types.renderType(receiverType))")
        }
        let kClassSymbol = try XCTUnwrap(sema.types.kClassInterfaceSymbol)
        XCTAssertEqual(receiverClassType.classSymbol, kClassSymbol)
        guard case let .classType(classType) = sema.types.kind(of: getterSignature.returnType) else {
            return XCTFail("Expected Class<T> return type, got \(sema.types.renderType(getterSignature.returnType))")
        }

        XCTAssertEqual(classType.classSymbol, classSymbol)
        XCTAssertEqual(receiverClassType.args.count, 1)
        XCTAssertEqual(classType.args, receiverClassType.args)
        XCTAssertEqual(sema.symbols.propertyType(for: propertySymbol), getterSignature.returnType)
        XCTAssertEqual(sema.symbols.extensionPropertyReceiverType(for: propertySymbol), receiverType)
    }

    func testKClassJavaClassPropertyResolvesFromSource() throws {
        let source = """
        import java.lang.Class
        import kotlin.jvm.javaClass
        import kotlin.reflect.KClass

        fun stringKClassClass(): Class<KClass<String>> = String::class.javaClass
        fun <T : Any> kclassClassOf(kclass: KClass<T>): Class<KClass<T>> = kclass.javaClass
        """
        let (sema, interner) = try makeSema(source: source)

        for functionName in ["stringKClassClass", "kclassClassOf"] {
            let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: [interner.intern(functionName)]))
            let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbol))
            guard case .classType = sema.types.kind(of: signature.returnType) else {
                return XCTFail("\(functionName) should return java.lang.Class<KClass<T>>, got \(sema.types.renderType(signature.returnType))")
            }
        }
    }

    func testClassKotlinPropertyResolvesFromSource() throws {
        let source = """
        import java.lang.Class
        import kotlin.jvm.*
        import kotlin.reflect.KClass

        fun stringKClass(clazz: Class<String>): KClass<String> = clazz.kotlin
        fun <T : Any> kotlinClassOf(clazz: Class<T>): KClass<T> = clazz.kotlin
        """
        let (sema, interner) = try makeSema(source: source)

        for functionName in ["stringKClass", "kotlinClassOf"] {
            let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: [interner.intern(functionName)]))
            let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbol))
            guard case .classType = sema.types.kind(of: signature.returnType) else {
                return XCTFail("\(functionName) should return kotlin.reflect.KClass<T>, got \(sema.types.renderType(signature.returnType))")
            }
        }
    }

    func testKClassJavaPrimitiveTypePropertyResolvesFromSource() throws {
        let source = """
        import java.lang.Class
        import kotlin.jvm.javaPrimitiveType
        import kotlin.reflect.KClass

        fun <T : Any> primitiveClassOf(kclass: KClass<T>): Class<T>? = kclass.javaPrimitiveType
        """
        let (sema, interner) = try makeSema(source: source)

        let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: [interner.intern("primitiveClassOf")]))
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbol))
        guard case let .classType(classType) = sema.types.kind(of: signature.returnType) else {
            return XCTFail("primitiveClassOf should return java.lang.Class<T>?, got \(sema.types.renderType(signature.returnType))")
        }
        XCTAssertEqual(classType.nullability, .nullable)
    }

    func testKClassJavaObjectTypePropertyResolvesFromSource() throws {
        let source = """
        import java.lang.Class
        import kotlin.jvm.javaObjectType
        import kotlin.reflect.KClass

        fun <T : Any> javaObjectClassOf(kclass: KClass<T>): Class<T> = kclass.javaObjectType
        """
        let (sema, interner) = try makeSema(source: source)

        let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: [interner.intern("javaObjectClassOf")]))
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: symbol))
        guard case .classType = sema.types.kind(of: signature.returnType) else {
            return XCTFail("javaObjectClassOf should return java.lang.Class<T>, got \(sema.types.renderType(signature.returnType))")
        }
    }
}
