#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct NativePlatformAnnotationTests {
    private static nonisolated(unsafe) var _sharedSema: (SemaModule, StringInterner)?

    private func sharedSema() throws -> (SemaModule, StringInterner) {
        if let cached = Self._sharedSema { return cached }
        var result: (SemaModule, StringInterner)?
        try withTemporaryFile(contents: "fun noop() {}") { path in
            let ctx = makeCompilationContext(inputs: [path])
            try runSema(ctx)
            result = (try #require(ctx.sema), ctx.interner)
        }
        let semaResult = try #require(result)
        Self._sharedSema = semaResult
        return semaResult
    }

    private func runSemaCollectingDiagnostics(_ source: String) -> CompilationContext {
        let ctx = makeContextFromSource(source)
        do {
            try runSema(ctx)
        } catch {
            // Tests assert on collected diagnostics.
        }
        return ctx
    }

    @Test
    func testFreezingIsDeprecatedMarkerIsRegistered() throws {
        let (sema, interner) = try sharedSema()
        let fqName = ["kotlin", "native", "FreezingIsDeprecated"].map { interner.intern($0) }
        let symbol = try #require(
            sema.symbols.lookup(fqName: fqName),
            "kotlin.native.FreezingIsDeprecated must be registered"
        )

        #expect(sema.symbols.symbol(symbol)?.kind == .annotationClass)
    }

    @Test
    func testFreezingIsDeprecatedCarriesRequiresOptInWarning() throws {
        let (sema, interner) = try sharedSema()
        let fqName = ["kotlin", "native", "FreezingIsDeprecated"].map { interner.intern($0) }
        let symbol = try #require(sema.symbols.lookup(fqName: fqName))
        let requiresOptIn = try #require(
            sema.symbols.annotations(for: symbol).first { $0.annotationFQName == "kotlin.RequiresOptIn" },
            "FreezingIsDeprecated must carry @RequiresOptIn"
        )

        #expect(
            requiresOptIn.arguments.contains("level=RequiresOptIn.Level.WARNING"),
            "FreezingIsDeprecated must be a warning-level opt-in marker; got \(requiresOptIn.arguments)"
        )
        #expect(
            requiresOptIn.arguments.contains { $0.contains("Freezing API is deprecated since 1.7.20") },
            "FreezingIsDeprecated opt-in message should mention the freezing API deprecation"
        )
    }

    @Test
    func testFreezingIsDeprecatedCarriesOfficialKotlinMetadata() throws {
        let (sema, interner) = try sharedSema()
        let fqName = ["kotlin", "native", "FreezingIsDeprecated"].map { interner.intern($0) }
        let symbol = try #require(sema.symbols.lookup(fqName: fqName))
        let annotations = sema.symbols.annotations(for: symbol)

        #expect(
            annotations.contains {
                $0.annotationFQName == "kotlin.SinceKotlin"
                    && $0.arguments == ["\"\"1.7\"\""]
            },
            "FreezingIsDeprecated must carry @SinceKotlin(\"1.7\"); got \(annotations)"
        )
        #expect(
            annotations.contains { $0.annotationFQName == "kotlin.annotation.MustBeDocumented" },
            "FreezingIsDeprecated must carry @MustBeDocumented; got \(annotations)"
        )
        #expect(
            annotations.contains {
                $0.annotationFQName == "kotlin.Deprecated"
                    && $0.arguments == ["\"\"Opting in for the freezing API is no longer supported.\"\""]
            },
            "FreezingIsDeprecated must carry its deprecation message; got \(annotations)"
        )
        #expect(
            annotations.contains {
                $0.annotationFQName == "kotlin.DeprecatedSinceKotlin"
                    && $0.arguments == ["warningSince=\"\"2.1\"\""]
            },
            "FreezingIsDeprecated must carry @DeprecatedSinceKotlin(warningSince=\"2.1\"); got \(annotations)"
        )
    }

    @Test
    func testFreezingIsDeprecatedCarriesNativeTargets() throws {
        let (sema, interner) = try sharedSema()
        let fqName = ["kotlin", "native", "FreezingIsDeprecated"].map { interner.intern($0) }
        let symbol = try #require(sema.symbols.lookup(fqName: fqName))
        let target = try #require(
            sema.symbols.annotations(for: symbol).first { $0.annotationFQName == "kotlin.annotation.Target" },
            "FreezingIsDeprecated must carry @Target metadata"
        )
        let expectedTargets = [
            "AnnotationTarget.CLASS",
            "AnnotationTarget.ANNOTATION_CLASS",
            "AnnotationTarget.PROPERTY",
            "AnnotationTarget.FIELD",
            "AnnotationTarget.LOCAL_VARIABLE",
            "AnnotationTarget.VALUE_PARAMETER",
            "AnnotationTarget.CONSTRUCTOR",
            "AnnotationTarget.FUNCTION",
            "AnnotationTarget.PROPERTY_GETTER",
            "AnnotationTarget.PROPERTY_SETTER",
            "AnnotationTarget.TYPEALIAS",
        ]

        for expectedTarget in expectedTargets {
            #expect(
                target.arguments.contains(expectedTarget),
                "FreezingIsDeprecated @Target should include \(expectedTarget); got \(target.arguments)"
            )
        }
    }

    @Test
    func testUsingFreezingDeprecatedApiProducesWarningDiagnostic() {
        let source = """
        import kotlin.native.FreezingIsDeprecated

        @FreezingIsDeprecated
        fun frozenApi() {}

        fun probe() {
            frozenApi()
        }
        """
        let ctx = runSemaCollectingDiagnostics(source)
        let optInWarnings = ctx.diagnostics.diagnostics.filter {
            $0.code == "KSWIFTK-SEMA-OPT-IN" && $0.severity == .warning
        }

        #expect(
            !optInWarnings.isEmpty,
            "Expected warning-level opt-in diagnostic for FreezingIsDeprecated API usage"
        )
    }

    @Test
    func testOptingInToFreezingIsDeprecatedSuppressesDiagnostic() {
        let source = """
        @file:OptIn(kotlin.native.FreezingIsDeprecated::class)
        import kotlin.native.FreezingIsDeprecated

        @FreezingIsDeprecated
        fun frozenApi() {}

        fun probe() {
            frozenApi()
        }
        """
        let ctx = runSemaCollectingDiagnostics(source)
        let optInDiagnostics = ctx.diagnostics.diagnostics.filter {
            $0.code == "KSWIFTK-SEMA-OPT-IN"
        }

        #expect(
            optInDiagnostics.isEmpty,
            "Expected no opt-in diagnostic when @OptIn(FreezingIsDeprecated::class) is present"
        )
    }

    @Test
    func testObjCNameCarriesExactTopLevelConstructorAndMetadata() throws {
        let (sema, interner) = try sharedSema()
        let fqName = ["kotlin", "native", "ObjCName"].map { interner.intern($0) }
        let symbol = try #require(
            sema.symbols.lookup(fqName: fqName),
            "kotlin.native.ObjCName must be registered"
        )

        #expect(sema.symbols.symbol(symbol)?.kind == .annotationClass)
        #expect(sema.symbols.isSourceBackedSymbol(symbol))

        let annotations = sema.symbols.annotations(for: symbol)
        let target = try #require(
            annotations.first { $0.annotationFQName == "kotlin.annotation.Target" },
            "ObjCName must carry @Target metadata"
        )
        #expect(
            Set(target.arguments)
            == Set([
                "AnnotationTarget.CLASS",
                "AnnotationTarget.PROPERTY",
                "AnnotationTarget.VALUE_PARAMETER",
                "AnnotationTarget.FUNCTION",
            ])
        )
        let retention = try #require(
            annotations.first { $0.annotationFQName == "kotlin.annotation.Retention" },
            "ObjCName must carry @Retention metadata"
        )
        #expect(retention.arguments == ["AnnotationRetention.BINARY"])
        #expect(
            annotations.contains { $0.annotationFQName == "kotlin.annotation.MustBeDocumented" },
            "ObjCName must carry @MustBeDocumented metadata"
        )
        #expect(
            annotations.contains { $0.annotationFQName == "kotlin.experimental.ExperimentalObjCName" },
            "ObjCName must require ExperimentalObjCName opt-in"
        )
        let sinceKotlin = try #require(
            annotations.first { $0.annotationFQName == "kotlin.SinceKotlin" },
            "ObjCName must carry @SinceKotlin metadata"
        )
        #expect(
            sinceKotlin.arguments.contains { $0.contains("1.8") },
            "ObjCName must be available since Kotlin 1.8; got \(sinceKotlin.arguments)"
        )

        let constructor = try #require(
            sema.symbols.lookupAll(fqName: fqName + [interner.intern("<init>")]).first {
                sema.symbols.symbol($0)?.kind == .constructor
            },
            "kotlin.native.ObjCName.<init> must be registered"
        )
        let signature = try #require(sema.symbols.functionSignature(for: constructor))
        #expect(
            signature.parameterTypes
            == [sema.types.stringType, sema.types.stringType, sema.types.booleanType]
        )
        #expect(signature.valueParameterHasDefaultValues == [true, true, true])
        #expect(signature.valueParameterIsVararg == [false, false, false])
        #expect(
            signature.valueParameterSymbols.map { interner.resolve(sema.symbols.symbol($0)!.name) }
            == ["name", "swiftName", "exact"]
        )
    }

    @Test
    func testUsingObjCNameWithoutOptInProducesErrorDiagnostic() {
        let source = """
        import kotlin.native.ObjCName

        @ObjCName
        fun nativeNameProbe(): Int = 1

        fun useNativeNameProbe(): Int = nativeNameProbe()
        """
        let ctx = runSemaCollectingDiagnostics(source)
        let optInErrors = ctx.diagnostics.diagnostics.filter {
            $0.code == "KSWIFTK-SEMA-OPT-IN" && $0.severity == .error
        }

        #expect(
            !optInErrors.isEmpty,
            "Expected error-level opt-in diagnostic for ObjCName usage"
        )
    }

    @Test
    func testOptingInToObjCNameSuppressesDiagnostic() {
        let source = """
        @file:OptIn(kotlin.experimental.ExperimentalObjCName::class)
        import kotlin.native.ObjCName

        @ObjCName
        fun nativeNameProbe(): Int = 1

        fun useNativeNameProbe(): Int = nativeNameProbe()
        """
        let ctx = runSemaCollectingDiagnostics(source)
        let optInDiagnostics = ctx.diagnostics.diagnostics.filter {
            $0.code == "KSWIFTK-SEMA-OPT-IN"
        }

        #expect(
            optInDiagnostics.isEmpty,
            "Expected no opt-in diagnostic when ExperimentalObjCName is opted into"
        )
    }

    @Test
    func testSymbolNameCarriesTopLevelConstructorAndNativeMetadata() throws {
        let (sema, interner) = try sharedSema()
        let fqName = ["kotlin", "native", "SymbolName"].map { interner.intern($0) }
        let symbol = try #require(
            sema.symbols.lookup(fqName: fqName),
            "kotlin.native.SymbolName must be registered"
        )

        #expect(sema.symbols.symbol(symbol)?.kind == .annotationClass)
        #expect(sema.symbols.isSourceBackedSymbol(symbol))

        let annotations = sema.symbols.annotations(for: symbol)
        let target = try #require(
            annotations.first { $0.annotationFQName == "kotlin.annotation.Target" },
            "SymbolName must carry @Target metadata"
        )
        #expect(target.arguments == ["AnnotationTarget.FUNCTION"])
        let retention = try #require(
            annotations.first { $0.annotationFQName == "kotlin.annotation.Retention" },
            "SymbolName must carry @Retention metadata"
        )
        #expect(retention.arguments == ["AnnotationRetention.BINARY"])
        let constructor = try #require(
            sema.symbols.lookupAll(fqName: fqName + [interner.intern("<init>")]).first {
                sema.symbols.symbol($0)?.kind == .constructor
            },
            "kotlin.native.SymbolName.<init> must be registered"
        )
        let signature = try #require(sema.symbols.functionSignature(for: constructor))
        #expect(signature.parameterTypes == [sema.types.stringType])
        #expect(signature.valueParameterHasDefaultValues == [false])
        #expect(signature.valueParameterIsVararg == [false])
        #expect(
            signature.valueParameterSymbols.map { interner.resolve(sema.symbols.symbol($0)!.name) }
            == ["name"]
        )
    }

    @Test
    func testHiddenFromObjCAnnotationIsRegistered() throws {
        let (sema, interner) = try sharedSema()
        let fqName = ["kotlin", "native", "HiddenFromObjC"].map { interner.intern($0) }
        let symbol = try #require(
            sema.symbols.lookup(fqName: fqName),
            "kotlin.native.HiddenFromObjC must be registered"
        )

        #expect(sema.symbols.symbol(symbol)?.kind == .annotationClass)
    }

    @Test
    func testHiddenFromObjCCarriesObjCRefinementMetadata() throws {
        let (sema, interner) = try sharedSema()
        let fqName = ["kotlin", "native", "HiddenFromObjC"].map { interner.intern($0) }
        let symbol = try #require(sema.symbols.lookup(fqName: fqName))
        let annotations = sema.symbols.annotations(for: symbol)

        #expect(
            annotations.contains { $0.annotationFQName == "kotlin.native.HidesFromObjC" },
            "HiddenFromObjC must carry @HidesFromObjC metadata"
        )
        #expect(
            annotations.contains { $0.annotationFQName == "kotlin.experimental.ExperimentalObjCRefinement" },
            "HiddenFromObjC must carry @ExperimentalObjCRefinement metadata"
        )
    }

    @Test
    func testHiddenFromObjCCarriesClassFunctionPropertyTargets() throws {
        let (sema, interner) = try sharedSema()
        let fqName = ["kotlin", "native", "HiddenFromObjC"].map { interner.intern($0) }
        let symbol = try #require(sema.symbols.lookup(fqName: fqName))
        let target = try #require(
            sema.symbols.annotations(for: symbol).first { $0.annotationFQName == "kotlin.annotation.Target" },
            "HiddenFromObjC must carry @Target metadata"
        )

        #expect(
            Set(target.arguments)
            == Set([
                "AnnotationTarget.PROPERTY",
                "AnnotationTarget.FUNCTION",
                "AnnotationTarget.CLASS",
            ])
        )
    }

    @Test
    func testHiddenFromObjCIsAcceptedOnClassFunctionAndProperty() {
        let source = """
        @file:OptIn(kotlin.experimental.ExperimentalObjCRefinement::class)
        import kotlin.native.HiddenFromObjC

        @HiddenFromObjC
        class HiddenType {
            @HiddenFromObjC
            val hiddenProperty: Int = 1

            @HiddenFromObjC
            fun hiddenFunction(): Int = hiddenProperty
        }
        """
        let ctx = runSemaCollectingDiagnostics(source)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }

        #expect(
            errors.isEmpty,
            "Expected HiddenFromObjC on class/function/property to type-check with ObjC refinement opt-in, got \(errors)"
        )
    }

    @Test
    func testNoInlineAnnotationIsRegistered() throws {
        let (sema, interner) = try sharedSema()
        let fqName = ["kotlin", "native", "NoInline"].map { interner.intern($0) }
        let symbol = try #require(
            sema.symbols.lookup(fqName: fqName),
            "kotlin.native.NoInline must be registered"
        )

        #expect(sema.symbols.symbol(symbol)?.kind == .annotationClass)
    }

    @Test
    func testNoInlineCarriesExperimentalNativeApiMetadata() throws {
        let (sema, interner) = try sharedSema()
        let fqName = ["kotlin", "native", "NoInline"].map { interner.intern($0) }
        let symbol = try #require(sema.symbols.lookup(fqName: fqName))
        let annotations = sema.symbols.annotations(for: symbol)

        #expect(
            annotations.contains { $0.annotationFQName == "kotlin.experimental.ExperimentalNativeApi" },
            "NoInline must carry @ExperimentalNativeApi metadata"
        )
    }

    @Test
    func testNoInlineCarriesFunctionPropertyTargets() throws {
        let (sema, interner) = try sharedSema()
        let fqName = ["kotlin", "native", "NoInline"].map { interner.intern($0) }
        let symbol = try #require(sema.symbols.lookup(fqName: fqName))
        let target = try #require(
            sema.symbols.annotations(for: symbol).first { $0.annotationFQName == "kotlin.annotation.Target" },
            "NoInline must carry @Target metadata"
        )

        #expect(
            Set(target.arguments)
            == Set([
                "AnnotationTarget.FUNCTION",
                "AnnotationTarget.PROPERTY",
            ])
        )
    }

    @Test
    func testNoInlineIsAcceptedOnFunctionAndProperty() {
        let source = """
        @file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)
        import kotlin.native.NoInline

        @NoInline
        val nativeValue: Int = 1

        @NoInline
        fun nativeFunction(): Int = nativeValue
        """
        let ctx = runSemaCollectingDiagnostics(source)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }

        #expect(
            errors.isEmpty,
            "Expected NoInline on function/property to type-check with ExperimentalNativeApi opt-in, got \(errors)"
        )
    }

    @Test
    func testObsoleteNativeApiMarkerIsRegistered() throws {
        let (sema, interner) = try sharedSema()
        let fqName = ["kotlin", "native", "ObsoleteNativeApi"].map { interner.intern($0) }
        let symbol = try #require(
            sema.symbols.lookup(fqName: fqName),
            "kotlin.native.ObsoleteNativeApi must be registered"
        )

        #expect(sema.symbols.symbol(symbol)?.kind == .annotationClass)
    }

    @Test
    func testObsoleteNativeApiCarriesRequiresOptInError() throws {
        let (sema, interner) = try sharedSema()
        let fqName = ["kotlin", "native", "ObsoleteNativeApi"].map { interner.intern($0) }
        let symbol = try #require(sema.symbols.lookup(fqName: fqName))
        let requiresOptIn = try #require(
            sema.symbols.annotations(for: symbol).first { $0.annotationFQName == "kotlin.RequiresOptIn" },
            "ObsoleteNativeApi must carry @RequiresOptIn"
        )

        #expect(
            requiresOptIn.arguments.contains("level=RequiresOptIn.Level.ERROR"),
            "ObsoleteNativeApi must be an error-level opt-in marker; got \(requiresOptIn.arguments)"
        )
        #expect(
            requiresOptIn.arguments.contains { $0.contains("obsolete and subject to removal") },
            "ObsoleteNativeApi opt-in message should mention removal risk"
        )
    }

    @Test
    func testObsoleteNativeApiCarriesNativeTargets() throws {
        let (sema, interner) = try sharedSema()
        let fqName = ["kotlin", "native", "ObsoleteNativeApi"].map { interner.intern($0) }
        let symbol = try #require(sema.symbols.lookup(fqName: fqName))
        let target = try #require(
            sema.symbols.annotations(for: symbol).first { $0.annotationFQName == "kotlin.annotation.Target" },
            "ObsoleteNativeApi must carry @Target metadata"
        )
        let expectedTargets = [
            "AnnotationTarget.CLASS",
            "AnnotationTarget.ANNOTATION_CLASS",
            "AnnotationTarget.PROPERTY",
            "AnnotationTarget.FIELD",
            "AnnotationTarget.LOCAL_VARIABLE",
            "AnnotationTarget.VALUE_PARAMETER",
            "AnnotationTarget.CONSTRUCTOR",
            "AnnotationTarget.FUNCTION",
            "AnnotationTarget.PROPERTY_GETTER",
            "AnnotationTarget.PROPERTY_SETTER",
            "AnnotationTarget.TYPEALIAS",
        ]

        for expectedTarget in expectedTargets {
            #expect(
                target.arguments.contains(expectedTarget),
                "ObsoleteNativeApi @Target should include \(expectedTarget); got \(target.arguments)"
            )
        }
    }

    @Test
    func testUsingObsoleteNativeApiWithoutOptInProducesErrorDiagnostic() {
        let source = """
        import kotlin.native.ObsoleteNativeApi

        @ObsoleteNativeApi
        fun obsoleteApi() {}

        fun probe() {
            obsoleteApi()
        }
        """
        let ctx = runSemaCollectingDiagnostics(source)
        let optInErrors = ctx.diagnostics.diagnostics.filter {
            $0.code == "KSWIFTK-SEMA-OPT-IN" && $0.severity == .error
        }

        #expect(
            !optInErrors.isEmpty,
            "Expected error-level opt-in diagnostic for ObsoleteNativeApi usage"
        )
    }

    @Test
    func testOptingInToObsoleteNativeApiSuppressesDiagnostic() {
        let source = """
        @file:OptIn(kotlin.native.ObsoleteNativeApi::class)
        import kotlin.native.ObsoleteNativeApi

        @ObsoleteNativeApi
        fun obsoleteApi() {}

        fun probe() {
            obsoleteApi()
        }
        """
        let ctx = runSemaCollectingDiagnostics(source)
        let optInDiagnostics = ctx.diagnostics.diagnostics.filter {
            $0.code == "KSWIFTK-SEMA-OPT-IN"
        }

        #expect(
            optInDiagnostics.isEmpty,
            "Expected no opt-in diagnostic when @OptIn(ObsoleteNativeApi::class) is present"
        )
    }

    @Test
    func testEagerInitializationAnnotationIsRegistered() throws {
        let (sema, interner) = try sharedSema()
        let fqName = ["kotlin", "native", "EagerInitialization"].map { interner.intern($0) }
        let symbol = try #require(
            sema.symbols.lookup(fqName: fqName),
            "kotlin.native.EagerInitialization must be registered"
        )

        #expect(sema.symbols.symbol(symbol)?.kind == .annotationClass)
    }

    @Test
    func testEagerInitializationCarriesStdlibMetadata() throws {
        let (sema, interner) = try sharedSema()
        let fqName = ["kotlin", "native", "EagerInitialization"].map { interner.intern($0) }
        let symbol = try #require(sema.symbols.lookup(fqName: fqName))
        let annotations = sema.symbols.annotations(for: symbol)
        let target = try #require(
            annotations.first { $0.annotationFQName == "kotlin.annotation.Target" },
            "EagerInitialization must carry @Target metadata"
        )
        let retention = try #require(
            annotations.first { $0.annotationFQName == "kotlin.annotation.Retention" },
            "EagerInitialization must carry @Retention metadata"
        )
        let deprecated = try #require(
            annotations.first { $0.annotationFQName == "kotlin.Deprecated" },
            "EagerInitialization must carry @Deprecated metadata"
        )

        #expect(Set(target.arguments) == Set(["AnnotationTarget.PROPERTY"]))
        #expect(retention.arguments == ["AnnotationRetention.BINARY"])
        #expect(
            annotations.contains { $0.annotationFQName == "kotlin.ExperimentalStdlibApi" },
            "EagerInitialization must carry @ExperimentalStdlibApi metadata"
        )
        #expect(
            deprecated.arguments.contains { $0.contains("temporal migration assistance") },
            "EagerInitialization deprecation message should mention temporary migration assistance"
        )
    }

    @Test
    func testEagerInitializationIsAcceptedOnPropertyWithStdlibOptIn() {
        let source = """
        @file:OptIn(kotlin.ExperimentalStdlibApi::class)
        import kotlin.native.EagerInitialization

        @EagerInitialization
        val eagerValue: Int = 1
        """
        let ctx = runSemaCollectingDiagnostics(source)
        let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }

        #expect(
            errors.isEmpty,
            "Expected EagerInitialization on a property to type-check with ExperimentalStdlibApi opt-in, got \(errors)"
        )
    }
}
#endif
