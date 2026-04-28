import Foundation

private enum SyntheticAnnotationAPISurface {
    static let targetEntries = [
        "CLASS",
        "ANNOTATION_CLASS",
        "TYPE_PARAMETER",
        "PROPERTY",
        "FIELD",
        "LOCAL_VARIABLE",
        "VALUE_PARAMETER",
        "CONSTRUCTOR",
        "FUNCTION",
        "PROPERTY_GETTER",
        "PROPERTY_SETTER",
        "TYPE",
        "EXPRESSION",
        "FILE",
        "TYPEALIAS",
    ]

    static let retentionEntries = [
        "SOURCE",
        "BINARY",
        "RUNTIME",
    ]
}

/// STDLIB-METAPROG-116: Basic metaprogramming annotation stubs.
///
/// Registers synthetic `kotlin.jvm.*` annotation classes so that
/// `@JvmStatic`, `@JvmField`, and `@JvmOverloads` are resolvable during
/// name-resolution and type-checking without errors.  Also ensures
/// `kotlin.Suppress` and `kotlin.annotation.*` metaprogramming stubs are present so that
/// `@Suppress("...")` suppression records are created correctly even when
/// no library metadata has been loaded.
///
/// These are compile-time stubs only; runtime behaviour for `@JvmStatic`
/// is handled by `JvmStaticLoweringPass`.
extension DataFlowSemaPhase {
    func registerSyntheticMetaprogStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        // kotlin.jvm package hierarchy
        let kotlinJvmPkg = ensurePackage(
            path: ["kotlin", "jvm"],
            symbols: symbols,
            interner: interner
        )
        let kotlinJvmPkgSymbol = symbols.lookup(fqName: kotlinJvmPkg) ?? .invalid

        // @JvmStatic — companion object members promoted to class-level statics.
        registerSyntheticJvmAnnotationClass(
            named: "JvmStatic",
            packageFQName: kotlinJvmPkg,
            packageSymbol: kotlinJvmPkgSymbol,
            symbols: symbols,
            interner: interner
        )

        // @JvmField — exposes a Kotlin property as a plain JVM field (no getter/setter).
        registerSyntheticJvmAnnotationClass(
            named: "JvmField",
            packageFQName: kotlinJvmPkg,
            packageSymbol: kotlinJvmPkgSymbol,
            symbols: symbols,
            interner: interner
        )

        // @JvmOverloads — instructs the compiler to generate overloaded JVM methods
        // for functions with default parameter values.
        registerSyntheticJvmAnnotationClass(
            named: "JvmOverloads",
            packageFQName: kotlinJvmPkg,
            packageSymbol: kotlinJvmPkgSymbol,
            symbols: symbols,
            interner: interner
        )

        // @JvmName — controls the JVM-level name of the generated class or member.
        registerSyntheticJvmAnnotationClass(
            named: "JvmName",
            packageFQName: kotlinJvmPkg,
            packageSymbol: kotlinJvmPkgSymbol,
            symbols: symbols,
            interner: interner
        )

        // kotlin package — ensure built-in metadata annotations are present.
        let kotlinPkg = ensurePackage(
            path: ["kotlin"],
            symbols: symbols,
            interner: interner
        )
        let kotlinPkgSymbol = symbols.lookup(fqName: kotlinPkg) ?? .invalid

