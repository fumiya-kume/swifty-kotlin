/// Synthetic stubs for kotlin.io filesystem exception types.
///
/// Covers:
/// - STDLIB-IO-TYPE-001: `kotlin.io.AccessDeniedException` class surface
///
/// `AccessDeniedException` inherits from `FileSystemException`, which in turn
/// inherits from `kotlin.Exception` (Kotlin's stdlib aliases this through
/// `IOException`, but in our minimal type lattice we treat the parent chain
/// rooted at `Exception` so name resolution and subtype checks succeed without
/// requiring a full java.io runtime). Each stub registers the class, its
/// primary constructor overloads (`(File)`, `(File, File?)`,
/// `(File, File?, String?)`), and member properties (`file`, `other`,
/// `reason`) so that Kotlin source referencing these types type-checks.
import Foundation

extension DataFlowSemaPhase {
    func registerSyntheticIOExceptionStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        // Resolve required base symbols. We depend on registerSyntheticExceptionStubs
        // (for Exception) and registerSyntheticFileIOStubs (for java.io.File) being
        // executed prior to this call.
        let kotlinPkg: [InternedString] = [interner.intern("kotlin")]
        let exceptionFQName = kotlinPkg + [interner.intern("Exception")]
        guard let exceptionSymbol = symbols.lookup(fqName: exceptionFQName) else {
            return
        }

        let javaIOPkg: [InternedString] = [interner.intern("java"), interner.intern("io")]
        guard let fileSymbol = symbols.lookup(fqName: javaIOPkg + [interner.intern("File")]) else {
            return
        }
        let fileType = types.make(.classType(ClassType(
            classSymbol: fileSymbol, args: [], nullability: .nonNull
        )))
        let nullableFileType = types.make(.classType(ClassType(
            classSymbol: fileSymbol, args: [], nullability: .nullable
        )))
        let nullableStringType = types.makeNullable(types.stringType)

        let kotlinIoPkg = ensurePackage(
            path: ["kotlin", "io"],
            symbols: symbols,
            interner: interner
        )
        let kotlinIoPkgSymbol = symbols.lookup(fqName: kotlinIoPkg)

        // FileSystemException acts as the parent class. It is required by
        // Kotlin's documented hierarchy, so we always register it alongside
        // AccessDeniedException.
        let fileSystemExceptionSymbol = ensureClassSymbol(
            named: "FileSystemException",
            in: kotlinIoPkg,
            symbols: symbols,
            interner: interner
        )
        if let kotlinIoPkgSymbol {
            symbols.setParentSymbol(kotlinIoPkgSymbol, for: fileSystemExceptionSymbol)
        }
        symbols.setDirectSupertypes([exceptionSymbol], for: fileSystemExceptionSymbol)
        types.setNominalDirectSupertypes([exceptionSymbol], for: fileSystemExceptionSymbol)
        let fileSystemExceptionType = types.make(.classType(ClassType(
            classSymbol: fileSystemExceptionSymbol, args: [], nullability: .nonNull
        )))
        symbols.setPropertyType(fileSystemExceptionType, for: fileSystemExceptionSymbol)

        registerIOExceptionConstructorOverloads(
            ownerSymbol: fileSystemExceptionSymbol,
            ownerType: fileSystemExceptionType,
            fileType: fileType,
            nullableFileType: nullableFileType,
            nullableStringType: nullableStringType,
            externalLinkPrefix: "kk_file_system_exception",
            symbols: symbols,
            interner: interner
        )
        registerIOExceptionMemberProperties(
            ownerSymbol: fileSystemExceptionSymbol,
            ownerType: fileSystemExceptionType,
            fileType: fileType,
            nullableFileType: nullableFileType,
            nullableStringType: nullableStringType,
            externalLinkPrefix: "kk_file_system_exception",
            symbols: symbols,
            interner: interner
        )

