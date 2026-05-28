import Foundation

/// Synthetic stubs for kotlin.io filesystem exception types.
///
/// Covers:
/// - STDLIB-IO-TYPE-001: `kotlin.io.AccessDeniedException` class
/// - STDLIB-IO-TYPE-002: `kotlin.io.FileAlreadyExistsException` class
/// - STDLIB-IO-TYPE-003: `kotlin.io.FileSystemException` class
///
/// The exception classes are registered as subclasses of `kotlin.Exception`
/// so that `try/catch` and `throw` sites can be type-checked. Constructors
/// mirror the Kotlin stdlib shape `(file: File, other: File? = null, reason: String? = null)`
/// and route through the shared `kk_throwable_new` runtime entry point so no
/// dedicated runtime hook is required.
///
/// `FileSystemException` is the abstract base class for filesystem-related
/// exceptions in `kotlin.io`. `FileAlreadyExistsException` inherits from it.
///
/// This stub must run after `registerSyntheticFileIOStubs` (which defines
/// `java.io.File`) and after `registerSyntheticExceptionStubs` (which defines
/// `kotlin.Exception`).
extension DataFlowSemaPhase {
    func registerSyntheticKotlinIOExceptionStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinIOPkg = ensurePackage(
            path: ["kotlin", "io"],
            symbols: symbols,
            interner: interner
        )
        let kotlinIOPkgSymbol = symbols.lookup(fqName: kotlinIOPkg)

        let kotlinPkg: [InternedString] = [interner.intern("kotlin")]
        guard let exceptionSymbol = symbols.lookup(fqName: kotlinPkg + [interner.intern("Exception")]) else {
            // Exception is registered by registerSyntheticExceptionStubs; if it is missing the
            // synthetic stub pipeline is in an unexpected state and we simply skip registration.
            return
        }

        let fileFQName: [InternedString] = [
            interner.intern("java"),
            interner.intern("io"),
            interner.intern("File"),
        ]
        guard let fileSymbol = symbols.lookup(fqName: fileFQName) else {
            // java.io.File is registered by registerSyntheticFileIOStubs; bail out if it has not
            // been defined yet so that we don't fabricate an incomplete symbol table entry.
            return
        }
        let fileType = types.make(.classType(ClassType(
            classSymbol: fileSymbol, args: [], nullability: .nonNull
        )))
        let nullableFileType = types.make(.classType(ClassType(
            classSymbol: fileSymbol, args: [], nullability: .nullable
        )))
        let nullableStringType = types.makeNullable(types.stringType)

        // MARK: - STDLIB-IO-TYPE-003: FileSystemException

        let fileSystemExceptionSymbol = ensureClassSymbol(
            named: "FileSystemException",
            in: kotlinIOPkg,
            symbols: symbols,
            interner: interner
        )
        if let kotlinIOPkgSymbol {
            symbols.setParentSymbol(kotlinIOPkgSymbol, for: fileSystemExceptionSymbol)
        }

        // FileSystemException extends Exception (we model IOException → Exception for simplicity).
        symbols.setDirectSupertypes([exceptionSymbol], for: fileSystemExceptionSymbol)
        types.setNominalDirectSupertypes([exceptionSymbol], for: fileSystemExceptionSymbol)

        let fileSystemExceptionType = types.make(.classType(ClassType(
            classSymbol: fileSystemExceptionSymbol, args: [], nullability: .nonNull
        )))
        symbols.setPropertyType(fileSystemExceptionType, for: fileSystemExceptionSymbol)