        registerSyntheticJvmAnnotationClass(
            named: "Suppress",
            packageFQName: kotlinPkg,
            packageSymbol: kotlinPkgSymbol,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticJvmAnnotationClass(
            named: "Deprecated",
            packageFQName: kotlinPkg,
            packageSymbol: kotlinPkgSymbol,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticJvmAnnotationClass(
            named: "DeprecatedSinceKotlin",
            packageFQName: kotlinPkg,
            packageSymbol: kotlinPkgSymbol,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticJvmAnnotationClass(
            named: "ReplaceWith",
            packageFQName: kotlinPkg,
            packageSymbol: kotlinPkgSymbol,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticDeprecationLevelEnum(
            packageFQName: kotlinPkg,
            packageSymbol: kotlinPkgSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )
        if let deprecatedSinceKotlinSymbol = symbols.lookup(
            fqName: kotlinPkg + [interner.intern("DeprecatedSinceKotlin")]
        ) {
            registerSyntheticDeprecatedSinceKotlinMembers(
                ownerSymbol: deprecatedSinceKotlinSymbol,
                ownerFQName: kotlinPkg + [interner.intern("DeprecatedSinceKotlin")],
                symbols: symbols,
                types: types,
                interner: interner
            )
        }

        registerSyntheticJvmAnnotationClass(
            named: "WasExperimental",
            packageFQName: kotlinPkg,
            packageSymbol: kotlinPkgSymbol,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticJvmAnnotationClass(
            named: "SinceKotlin",
            packageFQName: kotlinPkg,
            packageSymbol: kotlinPkgSymbol,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticJvmAnnotationClass(
            named: "ExtensionFunctionType",
            packageFQName: kotlinPkg,
            packageSymbol: kotlinPkgSymbol,
            symbols: symbols,
            interner: interner
        )
        if let extFunctionTypeSymbol = symbols.lookup(fqName: kotlinPkg + [interner.intern("ExtensionFunctionType")]) {
            let record = MetadataAnnotationRecord(
                annotationFQName: "kotlin.annotation.Target",
                arguments: ["AnnotationTarget.TYPE"]
            )
            var annotations = symbols.annotations(for: extFunctionTypeSymbol)
            if !annotations.contains(record) {
                annotations.append(record)
            }
            symbols.setAnnotations(annotations, for: extFunctionTypeSymbol)
        }

        registerSyntheticJvmAnnotationClass(
            named: "Metadata",
            packageFQName: kotlinPkg,
            packageSymbol: kotlinPkgSymbol,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticJvmAnnotationClass(
            named: "OptIn",
            packageFQName: kotlinPkg,
            packageSymbol: kotlinPkgSymbol,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticJvmAnnotationClass(
            named: "RequiresOptIn",
            packageFQName: kotlinPkg,
            packageSymbol: kotlinPkgSymbol,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticJvmAnnotationClass(
            named: "SubclassOptInRequired",
            packageFQName: kotlinPkg,
            packageSymbol: kotlinPkgSymbol,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticJvmAnnotationClass(
            named: "ConsistentCopyVisibility",
            packageFQName: kotlinPkg,
            packageSymbol: kotlinPkgSymbol,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticJvmAnnotationClass(
            named: "ExposedCopyVisibility",
            packageFQName: kotlinPkg,
            packageSymbol: kotlinPkgSymbol,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticJvmAnnotationClass(
            named: "ParameterName",
            packageFQName: kotlinPkg,
            packageSymbol: kotlinPkgSymbol,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticJvmAnnotationClass(
            named: "IgnorableReturnValue",
            packageFQName: kotlinPkg,
            packageSymbol: kotlinPkgSymbol,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticJvmAnnotationClass(
            named: "MustUseReturnValues",
            packageFQName: kotlinPkg,
            packageSymbol: kotlinPkgSymbol,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticJvmAnnotationClass(
            named: "ExperimentalStdlibApi",
            packageFQName: kotlinPkg,
            packageSymbol: kotlinPkgSymbol,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticJvmAnnotationClass(
            named: "BuilderInference",
            packageFQName: kotlinPkg,
            packageSymbol: kotlinPkgSymbol,
            symbols: symbols,
            interner: interner
        )
        if let optInSymbol = symbols.lookup(fqName: kotlinPkg + [interner.intern("OptIn")]) {
            let record = MetadataAnnotationRecord(
                annotationFQName: "kotlin.annotation.Target",
                arguments: [
                    "AnnotationTarget.CLASS",
                    "AnnotationTarget.ANNOTATION_CLASS",
                    "AnnotationTarget.PROPERTY",
                    "AnnotationTarget.FIELD",
                    "AnnotationTarget.LOCAL_VARIABLE",
                    "AnnotationTarget.VALUE_PARAMETER",
                    "AnnotationTarget.CONSTRUCTOR",
                    "AnnotationTarget.FUNCTION",
                    "AnnotationTarget.TYPEALIAS",
                    "AnnotationTarget.EXPRESSION",
                    "AnnotationTarget.FILE",
                ]
            )
            var annotations = symbols.annotations(for: optInSymbol)
            if !annotations.contains(record) {
                annotations.append(record)
            }
            symbols.setAnnotations(annotations, for: optInSymbol)
        }

        registerSyntheticJvmAnnotationClass(
            named: "OverloadResolutionByLambdaReturnType",
            packageFQName: kotlinPkg,
            packageSymbol: kotlinPkgSymbol,
            symbols: symbols,
            interner: interner
        )
        if let overloadSymbol = symbols.lookup(
            fqName: kotlinPkg + [interner.intern("OverloadResolutionByLambdaReturnType")]
        ) {
            let targetRecord = MetadataAnnotationRecord(
                annotationFQName: "kotlin.annotation.Target",
                arguments: ["AnnotationTarget.FUNCTION"]
            )
            let experimentalRecord = MetadataAnnotationRecord(
                annotationFQName: "kotlin.experimental.ExperimentalTypeInference"
            )
            var annotations = symbols.annotations(for: overloadSymbol)
            if !annotations.contains(targetRecord) {
                annotations.append(targetRecord)
            }
            if !annotations.contains(experimentalRecord) {
                annotations.append(experimentalRecord)
            }
            symbols.setAnnotations(annotations, for: overloadSymbol)
        }
        if let builderInferenceSymbol = symbols.lookup(
            fqName: kotlinPkg + [interner.intern("BuilderInference")]
        ) {
            appendSyntheticAnnotation(
                MetadataAnnotationRecord(
                    annotationFQName: KnownCompilerAnnotation.target.qualifiedName,
                    arguments: [
                        "AnnotationTarget.VALUE_PARAMETER",
                        "AnnotationTarget.FUNCTION",
                        "AnnotationTarget.PROPERTY",
                    ]
                ),
                to: builderInferenceSymbol,
                symbols: symbols
            )
            appendSyntheticAnnotation(
                MetadataAnnotationRecord(
                    annotationFQName: "kotlin.annotation.Retention",
                    arguments: ["AnnotationRetention.BINARY"]
                ),
                to: builderInferenceSymbol,
                symbols: symbols
            )
            appendSyntheticAnnotation(
                MetadataAnnotationRecord(
                    annotationFQName: KnownCompilerAnnotation.experimentalTypeInference.qualifiedName
                ),
                to: builderInferenceSymbol,
                symbols: symbols
            )
        }

        let kotlinExperimentalPkg = ensurePackage(
            path: ["kotlin", "experimental"],
            symbols: symbols,
            interner: interner
        )
        let kotlinExperimentalPkgSymbol = symbols.lookup(fqName: kotlinExperimentalPkg) ?? .invalid
        registerSyntheticAnnotationClass(
            named: "ExperimentalTypeInference",
            packageFQName: kotlinExperimentalPkg,
            packageSymbol: kotlinExperimentalPkgSymbol,
            symbols: symbols,
            interner: interner
        )
        if let experimentalSymbol = symbols.lookup(
            fqName: kotlinExperimentalPkg + [interner.intern("ExperimentalTypeInference")]
        ) {
            let record = MetadataAnnotationRecord(
                annotationFQName: "kotlin.annotation.Target",
                arguments: ["AnnotationTarget.ANNOTATION_CLASS"]
            )
            var annotations = symbols.annotations(for: experimentalSymbol)
            if !annotations.contains(record) {
                annotations.append(record)
            }
            symbols.setAnnotations(annotations, for: experimentalSymbol)
        }

        // kotlin.annotation package — provides @Target and AnnotationTarget.
        let kotlinAnnotationPkg = ensurePackage(
            path: ["kotlin", "annotation"],
            symbols: symbols,
            interner: interner
        )
        let kotlinAnnotationPkgSymbol = symbols.lookup(fqName: kotlinAnnotationPkg) ?? .invalid

        registerSyntheticAnnotationClass(
            named: "Target",
            packageFQName: kotlinAnnotationPkg,
            packageSymbol: kotlinAnnotationPkgSymbol,
            symbols: symbols,
            interner: interner
        )
        if let targetSymbol = symbols.lookup(fqName: kotlinAnnotationPkg + [interner.intern("Target")]) {
            attachAnnotationIfNeeded(
                MetadataAnnotationRecord(
                    annotationFQName: "kotlin.annotation.Target",
                    arguments: ["AnnotationTarget.ANNOTATION_CLASS"]
                ),
                to: kotlinAnnotationPkg + [interner.intern("Target")],
                symbols: symbols
            )
            _ = targetSymbol
        }

        registerSyntheticAnnotationClass(
            named: "MustBeDocumented",
            packageFQName: kotlinAnnotationPkg,
            packageSymbol: kotlinAnnotationPkgSymbol,
            symbols: symbols,
            interner: interner
        )
        if let mustBeDocumentedSymbol = symbols.lookup(fqName: kotlinAnnotationPkg + [interner.intern("MustBeDocumented")]) {
            attachAnnotationIfNeeded(
                MetadataAnnotationRecord(
                    annotationFQName: "kotlin.annotation.Target",
                    arguments: ["AnnotationTarget.ANNOTATION_CLASS"]
                ),
                to: kotlinAnnotationPkg + [interner.intern("MustBeDocumented")],
                symbols: symbols
            )
            _ = mustBeDocumentedSymbol
        }

        registerSyntheticAnnotationClass(
            named: "Repeatable",
            packageFQName: kotlinAnnotationPkg,
            packageSymbol: kotlinAnnotationPkgSymbol,
            symbols: symbols,
            interner: interner
        )
        if let repeatableSymbol = symbols.lookup(fqName: kotlinAnnotationPkg + [interner.intern("Repeatable")]) {
            let record = MetadataAnnotationRecord(
                annotationFQName: "kotlin.annotation.Target",
                arguments: ["AnnotationTarget.ANNOTATION_CLASS"]
            )
            var annotations = symbols.annotations(for: repeatableSymbol)
            if !annotations.contains(record) {
                annotations.append(record)
            }
            symbols.setAnnotations(annotations, for: repeatableSymbol)
        }

        registerSyntheticAnnotationClass(
            named: "Retention",
            packageFQName: kotlinAnnotationPkg,
            packageSymbol: kotlinAnnotationPkgSymbol,
            symbols: symbols,
            interner: interner
        )
        if let retentionSymbol = symbols.lookup(fqName: kotlinAnnotationPkg + [interner.intern("Retention")]) {
            let record = MetadataAnnotationRecord(
                annotationFQName: "kotlin.annotation.Target",
                arguments: ["AnnotationTarget.ANNOTATION_CLASS"]
            )
            var annotations = symbols.annotations(for: retentionSymbol)
            if !annotations.contains(record) {
                annotations.append(record)
            }
            symbols.setAnnotations(annotations, for: retentionSymbol)
        }

        attachAnnotationIfNeeded(
            MetadataAnnotationRecord(annotationFQName: "kotlin.RequiresOptIn"),
            to: kotlinPkg + [interner.intern("ExperimentalStdlibApi")],
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

        if let requiresOptInSymbol = symbols.lookup(fqName: kotlinPkg + [interner.intern("RequiresOptIn")]) {
            appendSyntheticAnnotation(
                MetadataAnnotationRecord(
                    annotationFQName: KnownCompilerAnnotation.target.qualifiedName,
                    arguments: ["AnnotationTarget.ANNOTATION_CLASS"]
                ),
                to: requiresOptInSymbol,
                symbols: symbols
            )
            registerSyntheticRequiresOptInLevelEnum(
                ownerSymbol: requiresOptInSymbol,
                ownerFQName: kotlinPkg + [interner.intern("RequiresOptIn")],
                packageSymbol: kotlinPkgSymbol,
                symbols: symbols,
                types: types,
                interner: interner
            )
        }

        if let subclassOptInSymbol = symbols.lookup(fqName: kotlinPkg + [interner.intern("SubclassOptInRequired")]) {
            appendSyntheticAnnotation(
                MetadataAnnotationRecord(
                    annotationFQName: KnownCompilerAnnotation.target.qualifiedName,
                    arguments: ["AnnotationTarget.CLASS"]
                ),
                to: subclassOptInSymbol,
                symbols: symbols
            )
            registerSyntheticSubclassOptInRequiredMarkerClassProperty(
                ownerSymbol: subclassOptInSymbol,
                ownerFQName: kotlinPkg + [interner.intern("SubclassOptInRequired")],
                symbols: symbols,
                types: types,
                interner: interner
            )
        }

        if let consistentCopyVisibilitySymbol = symbols.lookup(
            fqName: kotlinPkg + [interner.intern("ConsistentCopyVisibility")]
        ) {
            appendSyntheticAnnotation(
                MetadataAnnotationRecord(
                    annotationFQName: KnownCompilerAnnotation.target.qualifiedName,
                    arguments: ["AnnotationTarget.CLASS"]
                ),
                to: consistentCopyVisibilitySymbol,
                symbols: symbols
            )
        }

        if let ignorableReturnValueSymbol = symbols.lookup(
            fqName: kotlinPkg + [interner.intern("IgnorableReturnValue")]
        ) {
            appendSyntheticAnnotation(
                MetadataAnnotationRecord(
                    annotationFQName: KnownCompilerAnnotation.target.qualifiedName,
                    arguments: ["AnnotationTarget.FUNCTION"]
                ),
                to: ignorableReturnValueSymbol,
                symbols: symbols
            )
        }

        if let exposedCopyVisibilitySymbol = symbols.lookup(
            fqName: kotlinPkg + [interner.intern("ExposedCopyVisibility")]
        ) {
            appendSyntheticAnnotation(
                MetadataAnnotationRecord(
                    annotationFQName: KnownCompilerAnnotation.target.qualifiedName,
                    arguments: ["AnnotationTarget.CLASS"]
                ),
                to: exposedCopyVisibilitySymbol,
                symbols: symbols
            )
        }

        if let sinceKotlinSymbol = symbols.lookup(fqName: kotlinPkg + [interner.intern("SinceKotlin")]) {
            appendSyntheticAnnotation(
                MetadataAnnotationRecord(
                    annotationFQName: KnownCompilerAnnotation.target.qualifiedName,
                    arguments: [
                        "AnnotationTarget.CLASS",
                        "AnnotationTarget.PROPERTY",
                        "AnnotationTarget.FIELD",
                        "AnnotationTarget.CONSTRUCTOR",
                        "AnnotationTarget.FUNCTION",
                        "AnnotationTarget.PROPERTY_GETTER",
                        "AnnotationTarget.PROPERTY_SETTER",
                        "AnnotationTarget.TYPEALIAS",
                    ]
                ),
                to: sinceKotlinSymbol,
                symbols: symbols
            )
            registerSyntheticStringAnnotationPropertyAndConstructor(
                ownerSymbol: sinceKotlinSymbol,
                ownerFQName: kotlinPkg + [interner.intern("SinceKotlin")],
                propertyName: "version",
                symbols: symbols,
                types: types,
                interner: interner
            )
        }

        if let mustUseReturnValuesSymbol = symbols.lookup(
            fqName: kotlinPkg + [interner.intern("MustUseReturnValues")]
        ) {
            appendSyntheticAnnotation(
                MetadataAnnotationRecord(
                    annotationFQName: KnownCompilerAnnotation.target.qualifiedName,
                    arguments: [
                        "AnnotationTarget.FILE",
                        "AnnotationTarget.CLASS",
                    ]
                ),
                to: mustUseReturnValuesSymbol,
                symbols: symbols
            )
        }

        if let parameterNameSymbol = symbols.lookup(fqName: kotlinPkg + [interner.intern("ParameterName")]) {
            appendSyntheticAnnotation(
                MetadataAnnotationRecord(
                    annotationFQName: KnownCompilerAnnotation.target.qualifiedName,
                    arguments: ["AnnotationTarget.TYPE"]
                ),
                to: parameterNameSymbol,
                symbols: symbols
            )
            appendSyntheticAnnotation(
                MetadataAnnotationRecord(
                    annotationFQName: "kotlin.annotation.Retention",
                    arguments: ["AnnotationRetention.BINARY"]
                ),
                to: parameterNameSymbol,
                symbols: symbols
            )
            registerSyntheticParameterNameMembers(
                ownerSymbol: parameterNameSymbol,
                ownerFQName: kotlinPkg + [interner.intern("ParameterName")],
                symbols: symbols,
                types: types,
                interner: interner
            )
        }

        if let optInSymbol = symbols.lookup(fqName: kotlinPkg + [interner.intern("OptIn")]) {
            appendSyntheticAnnotation(
                MetadataAnnotationRecord(
                    annotationFQName: KnownCompilerAnnotation.target.qualifiedName,
                    arguments: [
                        "AnnotationTarget.CLASS",
                        "AnnotationTarget.PROPERTY",
                        "AnnotationTarget.LOCAL_VARIABLE",
                        "AnnotationTarget.VALUE_PARAMETER",
                        "AnnotationTarget.CONSTRUCTOR",
                        "AnnotationTarget.FUNCTION",
                        "AnnotationTarget.TYPE",
                        "AnnotationTarget.EXPRESSION",
                        "AnnotationTarget.FILE",
                        "AnnotationTarget.TYPEALIAS",
                    ]
                ),
                to: optInSymbol,
                symbols: symbols
            )
        }
    }

    private func registerSyntheticParameterNameMembers(
        ownerSymbol: SymbolID,
        ownerFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let stringType = types.stringType
        let ownerType = types.make(.classType(ClassType(
            classSymbol: ownerSymbol,
            args: [],
            nullability: .nonNull
        )))

        let name = interner.intern("name")
        let propertyFQName = ownerFQName + [name]
        let propertySymbol: SymbolID
        if let existing = symbols.lookup(fqName: propertyFQName) {
            propertySymbol = existing
        } else {
            propertySymbol = symbols.define(
                kind: .property,
                name: name,
                fqName: propertyFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        symbols.setParentSymbol(ownerSymbol, for: propertySymbol)
        symbols.setPropertyType(stringType, for: propertySymbol)

        let initName = interner.intern("<init>")
        let ctorFQName = ownerFQName + [initName]
        let ctorSymbol: SymbolID
        if let existing = symbols.lookupAll(fqName: ctorFQName).first(where: {
            symbols.symbol($0)?.kind == .constructor
        }) {
            ctorSymbol = existing
        } else {
            ctorSymbol = symbols.define(
                kind: .constructor,
                name: initName,
                fqName: ctorFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        symbols.setParentSymbol(ownerSymbol, for: ctorSymbol)

        let parameterFQName = ctorFQName + [name]
        let parameterSymbol: SymbolID
        if let existing = symbols.lookup(fqName: parameterFQName) {
            parameterSymbol = existing
        } else {
            parameterSymbol = symbols.define(
                kind: .valueParameter,
                name: name,
                fqName: parameterFQName,
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
        }
        symbols.setParentSymbol(ctorSymbol, for: parameterSymbol)
        symbols.setPropertyType(stringType, for: parameterSymbol)

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: ownerType,
                parameterTypes: [stringType],
                returnType: ownerType,
                valueParameterSymbols: [parameterSymbol],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [false]
            ),
            for: ctorSymbol
        )
    }

    private func attachAnnotationIfNeeded(
        _ annotation: MetadataAnnotationRecord,
        to symbolFQName: [InternedString],
        symbols: SymbolTable
    ) {
        guard let symbol = symbols.lookup(fqName: symbolFQName) else {
            return
        }
        var annotations = symbols.annotations(for: symbol)
        if !annotations.contains(annotation) {
            annotations.append(annotation)
            symbols.setAnnotations(annotations, for: symbol)
        }
    }

    private func registerSyntheticJvmAnnotationClass(
        named name: String,
        packageFQName: [InternedString],
        packageSymbol: SymbolID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let className = interner.intern(name)
        let classFQName = packageFQName + [className]
        if let existing = symbols.lookup(fqName: classFQName) {
            if packageSymbol != .invalid {
                symbols.setParentSymbol(packageSymbol, for: existing)
            }
            return
        }

        let classSymbol = symbols.define(
            kind: .annotationClass,
            name: className,
            fqName: classFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        if packageSymbol != .invalid {
            symbols.setParentSymbol(packageSymbol, for: classSymbol)
        }
    }

    private func registerSyntheticAnnotationClass(
        named name: String,
        packageFQName: [InternedString],
        packageSymbol: SymbolID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let className = interner.intern(name)
        let classFQName = packageFQName + [className]
        if let existing = symbols.lookup(fqName: classFQName) {
            if packageSymbol != .invalid {
                symbols.setParentSymbol(packageSymbol, for: existing)
            }
            return
        }

        let classSymbol = symbols.define(
            kind: .annotationClass,
            name: className,
            fqName: classFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        if packageSymbol != .invalid {
            symbols.setParentSymbol(packageSymbol, for: classSymbol)
        }
    }

    private func registerSyntheticAnnotationTargetEnum(
        packageFQName: [InternedString],
        packageSymbol: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let enumName = interner.intern("AnnotationTarget")
        let enumFQName = packageFQName + [enumName]
        let enumSymbol: SymbolID
        if let existing = symbols.lookup(fqName: enumFQName) {
            enumSymbol = existing
            if packageSymbol != .invalid {
                symbols.setParentSymbol(packageSymbol, for: existing)
            }
        } else {
            enumSymbol = symbols.define(
                kind: .enumClass,
                name: enumName,
                fqName: enumFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            if packageSymbol != .invalid {
                symbols.setParentSymbol(packageSymbol, for: enumSymbol)
            }
        }

        let enumType = types.make(.classType(ClassType(
            classSymbol: enumSymbol,
            args: [],
            nullability: .nonNull
        )))

        for entryName in SyntheticAnnotationAPISurface.targetEntries {
            let entry = interner.intern(entryName)
            let entryFQName = enumFQName + [entry]
            let entrySymbol: SymbolID
            if let existing = symbols.lookup(fqName: entryFQName) {
                entrySymbol = existing
            } else {
                entrySymbol = symbols.define(
                    kind: .field,
                    name: entry,
                    fqName: entryFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic]
                )
            }
            symbols.setParentSymbol(enumSymbol, for: entrySymbol)
            if symbols.propertyType(for: entrySymbol) == nil {
                symbols.setPropertyType(enumType, for: entrySymbol)
            }
        }
    }

    private func registerSyntheticDeprecationLevelEnum(
        packageFQName: [InternedString],
        packageSymbol: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let enumName = interner.intern("DeprecationLevel")
        let enumFQName = packageFQName + [enumName]
        let enumSymbol: SymbolID
        if let existing = symbols.lookup(fqName: enumFQName) {
            enumSymbol = existing
            if packageSymbol != .invalid {
                symbols.setParentSymbol(packageSymbol, for: existing)
            }
        } else {
            enumSymbol = symbols.define(
                kind: .enumClass,
                name: enumName,
                fqName: enumFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            if packageSymbol != .invalid {
                symbols.setParentSymbol(packageSymbol, for: enumSymbol)
            }
        }

        let enumType = types.make(.classType(ClassType(
            classSymbol: enumSymbol,
            args: [],
            nullability: .nonNull
        )))

        for entryName in ["WARNING", "ERROR", "HIDDEN"] {
            let entry = interner.intern(entryName)
            let entryFQName = enumFQName + [entry]
            let entrySymbol: SymbolID
            if let existing = symbols.lookup(fqName: entryFQName) {
                entrySymbol = existing
            } else {
                entrySymbol = symbols.define(
                    kind: .field,
                    name: entry,
                    fqName: entryFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic]
                )
            }
            symbols.setParentSymbol(enumSymbol, for: entrySymbol)
            if symbols.propertyType(for: entrySymbol) == nil {
                symbols.setPropertyType(enumType, for: entrySymbol)
            }
        }
    }

    private func registerSyntheticDeprecatedSinceKotlinMembers(
        ownerSymbol: SymbolID,
        ownerFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        appendSyntheticAnnotation(
            MetadataAnnotationRecord(
                annotationFQName: KnownCompilerAnnotation.target.qualifiedName,
                arguments: [
                    "AnnotationTarget.CLASS",
                    "AnnotationTarget.FUNCTION",
                    "AnnotationTarget.PROPERTY",
                    "AnnotationTarget.ANNOTATION_CLASS",
                    "AnnotationTarget.CONSTRUCTOR",
                    "AnnotationTarget.PROPERTY_SETTER",
                    "AnnotationTarget.PROPERTY_GETTER",
                    "AnnotationTarget.TYPEALIAS",
                ]
            ),
            to: ownerSymbol,
            symbols: symbols
        )

        let stringType = types.stringType
        let ownerType = types.make(.classType(ClassType(
            classSymbol: ownerSymbol,
            args: [],
            nullability: .nonNull
        )))
        let propertyNames = ["warningSince", "errorSince", "hiddenSince"].map { interner.intern($0) }
        for propertyName in propertyNames {
            let propertyFQName = ownerFQName + [propertyName]
            let propertySymbol: SymbolID
            if let existing = symbols.lookup(fqName: propertyFQName) {
                propertySymbol = existing
            } else {
                propertySymbol = symbols.define(
                    kind: .property,
                    name: propertyName,
                    fqName: propertyFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic]
                )
            }
            symbols.setParentSymbol(ownerSymbol, for: propertySymbol)
            symbols.setPropertyType(stringType, for: propertySymbol)
        }

        let initName = interner.intern("<init>")
        let ctorFQName = ownerFQName + [initName]
        let ctorSymbol: SymbolID
        if let existing = symbols.lookupAll(fqName: ctorFQName).first(where: {
            symbols.symbol($0)?.kind == .constructor
        }) {
            ctorSymbol = existing
        } else {
            ctorSymbol = symbols.define(
                kind: .constructor,
                name: initName,
                fqName: ctorFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        symbols.setParentSymbol(ownerSymbol, for: ctorSymbol)

        let valueParameterSymbols = propertyNames.map { parameterName -> SymbolID in
            let parameterFQName = ctorFQName + [parameterName]
            let parameterSymbol: SymbolID
            if let existing = symbols.lookup(fqName: parameterFQName) {
                parameterSymbol = existing
            } else {
                parameterSymbol = symbols.define(
                    kind: .valueParameter,
                    name: parameterName,
                    fqName: parameterFQName,
                    declSite: nil,
                    visibility: .private,
                    flags: [.synthetic]
                )
            }
            symbols.setParentSymbol(ctorSymbol, for: parameterSymbol)
            symbols.setPropertyType(stringType, for: parameterSymbol)
            return parameterSymbol
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: ownerType,
                parameterTypes: Array(repeating: stringType, count: valueParameterSymbols.count),
                returnType: ownerType,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: true, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count)
            ),
            for: ctorSymbol
        )
    }

    private func registerSyntheticAnnotationRetentionEnum(
        packageFQName: [InternedString],
        packageSymbol: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let enumName = interner.intern("AnnotationRetention")
        let enumFQName = packageFQName + [enumName]
        let enumSymbol: SymbolID
        if let existing = symbols.lookup(fqName: enumFQName) {
            enumSymbol = existing
            if packageSymbol != .invalid {
                symbols.setParentSymbol(packageSymbol, for: existing)
            }
        } else {
            enumSymbol = symbols.define(
                kind: .enumClass,
                name: enumName,
                fqName: enumFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            if packageSymbol != .invalid {
                symbols.setParentSymbol(packageSymbol, for: enumSymbol)
            }
        }

        let enumType = types.make(.classType(ClassType(
            classSymbol: enumSymbol,
            args: [],
            nullability: .nonNull
        )))

        for entryName in SyntheticAnnotationAPISurface.retentionEntries {
            let entry = interner.intern(entryName)
            let entryFQName = enumFQName + [entry]
            let entrySymbol: SymbolID
            if let existing = symbols.lookup(fqName: entryFQName) {
                entrySymbol = existing
            } else {
                entrySymbol = symbols.define(
                    kind: .field,
                    name: entry,
                    fqName: entryFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic]
                )
            }
            symbols.setParentSymbol(enumSymbol, for: entrySymbol)
            if symbols.propertyType(for: entrySymbol) == nil {
                symbols.setPropertyType(enumType, for: entrySymbol)
            }
        }
    }

    private func registerSyntheticRequiresOptInLevelEnum(
        ownerSymbol: SymbolID,
        ownerFQName: [InternedString],
        packageSymbol: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let levelName = interner.intern("Level")
        let levelFQName = ownerFQName + [levelName]
        let levelSymbol: SymbolID
        if let existing = symbols.lookup(fqName: levelFQName) {
            levelSymbol = existing
        } else {
            levelSymbol = symbols.define(
                kind: .enumClass,
                name: levelName,
                fqName: levelFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        symbols.setParentSymbol(ownerSymbol, for: levelSymbol)
        if packageSymbol != .invalid {
            symbols.setSourceFileID(symbols.sourceFileID(for: packageSymbol) ?? FileID(rawValue: 0), for: levelSymbol)
        }

        let levelType = types.make(.classType(ClassType(
            classSymbol: levelSymbol,
            args: [],
            nullability: .nonNull
        )))

        for entryName in ["WARNING", "ERROR"] {
            let entry = interner.intern(entryName)
            let entryFQName = levelFQName + [entry]
            let entrySymbol: SymbolID
            if let existing = symbols.lookup(fqName: entryFQName) {
                entrySymbol = existing
            } else {
                entrySymbol = symbols.define(
                    kind: .field,
                    name: entry,
                    fqName: entryFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic]
                )
            }
            symbols.setParentSymbol(levelSymbol, for: entrySymbol)
            symbols.setPropertyType(levelType, for: entrySymbol)
        }
    }

    private func registerSyntheticSubclassOptInRequiredMarkerClassProperty(
        ownerSymbol: SymbolID,
        ownerFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let valueName = interner.intern("markerClass")
        let valueFQName = ownerFQName + [valueName]
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
                flags: [.synthetic]
            )
        }

        symbols.setParentSymbol(ownerSymbol, for: valueSymbol)

        let annotationFQName = [interner.intern("kotlin"), interner.intern("Annotation")]
        let annotationType: TypeID
        if let annotationSymbol = symbols.lookup(fqName: annotationFQName) {
            annotationType = types.make(.classType(ClassType(
                classSymbol: annotationSymbol,
                args: [],
                nullability: .nonNull
            )))
        } else {
            annotationType = types.anyType
        }
        symbols.setPropertyType(types.makeKClassType(argument: annotationType), for: valueSymbol)
    }

    private func registerSyntheticStringAnnotationPropertyAndConstructor(
        ownerSymbol: SymbolID,
        ownerFQName: [InternedString],
        propertyName: String,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let property = interner.intern(propertyName)
        let propertyFQName = ownerFQName + [property]
        let propertySymbol: SymbolID
        if let existing = symbols.lookup(fqName: propertyFQName) {
            propertySymbol = existing
        } else {
            propertySymbol = symbols.define(
                kind: .property,
                name: property,
                fqName: propertyFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        symbols.setParentSymbol(ownerSymbol, for: propertySymbol)
        symbols.setPropertyType(types.stringType, for: propertySymbol)

        let initName = interner.intern("<init>")
        let constructorFQName = ownerFQName + [initName]
        let hasMatchingConstructor = symbols.lookupAll(fqName: constructorFQName).contains { symbolID in
            guard let symbol = symbols.symbol(symbolID),
                  symbol.kind == .constructor,
                  let signature = symbols.functionSignature(for: symbolID)
            else {
                return false
            }
            return signature.parameterTypes == [types.stringType]
        }
        guard !hasMatchingConstructor else {
            return
        }

        let constructorSymbol = symbols.define(
            kind: .constructor,
            name: initName,
            fqName: constructorFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: constructorSymbol)

        let parameterSymbol = symbols.define(
            kind: .valueParameter,
            name: property,
            fqName: constructorFQName + [property],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(constructorSymbol, for: parameterSymbol)

        let ownerType = types.make(.classType(ClassType(
            classSymbol: ownerSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: [types.stringType],
                returnType: ownerType,
                valueParameterSymbols: [parameterSymbol],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [false]
            ),
            for: constructorSymbol
        )
    }

    private func appendSyntheticAnnotation(
        _ annotation: MetadataAnnotationRecord,
        to symbol: SymbolID,
        symbols: SymbolTable
    ) {
        var annotations = symbols.annotations(for: symbol)
        if !annotations.contains(annotation) {
            annotations.append(annotation)
            symbols.setAnnotations(annotations, for: symbol)
        }
    }
}

private extension String {
    var wrappedInBrackets: String {
        "[\(self)]"
    }
}
