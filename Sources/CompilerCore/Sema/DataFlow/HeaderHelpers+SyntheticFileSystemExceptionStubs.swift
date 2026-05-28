import Foundation

/// STDLIB-IO-TYPE-003: Synthetic `kotlin.io.FileSystemException` class surface.
///
/// `FileSystemException` is the base class in the `kotlin.io` package for
/// the file-system exception hierarchy returned by `File.copyTo`,
/// `File.copyRecursively`, and friends. The Kotlin signature is:
///
///     open class FileSystemException(
///         val file: File,
///         val other: File? = null,
///         val reason: String? = null,
///     ) : IOException(...)
///
/// Because the runtime currently surfaces these conditions as plain
/// `IOException`-flavoured throwables (see `Sources/Runtime/RuntimeFileIO.swift`),
/// the stub wires the class through Sema so that user code such as
/// `try { ... } catch (e: FileSystemException) { ... }` and constructor
/// invocations (`throw FileSystemException(file)`) type-check and bind to
/// the existing `kk_throwable_new*` runtime entries.
///
/// The class is registered as a synthetic subclass of `kotlin.Exception` and
/// exposes its three public read-only properties so member accesses such as
/// `e.file`, `e.other`, and `e.reason` resolve through the symbol table.
extension DataFlowSemaPhase {
    func registerSyntheticFileSystemExceptionStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        // kotlin.io package is created by Closeable stubs; ensure it exists for
        // standalone test orderings as well.
        let kotlinPkg: [InternedString] = [interner.intern("kotlin")]
        if symbols.lookup(fqName: kotlinPkg) == nil {
            _ = symbols.define(
                kind: .package,
                name: interner.intern("kotlin"),
                fqName: kotlinPkg,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        let kotlinIOPkg: [InternedString] = kotlinPkg + [interner.intern("io")]
        if symbols.lookup(fqName: kotlinIOPkg) == nil {
            _ = symbols.define(
                kind: .package,
                name: interner.intern("io"),
                fqName: kotlinIOPkg,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }

        // FileSystemException class symbol.
        let fileSystemExceptionSymbol = ensureClassSymbol(
            named: "FileSystemException",
            in: kotlinIOPkg,
            symbols: symbols,
            interner: interner
        )
        if let pkgSymbol = symbols.lookup(fqName: kotlinIOPkg) {
            symbols.setParentSymbol(pkgSymbol, for: fileSystemExceptionSymbol)
        }

        let fileSystemExceptionType = types.make(.classType(ClassType(
            classSymbol: fileSystemExceptionSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(fileSystemExceptionType, for: fileSystemExceptionSymbol)

        // Wire up the supertype chain (FileSystemException : Exception : Throwable).
        // Concrete IOException is not modelled as a Sema symbol yet; pinning the
        // synthetic class directly under Exception keeps subtype checks
        // (`catch (e: Exception)`) working without introducing a duplicate
        // IOException stub.
        let exceptionFQName = kotlinPkg + [interner.intern("Exception")]
        if let exceptionSymbol = symbols.lookup(fqName: exceptionFQName) {
            symbols.setDirectSupertypes([exceptionSymbol], for: fileSystemExceptionSymbol)
            types.setNominalDirectSupertypes([exceptionSymbol], for: fileSystemExceptionSymbol)
        }

        // File parameter / property types come from java.io.File registered by
        // the FileIO stubs. Look it up rather than re-defining.
        let fileFQName: [InternedString] = [
            interner.intern("java"),
            interner.intern("io"),
            interner.intern("File"),
        ]
        guard let fileSymbol = symbols.lookup(fqName: fileFQName) else {
            // FileIO stubs not yet registered; we cannot finish wiring the
            // constructors without the File type. The class itself is in
            // place, so user code that only catches the type still works.
            return
        }
        let fileType = types.make(.classType(ClassType(
            classSymbol: fileSymbol,
            args: [],
            nullability: .nonNull
        )))
        let nullableFileType = types.makeNullable(fileType)
        let nullableStringType = types.makeNullable(types.stringType)

        // Constructors:
        //   FileSystemException(file)
        //   FileSystemException(file, other)
        //   FileSystemException(file, other, reason)
        let constructorOverloads: [(parameters: [(name: String, type: TypeID)], link: String)] = [
            (
                [("file", fileType)],
                "kk_throwable_new"
            ),
            (
                [("file", fileType), ("other", nullableFileType)],
                "kk_throwable_new"
            ),
            (
                [("file", fileType), ("other", nullableFileType), ("reason", nullableStringType)],
                "kk_throwable_new"
            ),
        ]
        for overload in constructorOverloads {
            registerSyntheticExceptionConstructor(
                ownerSymbol: fileSystemExceptionSymbol,
                ownerType: fileSystemExceptionType,
                parameters: overload.parameters,
                externalLinkName: overload.link,
                symbols: symbols,
                interner: interner
            )
        }

        // Read-only public properties: file: File, other: File?, reason: String?
        registerFileSystemExceptionProperty(
            named: "file",
            propertyType: fileType,
            externalLinkName: "kk_filesystem_exception_file",
            ownerSymbol: fileSystemExceptionSymbol,
            ownerType: fileSystemExceptionType,
            symbols: symbols,
            interner: interner
        )
        registerFileSystemExceptionProperty(
            named: "other",
            propertyType: nullableFileType,
            externalLinkName: "kk_filesystem_exception_other",
            ownerSymbol: fileSystemExceptionSymbol,
            ownerType: fileSystemExceptionType,
            symbols: symbols,
            interner: interner
        )
        registerFileSystemExceptionProperty(
            named: "reason",
            propertyType: nullableStringType,
            externalLinkName: "kk_filesystem_exception_reason",
            ownerSymbol: fileSystemExceptionSymbol,
            ownerType: fileSystemExceptionType,
            symbols: symbols,
            interner: interner
        )
    }

    private func registerFileSystemExceptionProperty(
        named name: String,
        propertyType: TypeID,
        externalLinkName: String,
        ownerSymbol: SymbolID,
        ownerType _: TypeID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let propertyName = interner.intern(name)
        let propertyFQName = ownerInfo.fqName + [propertyName]
        if symbols.lookup(fqName: propertyFQName) != nil {
            return
        }
        let propertySymbol = symbols.define(
            kind: .property,
            name: propertyName,
            fqName: propertyFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: propertySymbol)
        symbols.setPropertyType(propertyType, for: propertySymbol)
        symbols.setExternalLinkName(externalLinkName, for: propertySymbol)
    }
}
