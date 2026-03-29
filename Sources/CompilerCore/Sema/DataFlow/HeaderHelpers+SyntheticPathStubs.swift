/// Synthetic stubs for kotlin.io.path.Path type.
///
/// Covers:
/// - `Path(pathString: String)` constructor
/// - `name: String`, `parent: Path?`, `fileName: Path?`, `root: Path?`, `nameCount: Int` properties
/// - `toString(): String`
/// - `resolve(other: String): Path`, `resolve(other: Path): Path`
/// - `relativize(other: Path): Path`, `normalize(): Path`
/// - `startsWith(other: Path): Boolean`, `startsWith(other: String): Boolean`
/// - `endsWith(other: Path): Boolean`, `endsWith(other: String): Boolean`
/// - `exists(): Boolean`, `isDirectory(): Boolean`, `isRegularFile(): Boolean`
/// - `readText(): String`, `writeText(text: String)`, `readLines(): List<String>`
/// - `createDirectories(): Path`, `deleteIfExists(): Boolean`
/// - `listDirectoryEntries(): List<Path>`
/// - `toFile(): File`
///
/// Each stub registers the kotlin.io.path.Path class, its constructor, member
/// properties, and member functions in the symbol table so that name resolution
/// and type checking succeed without requiring a full kotlin.io.path runtime.
extension DataFlowSemaPhase {
    func registerSyntheticPathStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let kotlinIOPathPkg = ensureKotlinIOPathPackage(symbols: symbols, interner: interner)
        let kotlinIOPathPkgSymbol = symbols.lookup(fqName: kotlinIOPathPkg)

        let pathSymbol = ensureClassSymbol(
            named: "Path",
            in: kotlinIOPathPkg,
            symbols: symbols,
            interner: interner
        )
        if let kotlinIOPathPkgSymbol {
            symbols.setParentSymbol(kotlinIOPathPkgSymbol, for: pathSymbol)
        }
        let pathType = types.make(.classType(ClassType(
            classSymbol: pathSymbol, args: [], nullability: .nonNull
        )))
        symbols.setPropertyType(pathType, for: pathSymbol)

        let nullablePathType = types.makeNullable(pathType)

        // List<Path> type for listDirectoryEntries return
        let listSymbol = resolvePathListSymbol(symbols: symbols, interner: interner)
        if listSymbol == nil {
            assertionFailure("kotlin.collections.List symbol not found; Path stubs will use Any as fallback")
        }
        let listOfPathType: TypeID = if let listSym = listSymbol {
            types.make(.classType(ClassType(
                classSymbol: listSym,
                args: [.out(pathType)],
                nullability: .nonNull
            )))
        } else {
            types.anyType
        }

        // List<String> type for readLines return
        let listOfStringType: TypeID = if let listSym = listSymbol {
            types.make(.classType(ClassType(
                classSymbol: listSym,
                args: [.out(types.stringType)],
                nullability: .nonNull
            )))
        } else {
            types.anyType
        }

        // MARK: - Path(pathString: String) constructor

        registerPathConstructor(
            ownerSymbol: pathSymbol,
            ownerType: pathType,
            parameters: [("pathString", types.stringType)],
            externalLinkName: "kk_path_new",
            symbols: symbols,
            interner: interner
        )

        // MARK: - Path properties

        registerPathMemberProperty(
            named: "name",
            externalLinkName: "kk_path_name",
            ownerSymbol: pathSymbol,
            returnType: types.stringType,
            symbols: symbols,
            interner: interner
        )

        registerPathMemberProperty(
            named: "parent",
            externalLinkName: "kk_path_parent",
            ownerSymbol: pathSymbol,
            returnType: nullablePathType,
            symbols: symbols,
            interner: interner
        )

        // MARK: - Path.toString()

        registerPathMemberFunction(
            named: "toString",
            externalLinkName: "kk_path_toString",
            ownerSymbol: pathSymbol,
            ownerType: pathType,
            parameters: [],
            returnType: types.stringType,
            symbols: symbols,
            interner: interner
        )

        // MARK: - Path.resolve(other: String) and Path.resolve(other: Path)

        registerPathMemberFunction(
            named: "resolve",
            externalLinkName: "kk_path_resolve_string",
            ownerSymbol: pathSymbol,
            ownerType: pathType,
            parameters: [("other", types.stringType)],
            returnType: pathType,
            symbols: symbols,
            interner: interner
        )

        registerPathMemberFunction(
            named: "resolve",
            externalLinkName: "kk_path_resolve_path",
            ownerSymbol: pathSymbol,
            ownerType: pathType,
            parameters: [("other", pathType)],
            returnType: pathType,
            symbols: symbols,
            interner: interner
        )

        // MARK: - Path query methods

        registerPathMemberFunction(
            named: "exists",
            externalLinkName: "kk_path_exists",
            ownerSymbol: pathSymbol,
            ownerType: pathType,
            parameters: [],
            returnType: types.booleanType,
            symbols: symbols,
            interner: interner
        )

