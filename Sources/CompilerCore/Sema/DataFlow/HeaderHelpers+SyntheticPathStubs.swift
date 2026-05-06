/// Synthetic stubs for kotlin.io.path.Path type.
///
/// Covers:
/// - `Path(pathString: String)` constructor
/// - `name: String`, `parent: Path?`, `fileName: Path?`, `root: Path?` properties
/// - `nameCount: Int`, `isAbsolute: Boolean` properties
/// - `toString(): String`
/// - `resolve(other: String): Path`, `resolve(other: Path): Path`
/// - `relativize(other: Path): Path`, `normalize(): Path`
/// - `exists(): Boolean`, `isDirectory(): Boolean`, `isRegularFile(): Boolean`
/// - `startsWith(other: Path): Boolean`, `startsWith(other: String): Boolean`
/// - `endsWith(other: Path): Boolean`, `endsWith(other: String): Boolean`
/// - `toFile(): File`, `toUri(): URI`, `toAbsolutePath(): Path`
/// - `URI.toPath(): Path` extension function
/// - `getName(index: Int): Path`
/// - `Path.name: String` extension property
/// - `Path.appendText(text: CharSequence, charset)` extension function
/// - `Path.copyTo(target: Path, options)` extension function
/// - `Path.invariantSeparatorsPath: String` extension property
/// - `Path.absolute(): Path` extension function
/// - `Path.relativeToOrSelf(base: Path): Path` extension function
/// - `Path.invariantSeparatorsPathString: String` extension property
/// - `Path.writeBytes(array: ByteArray, vararg options: OpenOption)` extension function
/// - `readBytes(): ByteArray`, `readText(): String`, `writeText(text: String)`, `readLines(): List<String>`
/// - `createDirectories(): Path`, `createLinkPointingTo(target): Path`, `deleteIfExists(): Boolean`
/// - `deleteExisting()`, `deleteRecursively()`
/// - `Path.fileStore(): FileStore` extension function
/// - `Path.setOwner(value: UserPrincipal): Path` extension function
/// - `listDirectoryEntries(): List<Path>`
/// - `Path.isExecutable()`, `isHidden()`, `isReadable()`, `isSameFileAs()`, `isSymbolicLink()`, `isWritable()`
/// - Top-level `Path(pathString: String)` factory (kotlin.io.path.Path)
/// - `Paths.get(pathString: String)` factory (java.nio.file.Paths)
/// - `CopyActionContext` type surface
/// - `CopyActionResult` enum surface
/// - `ExperimentalPathApi` marker annotation surface
/// - `FileVisitorBuilder` type surface
/// - `OnErrorResult` enum surface
/// - `PathWalkOption` enum surface
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
        let kotlinPkg = ensurePackage(path: ["kotlin"], symbols: symbols, interner: interner)
        let kotlinTextPkg = ensurePackage(path: ["kotlin", "text"], symbols: symbols, interner: interner)
        let kotlinPkgSymbol = symbols.lookup(fqName: kotlinPkg)
        let kotlinTextPkgSymbol = symbols.lookup(fqName: kotlinTextPkg)
        let javaNioFilePkg = ensurePackage(
            path: ["java", "nio", "file"],
            symbols: symbols,
            interner: interner
        )
        let javaNioFilePkgSymbol = symbols.lookup(fqName: javaNioFilePkg)

        let charSequenceSymbol = ensureInterfaceSymbol(
            named: "CharSequence",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        if let kotlinPkgSymbol {
            symbols.setParentSymbol(kotlinPkgSymbol, for: charSequenceSymbol)
        }
        let charSequenceType = types.make(.classType(ClassType(
            classSymbol: charSequenceSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(charSequenceType, for: charSequenceSymbol)

        let byteArraySymbol = ensureClassSymbol(
            named: "ByteArray",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        if let kotlinPkgSymbol {
            symbols.setParentSymbol(kotlinPkgSymbol, for: byteArraySymbol)
        }
        let byteArrayType = types.make(.classType(ClassType(
            classSymbol: byteArraySymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(byteArrayType, for: byteArraySymbol)

        let charsetSymbol = ensureClassSymbol(
            named: "Charset",
            in: kotlinTextPkg,
            symbols: symbols,
            interner: interner
        )
        if let kotlinTextPkgSymbol {
            symbols.setParentSymbol(kotlinTextPkgSymbol, for: charsetSymbol)
        }
        let charsetType = types.make(.classType(ClassType(
            classSymbol: charsetSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(charsetType, for: charsetSymbol)

        let copyOptionPkg = ensurePackage(path: ["java", "nio", "file"], symbols: symbols, interner: interner)
        let copyOptionPkgSymbol = symbols.lookup(fqName: copyOptionPkg)
        let copyOptionSymbol = ensureInterfaceSymbol(
            named: "CopyOption",
            in: copyOptionPkg,
            symbols: symbols,
            interner: interner
        )
        if let copyOptionPkgSymbol {
            symbols.setParentSymbol(copyOptionPkgSymbol, for: copyOptionSymbol)
        }
        let copyOptionType = types.make(.classType(ClassType(
            classSymbol: copyOptionSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(copyOptionType, for: copyOptionSymbol)

        let openOptionSymbol = ensureInterfaceSymbol(
            named: "OpenOption",
            in: javaNioFilePkg,
            symbols: symbols,
            interner: interner
        )
        if let javaNioFilePkgSymbol {
            symbols.setParentSymbol(javaNioFilePkgSymbol, for: openOptionSymbol)
        }
        let openOptionType = types.make(.classType(ClassType(
            classSymbol: openOptionSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(openOptionType, for: openOptionSymbol)

        registerPathCopyActionContextSurface(
            packageFQName: kotlinIOPathPkg,
            packageSymbol: kotlinIOPathPkgSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerPathExperimentalPathApiAnnotation(
            packageFQName: kotlinIOPathPkg,
            packageSymbol: kotlinIOPathPkgSymbol,
            symbols: symbols,
            interner: interner
        )
        registerPathFileVisitorBuilderSurface(
            packageFQName: kotlinIOPathPkg,
            packageSymbol: kotlinIOPathPkgSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )
        let onErrorResultSymbol = ensurePathOnErrorResultEnum(
            in: kotlinIOPathPkg,
            packageSymbol: kotlinIOPathPkgSymbol,
            symbols: symbols,
            interner: interner
        )
        let onErrorResultType = types.make(.classType(ClassType(
            classSymbol: onErrorResultSymbol,
            args: [],
            nullability: .nonNull
        )))
        setPathEnumEntryTypes(
            enumSymbol: onErrorResultSymbol,
            enumType: onErrorResultType,
            symbols: symbols
        )

        let pathWalkOptionSymbol = ensurePathWalkOptionEnum(
            in: kotlinIOPathPkg,
            packageSymbol: kotlinIOPathPkgSymbol,
            symbols: symbols,
            interner: interner
        )
        let pathWalkOptionType = types.make(.classType(ClassType(
            classSymbol: pathWalkOptionSymbol,
            args: [],
            nullability: .nonNull
        )))
        setPathEnumEntryTypes(
            enumSymbol: pathWalkOptionSymbol,
            enumType: pathWalkOptionType,
            symbols: symbols
        )

        let copyActionResultSymbol = ensurePathCopyActionResultEnum(
            in: kotlinIOPathPkg,
            packageSymbol: kotlinIOPathPkgSymbol,
            symbols: symbols,
            interner: interner
        )
        let copyActionResultType = types.make(.classType(ClassType(
            classSymbol: copyActionResultSymbol,
            args: [],
            nullability: .nonNull
        )))
        setPathEnumEntryTypes(
            enumSymbol: copyActionResultSymbol,
            enumType: copyActionResultType,
            symbols: symbols
        )

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
        // Resolve java.io.File type for toFile() return
        let javaIOPkg: [InternedString] = [
            interner.intern("java"),
            interner.intern("io"),
        ]
        let fileSymbol = symbols.lookup(fqName: javaIOPkg + [interner.intern("File")])
        let fileType: TypeID = if let fileSym = fileSymbol {
            types.make(.classType(ClassType(
                classSymbol: fileSym, args: [], nullability: .nonNull
            )))
        } else {
            types.anyType
        }

        let javaNetPkg = ensurePackage(
            path: ["java", "net"],
            symbols: symbols,
            interner: interner
        )
        let javaNetPkgSymbol = symbols.lookup(fqName: javaNetPkg)
        let uriSymbol = ensureClassSymbol(
            named: "URI",
            in: javaNetPkg,
            symbols: symbols,
            interner: interner
        )
        if let javaNetPkgSymbol {
            symbols.setParentSymbol(javaNetPkgSymbol, for: uriSymbol)
        }
        let uriType = types.make(.classType(ClassType(
            classSymbol: uriSymbol, args: [], nullability: .nonNull
        )))
        symbols.setPropertyType(uriType, for: uriSymbol)

        let javaNioFilePackage = ensurePackage(
            path: ["java", "nio", "file"],
            symbols: symbols,
            interner: interner
        )
        let javaNioFilePackageSymbol = symbols.lookup(fqName: javaNioFilePackage)
        let fileStoreSymbol = ensureClassSymbol(
            named: "FileStore",
            in: javaNioFilePackage,
            symbols: symbols,
            interner: interner
        )
        if let javaNioFilePackageSymbol {
            symbols.setParentSymbol(javaNioFilePackageSymbol, for: fileStoreSymbol)
        }
        let fileStoreType = types.make(.classType(ClassType(
            classSymbol: fileStoreSymbol, args: [], nullability: .nonNull
        )))
        symbols.setPropertyType(fileStoreType, for: fileStoreSymbol)

        let javaNioFileAttributePkg = ensurePackage(
            path: ["java", "nio", "file", "attribute"],
            symbols: symbols,
            interner: interner
        )
        let javaNioFileAttributePkgSymbol = symbols.lookup(fqName: javaNioFileAttributePkg)
        let userPrincipalSymbol = ensureInterfaceSymbol(
            named: "UserPrincipal",
            in: javaNioFileAttributePkg,
            symbols: symbols,
            interner: interner
        )
        if let javaNioFileAttributePkgSymbol {
            symbols.setParentSymbol(javaNioFileAttributePkgSymbol, for: userPrincipalSymbol)
        }
        let userPrincipalType = types.make(.classType(ClassType(
            classSymbol: userPrincipalSymbol, args: [], nullability: .nonNull
        )))
        symbols.setPropertyType(userPrincipalType, for: userPrincipalSymbol)

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
            named: "fileName",
            externalLinkName: "kk_path_fileName",
            ownerSymbol: pathSymbol,
            returnType: nullablePathType,
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

        registerPathMemberProperty(
            named: "root",
            externalLinkName: "kk_path_root",
            ownerSymbol: pathSymbol,
            returnType: nullablePathType,
            symbols: symbols,
            interner: interner
        )

        registerPathMemberProperty(
            named: "nameCount",
            externalLinkName: "kk_path_nameCount",
            ownerSymbol: pathSymbol,
            returnType: types.intType,
            symbols: symbols,
            interner: interner
        )

        registerPathMemberProperty(
            named: "isAbsolute",
            externalLinkName: "kk_path_isAbsolute",
            ownerSymbol: pathSymbol,
            returnType: types.booleanType,
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionProperty(
            named: "name",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            returnType: types.stringType,
            externalLinkName: "kk_path_name",
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "absolute",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [],
            returnType: pathType,
            externalLinkName: "kk_path_toAbsolutePath",
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "relativeToOrSelf",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [("base", pathType)],
            returnType: pathType,
            externalLinkName: "kk_path_relativeToOrSelf",
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionProperty(
            named: "invariantSeparatorsPath",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            returnType: types.stringType,
            externalLinkName: "kk_path_invariantSeparatorsPath",
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionProperty(
            named: "invariantSeparatorsPathString",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            returnType: types.stringType,
            externalLinkName: "kk_path_invariantSeparatorsPathString",
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

        registerPathExtensionFunction(
            named: "fileStore",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [],
            returnType: fileStoreType,
            externalLinkName: "kk_path_fileStore",
            symbols: symbols,
            interner: interner
        )

        for (name, link) in [
            ("isExecutable", "kk_path_isExecutable"),
            ("isHidden", "kk_path_isHidden"),
            ("isReadable", "kk_path_isReadable"),
            ("isSymbolicLink", "kk_path_isSymbolicLink"),
            ("isWritable", "kk_path_isWritable"),
        ] {
            registerPathExtensionFunction(
                named: name,
                packageFQName: kotlinIOPathPkg,
                receiverType: pathType,
                parameters: [],
                returnType: types.booleanType,
                externalLinkName: link,
                symbols: symbols,
                interner: interner
            )
        }

        registerPathExtensionFunction(
            named: "isSameFileAs",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [("other", pathType)],
            returnType: types.booleanType,
            externalLinkName: "kk_path_isSameFileAs",
            symbols: symbols,
            interner: interner
        )

        // MARK: - Path comparison methods

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

        // MARK: - Path conversion methods

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

        registerPathMemberFunction(
            named: "toUri",
            externalLinkName: "kk_path_toUri",
            ownerSymbol: pathSymbol,
            ownerType: pathType,
            parameters: [],
            returnType: uriType,
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "toPath",
            packageFQName: kotlinIOPathPkg,
            receiverType: uriType,
            parameters: [],
            returnType: pathType,
            externalLinkName: "kk_uri_toPath",
            symbols: symbols,
            interner: interner
        )

        registerPathMemberFunction(
            named: "toAbsolutePath",
            externalLinkName: "kk_path_toAbsolutePath",
            ownerSymbol: pathSymbol,
            ownerType: pathType,
            parameters: [],
            returnType: pathType,
            symbols: symbols,
            interner: interner
        )

        registerPathMemberFunction(
            named: "getName",
            externalLinkName: "kk_path_getName",
            ownerSymbol: pathSymbol,
            ownerType: pathType,
            parameters: [("index", types.intType)],
            returnType: pathType,
            symbols: symbols,
            interner: interner
        )

        // MARK: - Path read/write methods

        registerPathExtensionFunction(
            named: "readBytes",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [],
            returnType: byteArrayType,
            externalLinkName: "kk_path_readBytes",
            symbols: symbols,
            interner: interner
        )

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

        registerPathExtensionFunction(
            named: "readLines",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [("charset", charsetType)],
            returnType: listOfStringType,
            externalLinkName: "kk_path_readLines_charset",
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "readText",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [("charset", charsetType)],
            returnType: types.stringType,
            externalLinkName: "kk_path_readText_charset",
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "appendText",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [("text", charSequenceType)],
            returnType: pathType,
            externalLinkName: "kk_path_appendText_default",
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "appendText",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [("text", charSequenceType), ("charset", charsetType)],
            returnType: pathType,
            externalLinkName: "kk_path_appendText",
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "copyTo",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [("target", pathType), ("options", copyOptionType)],
            returnType: pathType,
            externalLinkName: "kk_path_copyTo_options",
            valueParameterIsVararg: [false, true],
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "writeBytes",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [("array", byteArrayType), ("options", openOptionType)],
            returnType: types.unitType,
            externalLinkName: "kk_path_writeBytes",
            valueParameterIsVararg: [false, true],
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

        registerPathExtensionFunction(
            named: "createLinkPointingTo",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [("target", pathType)],
            returnType: pathType,
            externalLinkName: "kk_path_createLinkPointingTo",
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "deleteExisting",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [],
            returnType: types.unitType,
            externalLinkName: "kk_path_deleteExisting",
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

        registerPathExtensionFunction(
            named: "setOwner",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [("value", userPrincipalType)],
            returnType: pathType,
            externalLinkName: "kk_path_setOwner",
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "deleteRecursively",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [],
            returnType: types.unitType,
            externalLinkName: "kk_path_deleteRecursively",
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

        registerPathExtensionFunction(
            named: "div",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [("other", pathType)],
            returnType: pathType,
            externalLinkName: "kk_path_div_path",
            isOperator: true,
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "div",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [("other", types.stringType)],
            returnType: pathType,
            externalLinkName: "kk_path_div_string",
            isOperator: true,
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "moveTo",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [("target", pathType), ("overwrite", types.booleanType)],
            returnType: pathType,
            externalLinkName: "kk_path_moveTo_overwrite",
            symbols: symbols,
            interner: interner
        )

        // MARK: - Top-level Path() factory (kotlin.io.path.Path)

        registerPathTopLevelFunction(
            named: "Path",
            packageFQName: kotlinIOPathPkg,
            parameters: [("pathString", types.stringType)],
            returnType: pathType,
            externalLinkName: "kk_path_get",
            symbols: symbols,
            interner: interner
        )

        // MARK: - Paths.get() (java.nio.file.Paths)

        let pathsSymbol = ensureClassSymbol(
            named: "Paths",
            in: javaNioFilePkg,
            symbols: symbols,
            interner: interner
        )
        if let javaNioFilePkgSymbol {
            symbols.setParentSymbol(javaNioFilePkgSymbol, for: pathsSymbol)
        }
        let pathsType = types.make(.classType(ClassType(
            classSymbol: pathsSymbol, args: [], nullability: .nonNull
        )))
        symbols.setPropertyType(pathsType, for: pathsSymbol)

        // Paths.get(pathString: String): Path
        registerPathMemberFunction(
            named: "get",
            externalLinkName: "kk_path_get",
            ownerSymbol: pathsSymbol,
            ownerType: pathsType,
            parameters: [("pathString", types.stringType)],
            returnType: pathType,
            symbols: symbols,
            interner: interner
        )
    }

    // MARK: - Private Helpers

    private func registerPathCopyActionContextSurface(
        packageFQName: [InternedString],
        packageSymbol: SymbolID?,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let contextSymbol = ensureInterfaceSymbol(
            named: "CopyActionContext",
            in: packageFQName,
            symbols: symbols,
            interner: interner
        )
        if let packageSymbol {
            symbols.setParentSymbol(packageSymbol, for: contextSymbol)
        }
        let contextType = types.make(.classType(ClassType(
            classSymbol: contextSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(contextType, for: contextSymbol)
    }

    private func registerPathExperimentalPathApiAnnotation(
        packageFQName: [InternedString],
        packageSymbol: SymbolID?,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let annotationSymbol = ensureAnnotationClassSymbol(
            named: "ExperimentalPathApi",
            in: packageFQName,
            symbols: symbols,
            interner: interner
        )
        if let packageSymbol {
            symbols.setParentSymbol(packageSymbol, for: annotationSymbol)
        }

        var annotations = symbols.annotations(for: annotationSymbol)
        let requiresOptIn = MetadataAnnotationRecord(
            annotationFQName: "kotlin.RequiresOptIn",
            arguments: ["level=RequiresOptIn.Level.ERROR"]
        )
        if !annotations.contains(requiresOptIn) {
            annotations.append(requiresOptIn)
        }

        let target = MetadataAnnotationRecord(
            annotationFQName: "kotlin.annotation.Target",
            arguments: [
                "AnnotationTarget.CLASS",
                "AnnotationTarget.ANNOTATION_CLASS",
                "AnnotationTarget.PROPERTY",
                "AnnotationTarget.FIELD",
                "AnnotationTarget.LOCAL_VARIABLE",
                "AnnotationTarget.VALUE_PARAMETER",
                "AnnotationTarget.CONSTRUCTOR",
                "AnnotationTarget.FUNCTION",
                "AnnotationTarget.PROPERTY_GETTER",
                "AnnotationTarget.PROPERTY_SETTER",
                "AnnotationTarget.TYPEALIAS",
            ]
        )
        if !annotations.contains(target) {
            annotations.append(target)
        }
        symbols.setAnnotations(annotations, for: annotationSymbol)
    }

    private func ensurePathCopyActionResultEnum(
        in packageFQName: [InternedString],
        packageSymbol: SymbolID?,
        symbols: SymbolTable,
        interner: StringInterner
    ) -> SymbolID {
        let name = interner.intern("CopyActionResult")
        let fqName = packageFQName + [name]
        if let existing = symbols.lookup(fqName: fqName) {
            return existing
        }

        let enumSymbol = symbols.define(
            kind: .enumClass,
            name: name,
            fqName: fqName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        if let packageSymbol {
            symbols.setParentSymbol(packageSymbol, for: enumSymbol)
        }

        for entry in ["CONTINUE", "SKIP_SUBTREE", "TERMINATE"] {
            let entryName = interner.intern(entry)
            let entryFQName = fqName + [entryName]
            if symbols.lookup(fqName: entryFQName) != nil {
                continue
            }
            let entrySymbol = symbols.define(
                kind: .field,
                name: entryName,
                fqName: entryFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(enumSymbol, for: entrySymbol)
        }

        return enumSymbol
    }

    private func ensurePathOnErrorResultEnum(
        in packageFQName: [InternedString],
        packageSymbol: SymbolID?,
        symbols: SymbolTable,
        interner: StringInterner
    ) -> SymbolID {
        let name = interner.intern("OnErrorResult")
        let fqName = packageFQName + [name]
        if let existing = symbols.lookup(fqName: fqName) {
            return existing
        }

        let enumSymbol = symbols.define(
            kind: .enumClass,
            name: name,
            fqName: fqName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        if let packageSymbol {
            symbols.setParentSymbol(packageSymbol, for: enumSymbol)
        }

        for entry in ["SKIP_SUBTREE", "TERMINATE"] {
            let entryName = interner.intern(entry)
            let entryFQName = fqName + [entryName]
            if symbols.lookup(fqName: entryFQName) != nil {
                continue
            }
            let entrySymbol = symbols.define(
                kind: .field,
                name: entryName,
                fqName: entryFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(enumSymbol, for: entrySymbol)
        }

        return enumSymbol
    }

    private func ensurePathWalkOptionEnum(
        in packageFQName: [InternedString],
        packageSymbol: SymbolID?,
        symbols: SymbolTable,
        interner: StringInterner
    ) -> SymbolID {
        let name = interner.intern("PathWalkOption")
        let fqName = packageFQName + [name]
        if let existing = symbols.lookup(fqName: fqName) {
            return existing
        }

        let enumSymbol = symbols.define(
            kind: .enumClass,
            name: name,
            fqName: fqName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        if let packageSymbol {
            symbols.setParentSymbol(packageSymbol, for: enumSymbol)
        }

        for entry in ["BREADTH_FIRST", "FOLLOW_LINKS"] {
            let entryName = interner.intern(entry)
            let entryFQName = fqName + [entryName]
            if symbols.lookup(fqName: entryFQName) != nil {
                continue
            }
            let entrySymbol = symbols.define(
                kind: .field,
                name: entryName,
                fqName: entryFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(enumSymbol, for: entrySymbol)
        }

        return enumSymbol
    }

    private func setPathEnumEntryTypes(
        enumSymbol: SymbolID,
        enumType: TypeID,
        symbols: SymbolTable
    ) {
        guard let enumInfo = symbols.symbol(enumSymbol) else { return }
        let children = symbols.children(ofFQName: enumInfo.fqName)
        for child in children {
            guard let childSym = symbols.symbol(child),
                  childSym.kind == .field
            else {
                continue
            }
            if symbols.propertyType(for: child) == nil {
                symbols.setPropertyType(enumType, for: child)
            }
        }
    }

    private func registerPathFileVisitorBuilderSurface(
        packageFQName: [InternedString],
        packageSymbol: SymbolID?,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let builderSymbol = ensureInterfaceSymbol(
            named: "FileVisitorBuilder",
            in: packageFQName,
            symbols: symbols,
            interner: interner
        )
        if let packageSymbol {
            symbols.setParentSymbol(packageSymbol, for: builderSymbol)
        }
        let builderType = types.make(.classType(ClassType(
            classSymbol: builderSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(builderType, for: builderSymbol)
    }

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

    private func registerPathExtensionProperty(
        named name: String,
        packageFQName: [InternedString],
        receiverType: TypeID,
        returnType: TypeID,
        externalLinkName: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let propertyName = interner.intern(name)
        let propertyFQName = packageFQName + [propertyName]
        if let existing = symbols.lookupAll(fqName: propertyFQName).first(where: { symbolID in
            symbols.symbol(symbolID)?.kind == .property
                && symbols.extensionPropertyReceiverType(for: symbolID) == receiverType
        }) {
            symbols.setExternalLinkName(externalLinkName, for: existing)
            symbols.setPropertyType(returnType, for: existing)
            if let getterSymbol = symbols.extensionPropertyGetterAccessor(for: existing) {
                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: receiverType,
                        parameterTypes: [],
                        returnType: returnType
                    ),
                    for: getterSymbol
                )
                symbols.setExternalLinkName(externalLinkName, for: getterSymbol)
            }
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
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: propertySymbol)
        }
        symbols.setPropertyType(returnType, for: propertySymbol)
        symbols.setExtensionPropertyReceiverType(receiverType, for: propertySymbol)
        symbols.setExternalLinkName(externalLinkName, for: propertySymbol)

        let getterSymbol = symbols.define(
            kind: .function,
            name: interner.intern("get"),
            fqName: propertyFQName + [interner.intern("$get")],
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(propertySymbol, for: getterSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [],
                returnType: returnType
            ),
            for: getterSymbol
        )
        symbols.setExtensionPropertyGetterAccessor(getterSymbol, for: propertySymbol)
        symbols.setAccessorOwnerProperty(propertySymbol, for: getterSymbol)
        symbols.setExternalLinkName(externalLinkName, for: getterSymbol)
    }

    private func registerPathExtensionFunction(
        named name: String,
        packageFQName: [InternedString],
        receiverType: TypeID,
        parameters: [(name: String, type: TypeID)],
        returnType: TypeID,
        externalLinkName: String,
        valueParameterHasDefaultValues: [Bool]? = nil,
        valueParameterIsVararg: [Bool]? = nil,
        isOperator: Bool = false,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let parameterIsVararg = valueParameterIsVararg ?? Array(repeating: false, count: parameters.count)
        let functionName = interner.intern(name)
        let functionFQName = packageFQName + [functionName]
        let parameterTypes = parameters.map(\.type)
        let defaults = valueParameterHasDefaultValues
            ?? Array(repeating: false, count: parameters.count)
        let varargs = valueParameterIsVararg
            ?? Array(repeating: false, count: parameters.count)

        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let existingSignature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return existingSignature.receiverType == receiverType
                && existingSignature.parameterTypes == parameterTypes
        }) {
            symbols.setExternalLinkName(externalLinkName, for: existing)
            if isOperator {
                symbols.insertFlags([.operatorFunction], for: existing)
            }
            if let existingSignature = symbols.functionSignature(for: existing) {
                let shouldUpdateSignature =
                    existingSignature.returnType != returnType
                    || existingSignature.valueParameterHasDefaultValues != defaults
                    || existingSignature.valueParameterIsVararg != varargs
                guard shouldUpdateSignature else {
                    return
                }
                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: existingSignature.receiverType,
                        parameterTypes: existingSignature.parameterTypes,
                        returnType: returnType,
                        isSuspend: existingSignature.isSuspend,
                        valueParameterSymbols: existingSignature.valueParameterSymbols,
                        valueParameterHasDefaultValues: defaults,
                        valueParameterIsVararg: varargs
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
            flags: isOperator ? [.synthetic, .operatorFunction] : [.synthetic]
        )
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: functionSymbol)
        }
        symbols.setExternalLinkName(externalLinkName, for: functionSymbol)

        var valueParameterSymbols: [SymbolID] = []
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
            valueParameterSymbols.append(parameterSymbol)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: parameterTypes,
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: defaults,
                valueParameterIsVararg: varargs
            ),
            for: functionSymbol
        )
    }

    private func registerPathTopLevelFunction(
        named name: String,
        packageFQName: [InternedString],
        parameters: [(name: String, type: TypeID)],
        returnType: TypeID,
        externalLinkName: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let functionName = interner.intern(name)
        let functionFQName = packageFQName + [functionName]
        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let existingSignature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return existingSignature.parameterTypes == parameters.map(\.type)
                && existingSignature.returnType == returnType
        }) {
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
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: functionSymbol)
        }
        symbols.setExternalLinkName(externalLinkName, for: functionSymbol)

        var valueParameterSymbols: [SymbolID] = []
        for parameter in parameters {
            let paramNameID = interner.intern(parameter.name)
            let paramSymbol = symbols.define(
                kind: .valueParameter,
                name: paramNameID,
                fqName: functionFQName + [paramNameID],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(functionSymbol, for: paramSymbol)
            valueParameterSymbols.append(paramSymbol)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: parameters.map(\.type),
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count)
            ),
            for: functionSymbol
        )
    }
}
