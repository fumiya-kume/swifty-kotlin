import Foundation

/// Synthetic stubs for five Kotlin stdlib experimental opt-in markers discovered
/// missing in STDLIB-EXPERIMENTAL-ABI-001.
///
/// Each marker is an annotation class annotated with `@RequiresOptIn` at the declared
/// severity level from the Kotlin stdlib source:
///
/// | Annotation                | Package              | Severity |
/// |---------------------------|----------------------|----------|
/// | ExperimentalUnsignedTypes | kotlin               | ERROR    |
/// | ExperimentalUuidApi       | kotlin.uuid          | ERROR    |
/// | ExperimentalEncodingApi   | kotlin.io.encoding   | ERROR    |
/// | ExperimentalMultiplatform | kotlin               | ERROR    |
/// | ExperimentalSubclassOptIn | kotlin               | WARNING  |
///
/// See: https://kotlinlang.org/api/latest/jvm/stdlib/
extension DataFlowSemaPhase {
    func registerSyntheticExperimentalMarkerStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinPkg = ensurePackage(
            path: ["kotlin"],
            symbols: symbols,
            interner: interner
        )
        let kotlinPkgSymbol = symbols.lookup(fqName: kotlinPkg) ?? .invalid

        // --- kotlin.ExperimentalUnsignedTypes (ERROR) ---
        registerSyntheticExperimentalMarker(
            named: "ExperimentalUnsignedTypes",
            packageFQName: kotlinPkg,
            packageSymbol: kotlinPkgSymbol,
            severity: "ERROR",
            symbols: symbols,
            interner: interner
        )

        // --- kotlin.ExperimentalMultiplatform (ERROR) ---
        registerSyntheticExperimentalMarker(
            named: "ExperimentalMultiplatform",
            packageFQName: kotlinPkg,
            packageSymbol: kotlinPkgSymbol,
            severity: "ERROR",
            symbols: symbols,
            interner: interner
        )

        // --- kotlin.ExperimentalSubclassOptIn (WARNING) ---
        registerSyntheticExperimentalMarker(
            named: "ExperimentalSubclassOptIn",
            packageFQName: kotlinPkg,
            packageSymbol: kotlinPkgSymbol,
            severity: "WARNING",
            symbols: symbols,
            interner: interner
        )

        // --- kotlin.uuid.ExperimentalUuidApi (ERROR) ---
        let kotlinUuidPkg = ensurePackage(
            path: ["kotlin", "uuid"],
            symbols: symbols,
            interner: interner
        )
        let kotlinUuidPkgSymbol = symbols.lookup(fqName: kotlinUuidPkg) ?? .invalid
        registerSyntheticExperimentalMarker(
            named: "ExperimentalUuidApi",
            packageFQName: kotlinUuidPkg,
            packageSymbol: kotlinUuidPkgSymbol,
            severity: "ERROR",
            symbols: symbols,
            interner: interner
        )

        // --- kotlin.io.encoding.ExperimentalEncodingApi (ERROR) ---
        let kotlinIoEncodingPkg = ensurePackage(
            path: ["kotlin", "io", "encoding"],
            symbols: symbols,
            interner: interner
        )
        let kotlinIoEncodingPkgSymbol = symbols.lookup(fqName: kotlinIoEncodingPkg) ?? .invalid
        registerSyntheticExperimentalMarker(
            named: "ExperimentalEncodingApi",
            packageFQName: kotlinIoEncodingPkg,
            packageSymbol: kotlinIoEncodingPkgSymbol,
            severity: "ERROR",
            symbols: symbols,
            interner: interner
        )
    }

    /// Registers a single experimental opt-in marker annotation class and attaches
    /// `@RequiresOptIn(level = RequiresOptIn.Level.<severity>)` to it so that the
    /// opt-in checker can emit the correct diagnostic severity.
    private func registerSyntheticExperimentalMarker(
        named name: String,
        packageFQName: [InternedString],
        packageSymbol: SymbolID,
        severity: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let className = interner.intern(name)
        let classFQName = packageFQName + [className]

        let classSymbol: SymbolID
        if let existing = symbols.lookup(fqName: classFQName) {
            classSymbol = existing
        } else {
            classSymbol = symbols.define(
                kind: .annotationClass,
                name: className,
                fqName: classFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        if packageSymbol != .invalid {
            symbols.setParentSymbol(packageSymbol, for: classSymbol)
        }

        // Attach @RequiresOptIn with the declared severity level.
        let requiresOptInRecord = MetadataAnnotationRecord(
            annotationFQName: "kotlin.RequiresOptIn",
            arguments: ["level=RequiresOptIn.Level.\(severity)"]
        )
        // Attach @Target(ANNOTATION_CLASS) so the compiler treats it as a
        // well-formed opt-in marker.
        let targetRecord = MetadataAnnotationRecord(
            annotationFQName: "kotlin.annotation.Target",
            arguments: ["AnnotationTarget.ANNOTATION_CLASS"]
        )
        // Attach @Retention(BINARY) matching Kotlin stdlib declarations.
        let retentionRecord = MetadataAnnotationRecord(
            annotationFQName: "kotlin.annotation.Retention",
            arguments: ["AnnotationRetention.BINARY"]
        )

        var annotations = symbols.annotations(for: classSymbol)
        for record in [requiresOptInRecord, targetRecord, retentionRecord] {
            if !annotations.contains(record) {
                annotations.append(record)
            }
        }
        symbols.setAnnotations(annotations, for: classSymbol)
    }
}