        registerPathMemberFunction(
            named: "isDirectory",
            externalLinkName: "kk_path_isDirectory",
            ownerSymbol: pathSymbol,
            ownerType: pathType,
            parameters: [],
            returnType: types.booleanType,
            symbols: symbols,
            interner: interner
        )

        registerPathMemberFunction(
            named: "isRegularFile",
            externalLinkName: "kk_path_isRegularFile",
            ownerSymbol: pathSymbol,
            ownerType: pathType,
            parameters: [],
            returnType: types.booleanType,
            symbols: symbols,
            interner: interner
        )

        // MARK: - Path read/write methods

        registerPathMemberFunction(
            named: "readText",
            externalLinkName: "kk_path_readText",
            ownerSymbol: pathSymbol,
            ownerType: pathType,
            parameters: [],
            returnType: types.stringType,
            symbols: symbols,
            interner: interner
        )

        registerPathMemberFunction(
            named: "writeText",
            externalLinkName: "kk_path_writeText",
            ownerSymbol: pathSymbol,
            ownerType: pathType,
            parameters: [("text", types.stringType)],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )

        registerPathMemberFunction(
            named: "readLines",
            externalLinkName: "kk_path_readLines",
            ownerSymbol: pathSymbol,
            ownerType: pathType,
            parameters: [],
            returnType: listOfStringType,
            symbols: symbols,
            interner: interner
        )

        // MARK: - Path filesystem operations

        registerPathMemberFunction(
            named: "createDirectories",
            externalLinkName: "kk_path_createDirectories",
            ownerSymbol: pathSymbol,
            ownerType: pathType,
            parameters: [],
            returnType: pathType,
            symbols: symbols,
            interner: interner
        )

        registerPathMemberFunction(
            named: "deleteIfExists",
            externalLinkName: "kk_path_deleteIfExists",
            ownerSymbol: pathSymbol,
            ownerType: pathType,
            parameters: [],
            returnType: types.booleanType,
            symbols: symbols,
            interner: interner
        )

        registerPathMemberFunction(
            named: "listDirectoryEntries",
            externalLinkName: "kk_path_listDirectoryEntries",
            ownerSymbol: pathSymbol,
            ownerType: pathType,
            parameters: [],
            returnType: listOfPathType,
            symbols: symbols,
            interner: interner
        )

        // MARK: - Path.normalize()

        registerPathMemberFunction(
            named: "normalize",
            externalLinkName: "kk_path_normalize",
            ownerSymbol: pathSymbol,
            ownerType: pathType,
            parameters: [],
            returnType: pathType,
            symbols: symbols,
            interner: interner
        )

        // MARK: - Path.relativize(other: Path)

        registerPathMemberFunction(
            named: "relativize",
            externalLinkName: "kk_path_relativize",
            ownerSymbol: pathSymbol,
            ownerType: pathType,
            parameters: [("other", pathType)],
            returnType: pathType,
            symbols: symbols,
            interner: interner
        )

        // MARK: - Path.fileName property (Path? wrapping last component, null for root paths)

        registerPathMemberProperty(
            named: "fileName",
            externalLinkName: "kk_path_fileName",
            ownerSymbol: pathSymbol,
            returnType: nullablePathType,
            symbols: symbols,
            interner: interner
        )

        // MARK: - Path.root property

        registerPathMemberProperty(
            named: "root",
            externalLinkName: "kk_path_root",
            ownerSymbol: pathSymbol,
            returnType: nullablePathType,
            symbols: symbols,
            interner: interner
        )

        // MARK: - Path.nameCount property

        registerPathMemberProperty(
            named: "nameCount",
            externalLinkName: "kk_path_nameCount",
            ownerSymbol: pathSymbol,
            returnType: types.intType,
            symbols: symbols,
            interner: interner
        )

        // MARK: - Path.startsWith()

        registerPathMemberFunction(
            named: "startsWith",
            externalLinkName: "kk_path_startsWith_path",
            ownerSymbol: pathSymbol,
            ownerType: pathType,
            parameters: [("other", pathType)],
            returnType: types.booleanType,
            symbols: symbols,
            interner: interner
        )

        registerPathMemberFunction(
            named: "startsWith",
            externalLinkName: "kk_path_startsWith_string",
            ownerSymbol: pathSymbol,
            ownerType: pathType,
            parameters: [("other", types.stringType)],
            returnType: types.booleanType,
            symbols: symbols,
            interner: interner
        )

        // MARK: - Path.endsWith()

        registerPathMemberFunction(
            named: "endsWith",
            externalLinkName: "kk_path_endsWith_path",
            ownerSymbol: pathSymbol,
            ownerType: pathType,
            parameters: [("other", pathType)],
            returnType: types.booleanType,
            symbols: symbols,
            interner: interner
        )

        registerPathMemberFunction(
            named: "endsWith",
            externalLinkName: "kk_path_endsWith_string",
            ownerSymbol: pathSymbol,
            ownerType: pathType,
            parameters: [("other", types.stringType)],
            returnType: types.booleanType,
            symbols: symbols,
            interner: interner
        )

