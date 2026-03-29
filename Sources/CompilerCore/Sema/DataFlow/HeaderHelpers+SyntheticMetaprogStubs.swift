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

        // kotlin package — ensure @Suppress is present as an annotation class.
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
}