        // AccessDeniedException — STDLIB-IO-TYPE-001
        let accessDeniedSymbol = ensureClassSymbol(
            named: "AccessDeniedException",
            in: kotlinIoPkg,
            symbols: symbols,
            interner: interner
        )
        if let kotlinIoPkgSymbol {
            symbols.setParentSymbol(kotlinIoPkgSymbol, for: accessDeniedSymbol)
        }
        symbols.setDirectSupertypes([fileSystemExceptionSymbol], for: accessDeniedSymbol)
        types.setNominalDirectSupertypes([fileSystemExceptionSymbol], for: accessDeniedSymbol)
        let accessDeniedType = types.make(.classType(ClassType(
            classSymbol: accessDeniedSymbol, args: [], nullability: .nonNull
        )))
        symbols.setPropertyType(accessDeniedType, for: accessDeniedSymbol)

        registerIOExceptionConstructorOverloads(
            ownerSymbol: accessDeniedSymbol,
            ownerType: accessDeniedType,
            fileType: fileType,
            nullableFileType: nullableFileType,
            nullableStringType: nullableStringType,
            externalLinkPrefix: "kk_access_denied_exception",
            symbols: symbols,
            interner: interner
        )
        registerIOExceptionMemberProperties(
            ownerSymbol: accessDeniedSymbol,
            ownerType: accessDeniedType,
            fileType: fileType,
            nullableFileType: nullableFileType,
            nullableStringType: nullableStringType,
            externalLinkPrefix: "kk_access_denied_exception",
            symbols: symbols,
            interner: interner
        )
    }

    private func registerIOExceptionConstructorOverloads(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        fileType: TypeID,
        nullableFileType: TypeID,
        nullableStringType: TypeID,
        externalLinkPrefix: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let overloads: [(parameters: [(name: String, type: TypeID)], link: String)] = [
            (
                [("file", fileType)],
                "\(externalLinkPrefix)_new_file"
            ),
            (
                [("file", fileType), ("other", nullableFileType)],
                "\(externalLinkPrefix)_new_file_other"
            ),
            (
                [
                    ("file", fileType),
                    ("other", nullableFileType),
                    ("reason", nullableStringType),
                ],
                "\(externalLinkPrefix)_new_file_other_reason"
            ),
        ]
        for overload in overloads {
            registerSyntheticExceptionConstructor(
                ownerSymbol: ownerSymbol,
                ownerType: ownerType,
                parameters: overload.parameters,
                externalLinkName: overload.link,
                symbols: symbols,
                interner: interner
            )
        }
    }

    private func registerIOExceptionMemberProperties(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        fileType: TypeID,
        nullableFileType: TypeID,
        nullableStringType: TypeID,
        externalLinkPrefix: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        registerIOExceptionMemberProperty(
            ownerSymbol: ownerSymbol,
            propertyName: "file",
            propertyType: fileType,
            externalLinkName: "\(externalLinkPrefix)_file",
            symbols: symbols,
            interner: interner
        )
        registerIOExceptionMemberProperty(
            ownerSymbol: ownerSymbol,
            propertyName: "other",
            propertyType: nullableFileType,
            externalLinkName: "\(externalLinkPrefix)_other",
            symbols: symbols,
            interner: interner
        )
        registerIOExceptionMemberProperty(
            ownerSymbol: ownerSymbol,
            propertyName: "reason",
            propertyType: nullableStringType,
            externalLinkName: "\(externalLinkPrefix)_reason",
            symbols: symbols,
            interner: interner
        )
    }

    private func registerIOExceptionMemberProperty(
        ownerSymbol: SymbolID,
        propertyName: String,
        propertyType: TypeID,
        externalLinkName: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let internedName = interner.intern(propertyName)
        let propFQName = ownerInfo.fqName + [internedName]
        if symbols.lookupAll(fqName: propFQName).contains(where: { id in
            symbols.symbol(id)?.kind == .property
        }) {
            return
        }
        let propSymbol = symbols.define(
            kind: .property,
            name: internedName,
            fqName: propFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: propSymbol)
        symbols.setPropertyType(propertyType, for: propSymbol)
        symbols.setExternalLinkName(externalLinkName, for: propSymbol)
    }
}
