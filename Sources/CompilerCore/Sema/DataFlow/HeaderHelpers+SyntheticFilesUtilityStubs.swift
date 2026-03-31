/// Synthetic stubs for java.nio.file.Files utility class (STDLIB-IO-090).
///
/// Covers:
/// - File operations: `createFile()`, `delete()`, `copy()`, `move()`
/// - Directory operations: `createDirectory()`, `createDirectories()`
/// - File attributes: `size()`, `lastModifiedTime()`, `isRegularFile()`, `isDirectory()`, `exists()`
/// - File search: `walk()`, `list()`, `newDirectoryStream()`
/// - Temporary files: `createTempFile()`, `createTempDirectory()`
///
/// `Files` is modelled as a Kotlin `object` (singleton) whose methods are
/// dispatched to `kk_files_*` runtime entry points.  The Path type is
/// resolved from the existing kotlin.io.path.Path symbol registered by
/// `registerSyntheticPathStubs`.
extension DataFlowSemaPhase {
    func registerSyntheticFilesUtilityStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        // java.nio.file package hierarchy
        let javaNIOFilePkg = ensureJavaNIOFilePackage(symbols: symbols, interner: interner)
        let javaNIOFilePkgSymbol = symbols.lookup(fqName: javaNIOFilePkg)

        // Files object symbol
        let filesSymbol = ensureFilesObjectSymbol(
            in: javaNIOFilePkg,
            pkgSymbol: javaNIOFilePkgSymbol,
            symbols: symbols,
            interner: interner
        )
        let filesType = types.make(.classType(ClassType(
            classSymbol: filesSymbol, args: [], nullability: .nonNull
        )))
        symbols.setPropertyType(filesType, for: filesSymbol)

        // Resolve Path type from kotlin.io.path.Path
        let pathSymbol = resolveFilesPathSymbol(symbols: symbols, interner: interner)
        guard let pathSym = pathSymbol else {
            // Path stubs not yet registered; bail out — will be retried on next pass
            return
        }
        let pathType = types.make(.classType(ClassType(
            classSymbol: pathSym, args: [], nullability: .nonNull
        )))

        // List<Path> type for walk/list/newDirectoryStream return
        let listSymbol = resolveFilesListSymbol(symbols: symbols, interner: interner)
        let listOfPathType: TypeID = if let listSym = listSymbol {
            types.make(.classType(ClassType(
                classSymbol: listSym,
                args: [.out(pathType)],
                nullability: .nonNull
            )))
        } else {
            types.anyType
        }

        // MARK: - File operations

        registerFilesMemberFunction(
            named: "createFile",
            externalLinkName: "kk_files_createFile",
            ownerSymbol: filesSymbol,
            ownerType: filesType,
            parameters: [("path", pathType)],
            returnType: pathType,
            symbols: symbols,
            interner: interner
        )

        registerFilesMemberFunction(
            named: "delete",
            externalLinkName: "kk_files_delete",
            ownerSymbol: filesSymbol,
            ownerType: filesType,
            parameters: [("path", pathType)],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )

        registerFilesMemberFunction(
            named: "copy",
            externalLinkName: "kk_files_copy",
            ownerSymbol: filesSymbol,
            ownerType: filesType,
            parameters: [("source", pathType), ("target", pathType)],
            returnType: pathType,
            symbols: symbols,
            interner: interner
        )

        registerFilesMemberFunction(
            named: "move",
            externalLinkName: "kk_files_move",
            ownerSymbol: filesSymbol,
            ownerType: filesType,
            parameters: [("source", pathType), ("target", pathType)],
            returnType: pathType,
            symbols: symbols,
            interner: interner
        )

        // MARK: - Directory operations

        registerFilesMemberFunction(
            named: "createDirectory",
            externalLinkName: "kk_files_createDirectory",
            ownerSymbol: filesSymbol,
            ownerType: filesType,
            parameters: [("path", pathType)],
            returnType: pathType,
            symbols: symbols,
            interner: interner
        )

        registerFilesMemberFunction(
            named: "createDirectories",
            externalLinkName: "kk_files_createDirectories",
            ownerSymbol: filesSymbol,
            ownerType: filesType,
            parameters: [("path", pathType)],
            returnType: pathType,
            symbols: symbols,
            interner: interner
        )

        // MARK: - File attributes

        registerFilesMemberFunction(
            named: "size",
            externalLinkName: "kk_files_size",
            ownerSymbol: filesSymbol,
            ownerType: filesType,
            parameters: [("path", pathType)],
            returnType: types.longType,
            symbols: symbols,
            interner: interner
        )

        registerFilesMemberFunction(
            named: "lastModifiedTime",
            externalLinkName: "kk_files_lastModifiedTime",
            ownerSymbol: filesSymbol,
            ownerType: filesType,
            parameters: [("path", pathType)],
            returnType: types.longType,
            symbols: symbols,
            interner: interner
        )

        registerFilesMemberFunction(
            named: "isRegularFile",
            externalLinkName: "kk_files_isRegularFile",
            ownerSymbol: filesSymbol,
            ownerType: filesType,
            parameters: [("path", pathType)],
            returnType: types.booleanType,
            symbols: symbols,
            interner: interner
        )

