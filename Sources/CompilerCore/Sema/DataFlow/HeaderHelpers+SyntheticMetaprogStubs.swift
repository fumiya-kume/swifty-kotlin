import Foundation

/// STDLIB-METAPROG-116: Basic metaprogramming annotation stubs.
///
/// Registers synthetic `kotlin.jvm.*` annotation classes so that
/// `@JvmStatic`, `@JvmField`, and `@JvmOverloads` are resolvable during
/// name-resolution and type-checking without errors.  Also ensures
/// `kotlin.Suppress` is present as an annotation class so that
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

        registerSyntheticJvmAnnotationClass(
            named: "WasExperimental",
            packageFQName: kotlinPkg,
            packageSymbol: kotlinPkgSymbol,
            symbols: symbols,
            interner: interner
        )

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
            let record = MetadataAnnotationRecord(
                annotationFQName: "kotlin.annotation.Target",
                arguments: ["AnnotationTarget.ANNOTATION_CLASS"]
            )
            var annotations = symbols.annotations(for: targetSymbol)
            if !annotations.contains(record) {
                annotations.append(record)
            }
            symbols.setAnnotations(annotations, for: targetSymbol)
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

        registerSyntheticAnnotationTargetEnum(
            packageFQName: kotlinAnnotationPkg,
            packageSymbol: kotlinAnnotationPkgSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )
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

        for entryName in [
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
        ] {
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
}
