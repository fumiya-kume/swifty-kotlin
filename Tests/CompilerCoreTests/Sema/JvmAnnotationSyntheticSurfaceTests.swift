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
}