        registerFilesMemberFunction(
            named: "isDirectory",
            externalLinkName: "kk_files_isDirectory",
            ownerSymbol: filesSymbol,
            ownerType: filesType,
            parameters: [("path", pathType)],
            returnType: types.booleanType,
            symbols: symbols,
            interner: interner
        )

        registerFilesMemberFunction(
            named: "exists",
            externalLinkName: "kk_files_exists",
            ownerSymbol: filesSymbol,
            ownerType: filesType,
            parameters: [("path", pathType)],
            returnType: types.booleanType,
            symbols: symbols,
            interner: interner
        )

        // MARK: - File search

        registerFilesMemberFunction(
            named: "walk",
            externalLinkName: "kk_files_walk",
            ownerSymbol: filesSymbol,
            ownerType: filesType,
            parameters: [("start", pathType)],
            returnType: listOfPathType,
            symbols: symbols,
            interner: interner
        )

        registerFilesMemberFunction(
            named: "list",
            externalLinkName: "kk_files_list",
            ownerSymbol: filesSymbol,
            ownerType: filesType,
            parameters: [("dir", pathType)],
            returnType: listOfPathType,
            symbols: symbols,
            interner: interner
        )

        registerFilesMemberFunction(
            named: "newDirectoryStream",
            externalLinkName: "kk_files_newDirectoryStream",
            ownerSymbol: filesSymbol,
            ownerType: filesType,
            parameters: [("dir", pathType)],
            returnType: listOfPathType,
            symbols: symbols,
            interner: interner
        )

        // MARK: - Temporary files

        registerFilesMemberFunction(
            named: "createTempFile",
            externalLinkName: "kk_files_createTempFile",
            ownerSymbol: filesSymbol,
            ownerType: filesType,
            parameters: [("prefix", types.stringType), ("suffix", types.stringType)],
            returnType: pathType,
            symbols: symbols,
            interner: interner
        )

        registerFilesMemberFunction(
            named: "createTempDirectory",
            externalLinkName: "kk_files_createTempDirectory",
            ownerSymbol: filesSymbol,
            ownerType: filesType,
            parameters: [("prefix", types.stringType)],
            returnType: pathType,
            symbols: symbols,
            interner: interner
        )
    }

    // MARK: - Private Helpers

    private func ensureJavaNIOFilePackage(
        symbols: SymbolTable,
        interner: StringInterner
    ) -> [InternedString] {
        return ensurePackage(
            path: ["java", "nio", "file"],
            symbols: symbols,
            interner: interner
        )
    }

    private func ensureFilesObjectSymbol(
        in pkg: [InternedString],
        pkgSymbol: SymbolID?,
        symbols: SymbolTable,
        interner: StringInterner
    ) -> SymbolID {
        let filesName = interner.intern("Files")
        let filesFQName = pkg + [filesName]
        if let existing = symbols.lookup(fqName: filesFQName) {
            return existing
        }
        let filesSymbol = symbols.define(
            kind: .object,
            name: filesName,
            fqName: filesFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .static]
        )
        if let pkgSym = pkgSymbol {
            symbols.setParentSymbol(pkgSym, for: filesSymbol)
        }
        return filesSymbol
    }

    private func resolveFilesPathSymbol(
        symbols: SymbolTable,
        interner: StringInterner
    ) -> SymbolID? {
        let pathFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("io"),
            interner.intern("path"),
            interner.intern("Path"),
        ]
        return symbols.lookup(fqName: pathFQName)
    }

    private func resolveFilesListSymbol(
        symbols: SymbolTable,
        interner: StringInterner
    ) -> SymbolID? {
        let listFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("List"),
        ]
        return symbols.lookup(fqName: listFQName)
    }

    private func registerFilesMemberFunction(
        named name: String,
        externalLinkName: String,
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        parameters: [(name: String, type: TypeID)],
        returnType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let functionName = interner.intern(name)
        let functionFQName = ownerInfo.fqName + [functionName]
        // Check for duplicate registration with same parameter types
        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let existingSignature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return existingSignature.parameterTypes == parameters.map(\.type)
        }) {
            guard let existingInfo = symbols.symbol(existing),
                  existingInfo.flags.contains(.synthetic) || existingInfo.declSite == nil else {
                return
            }
            symbols.setExternalLinkName(externalLinkName, for: existing)
            return
        }

        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: functionSymbol)
        symbols.setExternalLinkName(externalLinkName, for: functionSymbol)

        var parameterTypes: [TypeID] = []
        var parameterSymbols: [SymbolID] = []

        for parameter in parameters {
            let parameterName = interner.intern(parameter.name)
            let parameterSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: functionFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(functionSymbol, for: parameterSymbol)
            parameterTypes.append(parameter.type)
            parameterSymbols.append(parameterSymbol)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: ownerType,
                parameterTypes: parameterTypes,
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: parameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: parameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: parameterSymbols.count)
            ),
            for: functionSymbol
        )
    }
}
