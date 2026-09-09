
/// Kotlin-native metaprogramming annotation stubs.
///
/// Registers synthetic `kotlin.*`, `kotlin.annotation.*`, and
/// `kotlin.experimental.*` annotation classes that are needed for
/// name-resolution and type-checking on any Kotlin target (including Native).
///
/// JVM-specific annotations (`kotlin.jvm.*`) were removed as part of
/// CLEANUP-STUB-084 since this compiler targets macOS native via LLVM.
extension DataFlowSemaPhase {
    func registerSyntheticKotlinAnnotationStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        // kotlin package — ensure built-in metadata annotations are present.
        let kotlinPkg = ensurePackage(
            path: ["kotlin"],
            symbols: symbols,
            interner: interner
        )
        let kotlinPkgSymbol = symbols.lookup(fqName: kotlinPkg) ?? .invalid

        // Suppress, Deprecated, ReplaceWith, and DeprecatedSinceKotlin are provided by bundled Kotlin source
        // (Sources/CompilerCore/Stdlib/kotlin/Suppress.kt, Deprecated.kt, and DeprecatedSinceKotlin.kt).

        registerSyntheticAnnotationClass(
            named: "WasExperimental",
            packageFQName: kotlinPkg,
            packageSymbol: kotlinPkgSymbol,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticAnnotationClass(
            named: "IntroducedAt",
            packageFQName: kotlinPkg,
            packageSymbol: kotlinPkgSymbol,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticAnnotationClass(
            named: "Metadata",
            packageFQName: kotlinPkg,
            packageSymbol: kotlinPkgSymbol,
            symbols: symbols,
            interner: interner
        )

        // kotlin.experimental.ExperimentalTypeInference is now provided by the
        // bundled Kotlin source `Stdlib/kotlin/experimental/TypeInference.kt`
        // (KSP-668). No synthetic registration is needed here.

        // kotlin.annotation package. KSP-918 owns these six declarations in
        // bundled source. Keep the old registration below only as a fallback
        // for configurations that do not inject that source (for example
        // `--no-stdlib`), so normal source-backed compilation never creates a
        // synthetic declaration for this API.
        let kotlinAnnotationPkg = ensurePackage(
            path: ["kotlin", "annotation"],
            symbols: symbols,
            interner: interner
        )
        let kotlinAnnotationPkgSymbol = symbols.lookup(fqName: kotlinAnnotationPkg) ?? .invalid

        let sourceBackedCoreNames = [
            "AnnotationRetention",
            "AnnotationTarget",
            "MustBeDocumented",
            "Repeatable",
            "Retention",
            "Target",
        ].map(interner.intern)
        let hasSourceBackedAnnotationCore = sourceBackedCoreNames.allSatisfy { name in
            guard let symbol = symbols.lookup(fqName: kotlinAnnotationPkg + [name]),
                  let info = symbols.symbol(symbol)
            else { return false }
            return !info.flags.contains(.synthetic) && info.declSite != nil
        }

        if !hasSourceBackedAnnotationCore {
            registerSyntheticAnnotationClass(
                named: "Target",
                packageFQName: kotlinAnnotationPkg,
                packageSymbol: kotlinAnnotationPkgSymbol,
                symbols: symbols,
                interner: interner
            )
            attachAnnotationIfNeeded(
                MetadataAnnotationRecord(
                    annotationFQName: "kotlin.annotation.Target",
                    arguments: ["AnnotationTarget.ANNOTATION_CLASS"]
                ),
                to: kotlinAnnotationPkg + [interner.intern("Target")],
                symbols: symbols
            )

            registerSyntheticAnnotationClass(
                named: "MustBeDocumented",
                packageFQName: kotlinAnnotationPkg,
                packageSymbol: kotlinAnnotationPkgSymbol,
                symbols: symbols,
                interner: interner
            )
            attachAnnotationIfNeeded(
                MetadataAnnotationRecord(
                    annotationFQName: "kotlin.annotation.Target",
                    arguments: ["AnnotationTarget.ANNOTATION_CLASS"]
                ),
                to: kotlinAnnotationPkg + [interner.intern("MustBeDocumented")],
                symbols: symbols
            )

            registerSyntheticAnnotationClass(
                named: "Repeatable",
                packageFQName: kotlinAnnotationPkg,
                packageSymbol: kotlinAnnotationPkgSymbol,
                symbols: symbols,
                interner: interner
            )
            attachAnnotationIfNeeded(
                MetadataAnnotationRecord(
                    annotationFQName: "kotlin.annotation.Target",
                    arguments: ["AnnotationTarget.ANNOTATION_CLASS"]
                ),
                to: kotlinAnnotationPkg + [interner.intern("Repeatable")],
                symbols: symbols
            )

            registerSyntheticAnnotationClass(
                named: "Retention",
                packageFQName: kotlinAnnotationPkg,
                packageSymbol: kotlinAnnotationPkgSymbol,
                symbols: symbols,
                interner: interner
            )
            attachAnnotationIfNeeded(
                MetadataAnnotationRecord(
                    annotationFQName: "kotlin.annotation.Target",
                    arguments: ["AnnotationTarget.ANNOTATION_CLASS"]
                ),
                to: kotlinAnnotationPkg + [interner.intern("Retention")],
                symbols: symbols
            )

            registerSyntheticAnnotationTargetEnum(
                packageFQName: kotlinAnnotationPkg,
                packageSymbol: kotlinAnnotationPkgSymbol,
                symbols: symbols,
                types: types,
                interner: interner
            )
            registerSyntheticAnnotationRetentionEnum(
                packageFQName: kotlinAnnotationPkg,
                packageSymbol: kotlinAnnotationPkgSymbol,
                symbols: symbols,
                types: types,
                interner: interner
            )

            let annotationRetentionName = interner.intern("AnnotationRetention")
            if let retentionSymbol = symbols.lookup(fqName: kotlinAnnotationPkg + [interner.intern("Retention")]),
               let annotationRetentionSymbol = symbols.lookup(fqName: kotlinAnnotationPkg + [annotationRetentionName]),
               let retentionEntrySymbol = symbols.lookup(fqName: kotlinAnnotationPkg + [annotationRetentionName, interner.intern("RUNTIME")])
            {
                let retentionType = types.make(.classType(ClassType(
                    classSymbol: annotationRetentionSymbol,
                    args: [],
                    nullability: .nonNull
                )))
                let valueName = interner.intern("value")
                let retentionName = interner.intern("Retention")
                let valueFQName = kotlinAnnotationPkg + [retentionName, valueName]
                let valueSymbol: SymbolID
                if let existing = symbols.lookup(fqName: valueFQName) {
                    valueSymbol = existing
                } else {
                    valueSymbol = symbols.define(
                        kind: .property,
                        name: valueName,
                        fqName: valueFQName,
                        declSite: nil,
                        visibility: .public,
                        flags: [.synthetic, .constValue]
                    )
                }
                symbols.setParentSymbol(retentionSymbol, for: valueSymbol)
                symbols.setPropertyType(retentionType, for: valueSymbol)
                symbols.setConstValueExprKind(.symbolRef(retentionEntrySymbol), for: valueSymbol)
            }
        }

        if let introducedAtSymbol = symbols.lookup(fqName: kotlinPkg + [interner.intern("IntroducedAt")]) {
            appendSyntheticAnnotation(
                MetadataAnnotationRecord(
                    annotationFQName: KnownCompilerAnnotation.target.qualifiedName,
                    arguments: ["AnnotationTarget.VALUE_PARAMETER"]
                ),
                to: introducedAtSymbol,
                symbols: symbols
            )
            appendSyntheticAnnotation(
                MetadataAnnotationRecord(annotationFQName: "kotlin.annotation.MustBeDocumented"),
                to: introducedAtSymbol,
                symbols: symbols
            )
            appendSyntheticAnnotation(
                MetadataAnnotationRecord(
                    annotationFQName: KnownCompilerAnnotation.experimentalVersionOverloading.qualifiedName
                ),
                to: introducedAtSymbol,
                symbols: symbols
            )
            registerSyntheticStringAnnotationPropertyAndConstructor(
                ownerSymbol: introducedAtSymbol,
                ownerFQName: kotlinPkg + [interner.intern("IntroducedAt")],
                propertyName: "version",
                symbols: symbols,
                types: types,
                interner: interner
            )
        }
    }
}