        // Mirror the Kotlin stdlib constructor shape:
        //   FileSystemException(file: File)
        //   FileSystemException(file: File, other: File?)
        //   FileSystemException(file: File, other: File?, reason: String?)
        let fileSystemExceptionOverloads: [[(name: String, type: TypeID)]] = [
            [("file", fileType)],
            [("file", fileType), ("other", nullableFileType)],
            [("file", fileType), ("other", nullableFileType), ("reason", nullableStringType)],
        ]
        for parameters in fileSystemExceptionOverloads {
            registerSyntheticExceptionConstructor(
                ownerSymbol: fileSystemExceptionSymbol,
                ownerType: fileSystemExceptionType,
                parameters: parameters,
                externalLinkName: "kk_throwable_new",
                symbols: symbols,
                interner: interner
            )
        }

        // STDLIB-IO-TYPE-001: AccessDeniedException
        // Inherits from Exception directly (FileSystemException is tracked separately
        // under STDLIB-IO-TYPE-003).
        let accessDeniedSymbol = ensureClassSymbol(
            named: "AccessDeniedException",
            in: kotlinIOPkg,
            symbols: symbols,
            interner: interner
        )
        if let kotlinIOPkgSymbol {
            symbols.setParentSymbol(kotlinIOPkgSymbol, for: accessDeniedSymbol)
        }
        symbols.setDirectSupertypes([exceptionSymbol], for: accessDeniedSymbol)
        types.setNominalDirectSupertypes([exceptionSymbol], for: accessDeniedSymbol)

        let accessDeniedType = types.make(.classType(ClassType(
            classSymbol: accessDeniedSymbol, args: [], nullability: .nonNull
        )))
        symbols.setPropertyType(accessDeniedType, for: accessDeniedSymbol)

        let accessDeniedOverloads: [[(name: String, type: TypeID)]] = [
            [("file", fileType)],
            [("file", fileType), ("other", nullableFileType)],
            [("file", fileType), ("other", nullableFileType), ("reason", nullableStringType)],
        ]
        for parameters in accessDeniedOverloads {
            registerSyntheticExceptionConstructor(
                ownerSymbol: accessDeniedSymbol,
                ownerType: accessDeniedType,
                parameters: parameters,
                externalLinkName: "kk_throwable_new",
                symbols: symbols,
                interner: interner
            )
        }

        // MARK: - STDLIB-IO-TYPE-002: FileAlreadyExistsException


        let fileAlreadyExistsSymbol = ensureClassSymbol(
            named: "FileAlreadyExistsException",
            in: kotlinIOPkg,
            symbols: symbols,
            interner: interner
        )
        if let kotlinIOPkgSymbol {
            symbols.setParentSymbol(kotlinIOPkgSymbol, for: fileAlreadyExistsSymbol)
        }

        // FileAlreadyExistsException extends FileSystemException (corrected from
        // the placeholder Exception supertype now that FileSystemException exists).
        symbols.setDirectSupertypes([fileSystemExceptionSymbol], for: fileAlreadyExistsSymbol)
        types.setNominalDirectSupertypes([fileSystemExceptionSymbol], for: fileAlreadyExistsSymbol)

        let fileAlreadyExistsType = types.make(.classType(ClassType(
            classSymbol: fileAlreadyExistsSymbol, args: [], nullability: .nonNull
        )))
        symbols.setPropertyType(fileAlreadyExistsType, for: fileAlreadyExistsSymbol)

        // Mirror the Kotlin stdlib constructor shape. All overloads route through
        // `kk_throwable_new` (which expects a single message argument) — the
        // surrounding compiler call lowering is responsible for synthesising the
        // descriptive message before passing it down.
        let fileAlreadyExistsOverloads: [[(name: String, type: TypeID)]] = [
            [("file", fileType)],
            [("file", fileType), ("other", nullableFileType)],
            [("file", fileType), ("other", nullableFileType), ("reason", nullableStringType)],
        ]
        for parameters in fileAlreadyExistsOverloads {
            registerSyntheticExceptionConstructor(
                ownerSymbol: fileAlreadyExistsSymbol,
                ownerType: fileAlreadyExistsType,
                parameters: parameters,
                externalLinkName: "kk_throwable_new",
                symbols: symbols,
                interner: interner
            )
        }
    }
}
