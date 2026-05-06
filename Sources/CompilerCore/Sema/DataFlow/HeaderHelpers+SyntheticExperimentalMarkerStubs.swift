import Foundation

/// Synthetic stubs for Kotlin stdlib experimental opt-in markers discovered
/// missing in STDLIB-EXPERIMENTAL-ABI-001.
///
/// Each marker is an annotation class annotated with `@RequiresOptIn` at the declared
/// severity level from the Kotlin stdlib source:
///
/// | Annotation                | Package              | Severity |
/// |---------------------------|----------------------|----------|
/// | ExperimentalUnsignedTypes | kotlin               | ERROR    |
/// | ExperimentalVersionOverloading | kotlin          | ERROR    |
/// | ExperimentalContextParameters | kotlin           | ERROR    |
/// | ExperimentalUuidApi       | kotlin.uuid          | ERROR    |
/// | ExperimentalEncodingApi   | kotlin.io.encoding   | ERROR    |
/// | ExperimentalWasmInterop   | kotlin.wasm          | WARNING  |
/// | ExperimentalMultiplatform | kotlin               | ERROR    |
/// | ExperimentalSubclassOptIn | kotlin               | WARNING  |
/// | ExperimentalAssociatedObjects | kotlin.reflect    | ERROR    |
/// | ExperimentalJsFileName    | kotlin.js            | WARNING  |
/// | ExpectRefinement          | kotlin.experimental  | @ExperimentalMultiplatform |
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

        // --- kotlin.ExperimentalVersionOverloading (ERROR) ---
        registerSyntheticExperimentalMarker(
            named: "ExperimentalVersionOverloading",
            packageFQName: kotlinPkg,
            packageSymbol: kotlinPkgSymbol,
            severity: "ERROR",
            symbols: symbols,
            interner: interner
        )

        // --- kotlin.ExperimentalContextParameters (ERROR) ---
        registerSyntheticExperimentalMarker(
            named: "ExperimentalContextParameters",
            packageFQName: kotlinPkg,
            packageSymbol: kotlinPkgSymbol,
            severity: "ERROR",
            message: "The API is related to the experimental feature \"context parameters\" (see KEEP-367) and may be changed or removed in any future release.",
            targetArguments: nil,
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

        // --- kotlin.js.ExperimentalJsFileName (WARNING) ---
        let kotlinJsPkg = ensurePackage(
            path: ["kotlin", "js"],
            symbols: symbols,
            interner: interner
        )
        let kotlinJsPkgSymbol = symbols.lookup(fqName: kotlinJsPkg) ?? .invalid
        registerSyntheticExperimentalMarker(
            named: "ExperimentalJsFileName",
            packageFQName: kotlinJsPkg,
            packageSymbol: kotlinJsPkgSymbol,
            severity: "WARNING",
            targetArguments: nil,
            symbols: symbols,
            interner: interner
        )

        // --- kotlin.reflect.ExperimentalAssociatedObjects (ERROR) ---
        let kotlinReflectPkg = ensurePackage(
            path: ["kotlin", "reflect"],
            symbols: symbols,
            interner: interner
        )
        let kotlinReflectPkgSymbol = symbols.lookup(fqName: kotlinReflectPkg) ?? .invalid
        registerSyntheticExperimentalMarker(
            named: "ExperimentalAssociatedObjects",
            packageFQName: kotlinReflectPkg,
            packageSymbol: kotlinReflectPkgSymbol,
            severity: "ERROR",
            targetArguments: nil,
            symbols: symbols,
            interner: interner
        )

        // --- kotlin.wasm.ExperimentalWasmInterop (WARNING) ---
        let kotlinWasmPkg = ensurePackage(
            path: ["kotlin", "wasm"],
            symbols: symbols,
            interner: interner
        )
        let kotlinWasmPkgSymbol = symbols.lookup(fqName: kotlinWasmPkg) ?? .invalid
        registerSyntheticExperimentalMarker(
            named: "ExperimentalWasmInterop",
            packageFQName: kotlinWasmPkg,
            packageSymbol: kotlinWasmPkgSymbol,
            severity: "WARNING",
            targetArguments: nil,
            symbols: symbols,
            interner: interner
        )

        // --- kotlin.experimental.ExpectRefinement ---
        let kotlinExperimentalPkg = ensurePackage(
            path: ["kotlin", "experimental"],
            symbols: symbols,
            interner: interner
        )
        let kotlinExperimentalPkgSymbol = symbols.lookup(fqName: kotlinExperimentalPkg) ?? .invalid
        registerSyntheticExpectRefinementAnnotation(
            packageFQName: kotlinExperimentalPkg,
            packageSymbol: kotlinExperimentalPkgSymbol,
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
        message: String? = nil,
        targetArguments: [String]? = ["AnnotationTarget.ANNOTATION_CLASS"],
        retentionArgument: String? = "AnnotationRetention.BINARY",
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
        var requiresOptInArguments = ["level=RequiresOptIn.Level.\(severity)"]
        if let message {
            requiresOptInArguments.insert("message=\(message)", at: 0)
        }
        let requiresOptInRecord = MetadataAnnotationRecord(
            annotationFQName: "kotlin.RequiresOptIn",
            arguments: requiresOptInArguments
        )
        var annotations = symbols.annotations(for: classSymbol)
        if !annotations.contains(requiresOptInRecord) {
            annotations.append(requiresOptInRecord)
        }
        if let targetArguments {
            let targetRecord = MetadataAnnotationRecord(
                annotationFQName: "kotlin.annotation.Target",
                arguments: targetArguments
            )
            if !annotations.contains(targetRecord) {
                annotations.append(targetRecord)
            }
        }
        if let retentionArgument {
            let retentionRecord = MetadataAnnotationRecord(
                annotationFQName: "kotlin.annotation.Retention",
                arguments: [retentionArgument]
            )
            if !annotations.contains(retentionRecord) {
                annotations.append(retentionRecord)
            }
        }
        symbols.setAnnotations(annotations, for: classSymbol)
    }

    private func registerSyntheticExpectRefinementAnnotation(
        packageFQName: [InternedString],
        packageSymbol: SymbolID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let className = interner.intern("ExpectRefinement")
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

        let metadata = [
            MetadataAnnotationRecord(
                annotationFQName: "kotlin.annotation.Target",
                arguments: ["AnnotationTarget.CLASS"]
            ),
            MetadataAnnotationRecord(annotationFQName: "kotlin.ExperimentalMultiplatform"),
        ]

        var annotations = symbols.annotations(for: classSymbol)
        var didAppend = false
        for record in metadata where !annotations.contains(record) {
            annotations.append(record)
            didAppend = true
        }
        if didAppend {
            symbols.setAnnotations(annotations, for: classSymbol)
        }
    }
}
