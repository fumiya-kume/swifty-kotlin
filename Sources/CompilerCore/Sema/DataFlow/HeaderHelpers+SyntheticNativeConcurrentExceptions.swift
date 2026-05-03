import Foundation

/// Synthetic stdlib stubs for `kotlin.native.concurrent`: FreezingException and InvalidMutabilityException classes.
///
/// Split out from `HeaderHelpers+SyntheticNativeConcurrentStubs.swift` to isolate
/// merge conflicts between parallel stdlib PRs adding new entries to this package.
extension DataFlowSemaPhase {

    // MARK: - FreezingException

    func registerNativeConcurrentFreezingException(
        packageFQName: [InternedString],
        pkgSymbol: SymbolID?,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let exceptionName = interner.intern("FreezingException")
        let exceptionFQName = packageFQName + [exceptionName]
        let exceptionSymbol: SymbolID
        if let existing = symbols.lookup(fqName: exceptionFQName), symbols.symbol(existing)?.kind == .class {
            exceptionSymbol = existing
        } else {
            exceptionSymbol = symbols.define(
                kind: .class,
                name: exceptionName,
                fqName: exceptionFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        if let pkgSymbol {
            symbols.setParentSymbol(pkgSymbol, for: exceptionSymbol)
        }

        let exceptionType = types.make(.classType(ClassType(
            classSymbol: exceptionSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(exceptionType, for: exceptionSymbol)

        let runtimeExceptionSymbol = nativeConcurrentClassSymbol(
            packagePath: ["kotlin"],
            name: "RuntimeException",
            symbols: symbols,
            interner: interner
        )
        symbols.setDirectSupertypes([runtimeExceptionSymbol], for: exceptionSymbol)
        types.setNominalDirectSupertypes([runtimeExceptionSymbol], for: exceptionSymbol)
        appendNativeConcurrentMetadataAnnotations(
            [MetadataAnnotationRecord(annotationFQName: "kotlin.experimental.ExperimentalNativeApi")],
            to: exceptionSymbol,
            symbols: symbols
        )

        registerNativeConcurrentConstructor(
            ownerSymbol: exceptionSymbol,
            ownerType: exceptionType,
            parameters: [
                (name: "toFreeze", type: types.anyType),
                (name: "blocker", type: types.anyType),
            ],
            defaultValues: [false, false],
            symbols: symbols,
            interner: interner
        )
    }

    // MARK: - InvalidMutabilityException

    func registerNativeConcurrentInvalidMutabilityException(
        packageFQName: [InternedString],
        pkgSymbol: SymbolID?,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let exceptionName = interner.intern("InvalidMutabilityException")
        let exceptionFQName = packageFQName + [exceptionName]
        let exceptionSymbol: SymbolID
        if let existing = symbols.lookup(fqName: exceptionFQName), symbols.symbol(existing)?.kind == .class {
            exceptionSymbol = existing
        } else {
            exceptionSymbol = symbols.define(
                kind: .class,
                name: exceptionName,
                fqName: exceptionFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        if let pkgSymbol {
            symbols.setParentSymbol(pkgSymbol, for: exceptionSymbol)
        }

        let exceptionType = types.make(.classType(ClassType(
            classSymbol: exceptionSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(exceptionType, for: exceptionSymbol)

        let runtimeExceptionSymbol = nativeConcurrentClassSymbol(
            packagePath: ["kotlin"],
            name: "RuntimeException",
            symbols: symbols,
            interner: interner
        )
        symbols.setDirectSupertypes([runtimeExceptionSymbol], for: exceptionSymbol)
        types.setNominalDirectSupertypes([runtimeExceptionSymbol], for: exceptionSymbol)
        appendNativeConcurrentMetadataAnnotations(
            [MetadataAnnotationRecord(annotationFQName: "kotlin.experimental.ExperimentalNativeApi")],
            to: exceptionSymbol,
            symbols: symbols
        )

        registerNativeConcurrentConstructor(
            ownerSymbol: exceptionSymbol,
            ownerType: exceptionType,
            parameters: [(name: "message", type: types.stringType)],
            defaultValues: [false],
            symbols: symbols,
            interner: interner
        )
    }
}