        // MARK: - Path.toFile(): File

        let fileType = resolvePathFileType(symbols: symbols, types: types, interner: interner)
        registerPathMemberFunction(
            named: "toFile",
            externalLinkName: "kk_path_toFile",
            ownerSymbol: pathSymbol,
            ownerType: pathType,
            parameters: [],
            returnType: fileType,
            symbols: symbols,
            interner: interner
        )
    }

    // MARK: - Private Helpers

    private func resolvePathListSymbol(
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

    /// Resolves or creates the `java.io.File` type for use as the return type of `Path.toFile()`.
    private func resolvePathFileType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> TypeID {
        let javaPkg: [InternedString] = [interner.intern("java")]
        if symbols.lookup(fqName: javaPkg) == nil {
            _ = symbols.define(
                kind: .package,
                name: interner.intern("java"),
                fqName: javaPkg,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        let javaIOPkg: [InternedString] = javaPkg + [interner.intern("io")]
        if symbols.lookup(fqName: javaIOPkg) == nil {
            _ = symbols.define(
                kind: .package,
                name: interner.intern("io"),
                fqName: javaIOPkg,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        let fileSymbol = ensureClassSymbol(
            named: "File",
            in: javaIOPkg,
            symbols: symbols,
            interner: interner
        )
        return types.make(.classType(ClassType(
            classSymbol: fileSymbol, args: [], nullability: .nonNull
        )))
    }

    private func ensureKotlinIOPathPackage(
        symbols: SymbolTable,
        interner: StringInterner
    ) -> [InternedString] {
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
        let kotlinIOPathPkg: [InternedString] = kotlinIOPkg + [interner.intern("path")]
        if symbols.lookup(fqName: kotlinIOPathPkg) == nil {
            _ = symbols.define(
                kind: .package,
                name: interner.intern("path"),
                fqName: kotlinIOPathPkg,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        return kotlinIOPathPkg
    }

    private func registerPathConstructor(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        parameters: [(name: String, type: TypeID)],
        externalLinkName: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let initName = interner.intern("<init>")
        let ctorFQName = ownerInfo.fqName + [initName]
        let hasMatchingConstructor = symbols.lookupAll(fqName: ctorFQName).contains { symbolID in
            guard let symbol = symbols.symbol(symbolID),
                  symbol.kind == .constructor,
                  let signature = symbols.functionSignature(for: symbolID)
            else {
                return false
            }
            return signature.parameterTypes == parameters.map(\.type)
        }
        guard !hasMatchingConstructor else {
            return
        }

        let ctorSymbol = symbols.define(
            kind: .constructor,
            name: initName,
            fqName: ctorFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: ctorSymbol)
        symbols.setExternalLinkName(externalLinkName, for: ctorSymbol)

        var valueParameterSymbols: [SymbolID] = []
        for parameter in parameters {
            let parameterName = interner.intern(parameter.name)
            let paramSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: ctorFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(ctorSymbol, for: paramSymbol)
            valueParameterSymbols.append(paramSymbol)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: parameters.map(\.type),
                returnType: ownerType,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count)
            ),
            for: ctorSymbol
        )
    }

    private func registerPathMemberFunction(
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
        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let existingSignature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return existingSignature.receiverType == ownerType
                && existingSignature.parameterTypes == parameters.map(\.type)
        }) {
            guard let existingInfo = symbols.symbol(existing),
                  existingInfo.flags.contains(.synthetic) || existingInfo.declSite == nil else {
                return
            }
            symbols.setExternalLinkName(externalLinkName, for: existing)
            if let existingSignature = symbols.functionSignature(for: existing),
               existingSignature.returnType != returnType {
                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: existingSignature.receiverType,
                        parameterTypes: existingSignature.parameterTypes,
                        returnType: returnType,
                        isSuspend: existingSignature.isSuspend,
                        valueParameterSymbols: existingSignature.valueParameterSymbols,
                        valueParameterHasDefaultValues: existingSignature.valueParameterHasDefaultValues,
                        valueParameterIsVararg: existingSignature.valueParameterIsVararg
                    ),
                    for: existing
                )
            }
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

    private func registerPathMemberProperty(
        named name: String,
        externalLinkName: String,
        ownerSymbol: SymbolID,
        returnType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let propertyName = interner.intern(name)
        let propertyFQName = ownerInfo.fqName + [propertyName]
        if let existing = symbols.lookupAll(fqName: propertyFQName).first(where: { symbolID in
            symbols.symbol(symbolID)?.kind == .property
        }) {
            guard let existingInfo = symbols.symbol(existing),
                  existingInfo.flags.contains(.synthetic) || existingInfo.declSite == nil else {
                return
            }
            symbols.setExternalLinkName(externalLinkName, for: existing)
            symbols.setPropertyType(returnType, for: existing)
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
        symbols.setExternalLinkName(externalLinkName, for: propertySymbol)
        symbols.setPropertyType(returnType, for: propertySymbol)
    }
}
