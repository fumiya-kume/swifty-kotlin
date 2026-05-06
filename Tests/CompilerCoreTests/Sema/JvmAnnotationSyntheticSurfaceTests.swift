@testable import CompilerCore
import XCTest

final class JvmAnnotationSyntheticSurfaceTests: XCTestCase {
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
                "Expected JVM annotation surface to resolve cleanly, got: \(diagnostics)"
            )
            result = try (XCTUnwrap(ctx.sema), ctx.interner)
        }
        return try XCTUnwrap(result)
    }

    private func runSemaCollectingDiagnostics(_ source: String) -> CompilationContext {
        let ctx = makeContextFromSource(source)
        do {
            try runSema(ctx)
        } catch {
            // Error diagnostics are asserted by each test.
        }
        return ctx
    }

    private func diagnostics(withCode code: String, in ctx: CompilationContext) -> [Diagnostic] {
        ctx.diagnostics.diagnostics.filter { $0.code == code }
    }

    func testJvmRecordAnnotationIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "jvm", "JvmRecord"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: fqName),
            "kotlin.jvm.JvmRecord must be registered"
        )
        let info = try XCTUnwrap(sema.symbols.symbol(symbol))

        XCTAssertEqual(info.kind, .annotationClass)
        XCTAssertEqual(info.visibility, .public)
        XCTAssertTrue(info.flags.contains(.synthetic))
    }

    func testJvmRecordCarriesClassTarget() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "jvm", "JvmRecord"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: fqName))
        let target = try XCTUnwrap(
            sema.symbols.annotations(for: symbol).first { $0.annotationFQName == "kotlin.annotation.Target" },
            "JvmRecord must carry @Target metadata"
        )

        XCTAssertEqual(target.arguments, ["AnnotationTarget.CLASS"])
    }

    func testJvmRecordResolvesOnClass() throws {
        let source = """
        import kotlin.jvm.JvmRecord

        @JvmRecord
        class User(val name: String)
        """

        _ = try makeSema(source: source)
    }

    func testJvmPackageNameAnnotationIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "jvm", "JvmPackageName"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: fqName),
            "kotlin.jvm.JvmPackageName must be registered"
        )
        let info = try XCTUnwrap(sema.symbols.symbol(symbol))

        XCTAssertEqual(info.kind, .annotationClass)
        XCTAssertEqual(info.visibility, .public)
        XCTAssertTrue(info.flags.contains(.synthetic))
    }

    func testJvmPackageNameCarriesFileTargetAndSourceRetention() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "jvm", "JvmPackageName"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: fqName))
        let annotations = sema.symbols.annotations(for: symbol)

        XCTAssertTrue(
            annotations.contains {
                $0.annotationFQName == "kotlin.annotation.Target"
                    && $0.arguments == ["AnnotationTarget.FILE"]
            },
            "JvmPackageName must carry @Target(FILE), got \(annotations)"
        )
        XCTAssertTrue(
            annotations.contains {
                $0.annotationFQName == "kotlin.annotation.Retention"
                    && $0.arguments == ["AnnotationRetention.SOURCE"]
            },
            "JvmPackageName must carry @Retention(SOURCE), got \(annotations)"
        )
        XCTAssertTrue(
            annotations.contains {
                $0.annotationFQName == "kotlin.annotation.MustBeDocumented"
            },
            "JvmPackageName must carry @MustBeDocumented, got \(annotations)"
        )
        XCTAssertTrue(
            annotations.contains {
                $0.annotationFQName == "kotlin.SinceKotlin"
                    && $0.arguments == ["1.2"]
            },
            "JvmPackageName must carry @SinceKotlin(\"1.2\"), got \(annotations)"
        )
    }

    func testJvmPackageNameHasNamePropertyAndConstructor() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "jvm", "JvmPackageName"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: fqName))
        let nameProperty = try XCTUnwrap(
            sema.symbols.lookup(fqName: fqName + [interner.intern("name")]),
            "JvmPackageName.name must be registered"
        )

        XCTAssertEqual(sema.symbols.propertyType(for: nameProperty), sema.types.stringType)

        let constructorSymbol = try XCTUnwrap(
            sema.symbols.lookupAll(fqName: fqName + [interner.intern("<init>")]).first { symbolID in
                sema.symbols.symbol(symbolID)?.kind == .constructor
            },
            "JvmPackageName(String) constructor must be registered"
        )
        let signature = try XCTUnwrap(sema.symbols.functionSignature(for: constructorSymbol))
        let ownerType = sema.types.make(.classType(ClassType(
            classSymbol: symbol,
            args: [],
            nullability: .nonNull
        )))

        XCTAssertEqual(signature.parameterTypes, [sema.types.stringType])
        XCTAssertEqual(signature.returnType, ownerType)
        XCTAssertEqual(signature.valueParameterHasDefaultValues, [false])
        XCTAssertEqual(signature.valueParameterIsVararg, [false])
    }

    func testJvmPackageNameResolvesOnFile() throws {
        let source = """
        @file:kotlin.jvm.JvmPackageName("com.example.generated")

        package sample

        fun value(): Int = 1
        """

        _ = try makeSema(source: source)
    }

    func testJvmWildcardAnnotationIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "jvm", "JvmWildcard"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: fqName),
            "kotlin.jvm.JvmWildcard must be registered"
        )
        let info = try XCTUnwrap(sema.symbols.symbol(symbol))

        XCTAssertEqual(info.kind, .annotationClass)
        XCTAssertEqual(info.visibility, .public)
        XCTAssertTrue(info.flags.contains(.synthetic))
    }

    func testJvmWildcardCarriesTypeTarget() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "jvm", "JvmWildcard"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: fqName))
        let annotations = sema.symbols.annotations(for: symbol)

        XCTAssertTrue(
            annotations.contains {
                $0.annotationFQName == "kotlin.annotation.Target"
                    && $0.arguments == ["AnnotationTarget.TYPE"]
            },
            "JvmWildcard must carry @Target(TYPE), got \(annotations)"
        )
        XCTAssertTrue(
            annotations.contains {
                $0.annotationFQName == "kotlin.SinceKotlin"
                    && $0.arguments == ["1.0"]
            },
            "JvmWildcard must carry @SinceKotlin(\"1.0\"), got \(annotations)"
        )
    }

    func testJvmWildcardResolvesOnTypeUse() throws {
        let source = """
        import kotlin.jvm.JvmWildcard

        fun identity(value: @JvmWildcard String): String = value
        """

        _ = try makeSema(source: source)
    }

    func testJvmThrowsAnnotationIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "jvm", "Throws"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: fqName),
            "kotlin.jvm.Throws must be registered"
        )
        let info = try XCTUnwrap(sema.symbols.symbol(symbol))

        XCTAssertEqual(info.kind, .annotationClass)
        XCTAssertEqual(info.visibility, .public)
        XCTAssertTrue(info.flags.contains(.synthetic))
    }

    func testJvmThrowsCarriesTargetsAndSinceKotlin() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "jvm", "Throws"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: fqName))
        let annotations = sema.symbols.annotations(for: symbol)

        XCTAssertTrue(
            annotations.contains {
                $0.annotationFQName == "kotlin.annotation.Target"
                    && $0.arguments == [
                        "AnnotationTarget.FUNCTION",
                        "AnnotationTarget.PROPERTY_GETTER",
                        "AnnotationTarget.PROPERTY_SETTER",
                        "AnnotationTarget.CONSTRUCTOR",
                    ]
            },
            "Throws must carry function/getter/setter/constructor targets, got \(annotations)"
        )
        XCTAssertTrue(
            annotations.contains {
                $0.annotationFQName == "kotlin.SinceKotlin"
                    && $0.arguments == ["1.0"]
            },
            "Throws must carry @SinceKotlin(\"1.0\"), got \(annotations)"
        )
    }

    func testJvmThrowsHasExceptionClassesPropertyAndVarargConstructor() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "jvm", "Throws"].map { interner.intern($0) }
        let exceptionClassesSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: fqName + [interner.intern("exceptionClasses")]),
            "Throws.exceptionClasses property must be registered"
        )
        let exceptionClassesType = try XCTUnwrap(sema.symbols.propertyType(for: exceptionClassesSymbol))
        try assertArrayOfOutThrowableKClass(exceptionClassesType, in: sema, interner: interner)

        let constructors = sema.symbols.lookupAll(fqName: fqName + [interner.intern("<init>")])
        let constructorSignature = try XCTUnwrap(
            constructors.lazy.compactMap { sema.symbols.functionSignature(for: $0) }.first { signature in
                signature.valueParameterIsVararg == [true]
                    && signature.valueParameterSymbols.count == 1
            },
            "Throws(vararg exceptionClasses: KClass<out Throwable>) constructor must be registered"
        )
        try assertThrowableKClass(constructorSignature.parameterTypes[0], in: sema, interner: interner)
        let parameter = try XCTUnwrap(sema.symbols.symbol(constructorSignature.valueParameterSymbols[0]))
        XCTAssertEqual(interner.resolve(parameter.name), "exceptionClasses")
    }

    func testJvmThrowsResolvesOnDocumentedDeclarationTargets() throws {
        let source = """
        import kotlin.jvm.Throws

        class Host @Throws() constructor() {
            @get:Throws()
            val readonly: Int = 1

            @set:Throws()
            var value: Int = 0

            @Throws()
            fun expose(): Int = value
        }
        """

        let ctx = runSemaCollectingDiagnostics(source)
        let diagnostics = diagnostics(withCode: "KSWIFTK-SEMA-ANNOTATION-TARGET", in: ctx)

        XCTAssertTrue(diagnostics.isEmpty, "Expected kotlin.jvm.Throws declaration targets to be accepted, got: \(ctx.diagnostics.diagnostics)")
    }

    func testJvmDefaultWithCompatibilityAnnotationIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "jvm", "JvmDefaultWithCompatibility"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: fqName),
            "kotlin.jvm.JvmDefaultWithCompatibility must be registered"
        )
        let info = try XCTUnwrap(sema.symbols.symbol(symbol))

        XCTAssertEqual(info.kind, .annotationClass)
        XCTAssertEqual(info.visibility, .public)
        XCTAssertTrue(info.flags.contains(.synthetic))
    }

    func testJvmDefaultWithCompatibilityCarriesClassTarget() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "jvm", "JvmDefaultWithCompatibility"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: fqName))
        let target = try XCTUnwrap(
            sema.symbols.annotations(for: symbol).first { $0.annotationFQName == "kotlin.annotation.Target" },
            "JvmDefaultWithCompatibility must carry @Target metadata"
        )

        XCTAssertEqual(target.arguments, ["AnnotationTarget.CLASS"])
    }

    func testJvmDefaultWithCompatibilityResolvesOnInterfaceAndClass() throws {
        let source = """
        import kotlin.jvm.JvmDefaultWithCompatibility

        @JvmDefaultWithCompatibility
        interface Service {
            fun ping(): String = "ok"
        }

        @JvmDefaultWithCompatibility
        open class BaseService
        """

        _ = try makeSema(source: source)
    }

    func testJvmDefaultWithoutCompatibilityAnnotationIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "jvm", "JvmDefaultWithoutCompatibility"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: fqName),
            "kotlin.jvm.JvmDefaultWithoutCompatibility must be registered"
        )
        let info = try XCTUnwrap(sema.symbols.symbol(symbol))

        XCTAssertEqual(info.kind, .annotationClass)
        XCTAssertEqual(info.visibility, .public)
        XCTAssertTrue(info.flags.contains(.synthetic))
    }

    func testJvmDefaultWithoutCompatibilityCarriesClassTarget() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "jvm", "JvmDefaultWithoutCompatibility"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: fqName))
        let target = try XCTUnwrap(
            sema.symbols.annotations(for: symbol).first { $0.annotationFQName == "kotlin.annotation.Target" },
            "JvmDefaultWithoutCompatibility must carry @Target metadata"
        )

        XCTAssertEqual(target.arguments, ["AnnotationTarget.CLASS"])
    }

    func testJvmDefaultWithoutCompatibilityResolvesOnInterfaceAndClass() throws {
        let source = """
        import kotlin.jvm.JvmDefaultWithoutCompatibility

        @JvmDefaultWithoutCompatibility
        interface Service {
            fun ping(): String = "ok"
        }

        @JvmDefaultWithoutCompatibility
        open class BaseService
        """

        _ = try makeSema(source: source)
    }

    func testImplicitlyActualizedByJvmDeclarationAnnotationIsRegistered() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "jvm", "ImplicitlyActualizedByJvmDeclaration"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: fqName),
            "kotlin.jvm.ImplicitlyActualizedByJvmDeclaration must be registered"
        )
        let info = try XCTUnwrap(sema.symbols.symbol(symbol))

        XCTAssertEqual(info.kind, .annotationClass)
        XCTAssertEqual(info.visibility, .public)
        XCTAssertTrue(info.flags.contains(.synthetic))
    }

    func testImplicitlyActualizedByJvmDeclarationCarriesMetadata() throws {
        let (sema, interner) = try makeSema()
        let fqName = ["kotlin", "jvm", "ImplicitlyActualizedByJvmDeclaration"].map { interner.intern($0) }
        let symbol = try XCTUnwrap(sema.symbols.lookup(fqName: fqName))
        let annotations = sema.symbols.annotations(for: symbol)

        XCTAssertTrue(
            annotations.contains {
                $0.annotationFQName == "kotlin.annotation.Target"
                    && $0.arguments == ["AnnotationTarget.CLASS"]
            },
            "ImplicitlyActualizedByJvmDeclaration must carry @Target(AnnotationTarget.CLASS), got \(annotations)"
        )
        XCTAssertTrue(
            annotations.contains { $0.annotationFQName == "kotlin.ExperimentalMultiplatform" },
            "ImplicitlyActualizedByJvmDeclaration must carry @ExperimentalMultiplatform, got \(annotations)"
        )
    }

    func testImplicitlyActualizedByJvmDeclarationResolvesOnOptedInClass() throws {
        let source = """
        @file:OptIn(kotlin.ExperimentalMultiplatform::class)

        import kotlin.jvm.ImplicitlyActualizedByJvmDeclaration

        @ImplicitlyActualizedByJvmDeclaration
        class JavaBacked
        """

        _ = try makeSema(source: source)
    }

    private func assertArrayOfOutThrowableKClass(
        _ type: TypeID,
        in sema: SemaModule,
        interner: StringInterner,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        guard case let .classType(arrayType) = sema.types.kind(of: type) else {
            return XCTFail("Expected Array<out KClass<Throwable>>, got \(sema.types.renderType(type))", file: file, line: line)
        }
        let arraySymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: [interner.intern("kotlin"), interner.intern("Array")]),
            file: file,
            line: line
        )
        XCTAssertEqual(arrayType.classSymbol, arraySymbol, file: file, line: line)
        XCTAssertEqual(arrayType.args.count, 1, file: file, line: line)
        guard case let .out(elementType) = arrayType.args[0] else {
            return XCTFail("Expected covariant Array element, got \(arrayType.args[0])", file: file, line: line)
        }
        try assertThrowableKClass(elementType, in: sema, interner: interner, file: file, line: line)
    }

    private func assertThrowableKClass(
        _ type: TypeID,
        in sema: SemaModule,
        interner: StringInterner,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        guard case let .kClassType(kClassType) = sema.types.kind(of: type) else {
            return XCTFail("Expected KClass<Throwable>, got \(sema.types.renderType(type))", file: file, line: line)
        }
        guard case let .classType(argumentType) = sema.types.kind(of: kClassType.argument) else {
            return XCTFail("Expected KClass argument to be Throwable, got \(sema.types.renderType(kClassType.argument))", file: file, line: line)
        }
        let throwableSymbol = try XCTUnwrap(
            sema.symbols.lookup(fqName: [interner.intern("kotlin"), interner.intern("Throwable")]),
            file: file,
            line: line
        )
        XCTAssertEqual(argumentType.classSymbol, throwableSymbol, file: file, line: line)
    }
}
