/// Synthetic stubs for kotlin.io.path.Path type.
///
/// Covers:
/// - `Path(pathString: String)` constructor
/// - `name: String`, `parent: Path?`, `fileName: Path?`, `root: Path?` properties
/// - `nameCount: Int`, `isAbsolute: Boolean` properties
/// - `toString(): String`
/// - `resolve(other: String): Path`, `resolve(other: Path): Path`
/// - `relativize(other: Path): Path`, `normalize(): Path`
/// - `exists(): Boolean`
/// - `Path.isDirectory(vararg options: LinkOption): Boolean` extension function
/// - `Path.isRegularFile(vararg options: LinkOption): Boolean` extension function
/// - `Path.exists(vararg options: LinkOption): Boolean` extension function
/// - `startsWith(other: Path): Boolean`, `startsWith(other: String): Boolean`
/// - `endsWith(other: Path): Boolean`, `endsWith(other: String): Boolean`
/// - `toFile(): File`, `toUri(): URI`, `toAbsolutePath(): Path`
/// - `URI.toPath(): Path` extension function
/// - `getName(index: Int): Path`
/// - `Path.name: String` extension property
/// - `Path.appendText(text: CharSequence, charset)` extension function
/// - `Path.copyTo(target: Path, options)` extension function
/// - `Path.copyTo(target: Path, overwrite: Boolean)` extension function
/// - `Path.invariantSeparatorsPath: String` extension property
/// - `Path.absolute(): Path` extension function
/// - `Path.relativeToOrSelf(base: Path): Path` extension function
/// - `Path.relativeTo(base: Path): Path` extension function
/// - `Path.relativeToOrNull(base: Path): Path?` extension function
/// - `Path.readSymbolicLink(): Path` extension function
/// - `Path.readAttributes(attributes, vararg options: LinkOption): Map<String, Any?>` extension function
/// - `Path.readAttributes<A : BasicFileAttributes>(vararg options: LinkOption): A` extension function
/// - `Path.invariantSeparatorsPathString: String` extension property
/// - `Path.pathString: String` extension property
/// - `Path.writeBytes(array: ByteArray, vararg options: OpenOption)` extension function
/// - `Path.writer(charset, options)` extension function
/// - `Path.outputStream(vararg options: OpenOption): OutputStream` extension function
/// - `Path.moveTo(target: Path, vararg options: CopyOption): Path` extension function
/// - `Path.inputStream(vararg options: OpenOption): InputStream` extension function
/// - `Path.reader(charset, vararg options: OpenOption): BufferedReader` extension function
/// - `Path.inputStream(vararg options: OpenOption): InputStream` extension function
/// - `Path.appendLines(lines: Iterable<CharSequence>, charset)` extension function
/// - `Path.writeLines(lines: Iterable<CharSequence>, charset, options)` extension function
/// - `Path.writeLines(lines: Sequence<CharSequence>, charset, options)` extension function
/// - `Path.absolutePathString(): String` extension function
/// - `Path.appendBytes(array: ByteArray)` extension function
/// - `readBytes(): ByteArray`, `readText(): String`, `writeText(text: String)`, `readLines(): List<String>`
/// - `Path.writeText(text, charset, options)` extension function
/// - `createDirectories(): Path`, `createLinkPointingTo(target): Path`, `Path.deleteIfExists(): Boolean`
/// - `Path.createDirectories(vararg attributes: FileAttribute<*>): Path` extension function
/// - `Path.createDirectory(vararg attributes: FileAttribute<*>): Path` extension function
/// - `Path.createFile(vararg attributes: FileAttribute<*>): Path` extension function
/// - `Path.createSymbolicLinkPointingTo(target: Path, vararg attributes: FileAttribute<*>): Path` extension function
/// - `createTempDirectory(directory: Path?, prefix: String?, vararg attributes: FileAttribute<*>): Path` top-level function
/// - `createTempDirectory(prefix: String?, vararg attributes: FileAttribute<*>): Path` top-level function
/// - `createTempFile(directory: Path?, prefix: String?, suffix: String?, vararg attributes: FileAttribute<*>): Path` top-level function
/// - `createTempFile(prefix: String?, suffix: String?, vararg attributes: FileAttribute<*>): Path` top-level function
/// - `deleteExisting()`, `deleteRecursively()`
/// - `Path.fileStore(): FileStore` extension function
/// - `Path.fileAttributesViewOrNull<V : FileAttributeView>(vararg options: LinkOption): V?` extension function
/// - `Path.getAttribute(attribute: String, vararg options: LinkOption): Any` extension function
/// - `Path.fileAttributesView<V : FileAttributeView>(vararg options: LinkOption): V` extension function
/// - `Path.copyToRecursively(target, onError, followLinks, overwrite): Path` extension function
/// - `Path.copyToRecursively(target, onError, followLinks, copyAction): Path` extension function
/// - `Path.getOwner(vararg options: LinkOption): UserPrincipal` extension function
/// - `Path.getLastModifiedTime(vararg options: LinkOption): FileTime` extension function
/// - `Path.setOwner(value: UserPrincipal): Path` extension function
/// - `Path.getPosixFilePermissions(vararg options: LinkOption): Set<PosixFilePermission>` extension function
/// - `Path.setAttribute(attribute, value, vararg options: LinkOption): Path` extension function
/// - `Path.fileSize(): Long` extension function
/// - `Path.forEachDirectoryEntry(glob, action)` extension function
/// - `Path.forEachLine(charset, action)` extension function
/// - `Path.setPosixFilePermissions(value: Set<PosixFilePermission>): Path` extension function
/// - `Path.useLines(charset, block)` extension function
/// - `Path.listDirectoryEntries(glob: String = "*"): List<Path>` extension function
/// - `Path.walk(options)` extension function
/// - `Path.useDirectoryEntries(glob, block)` extension function
/// - `Path.isExecutable()`, `isHidden()`, `isReadable()`, `isSameFileAs()`, `isSymbolicLink()`, `isWritable()`
/// - `Path.notExists(vararg options: LinkOption): Boolean`
/// - Top-level `Path(pathString: String)` factory (kotlin.io.path.Path)
/// - Top-level `Path(base: String, vararg subpaths: String)` factory (kotlin.io.path.Path)
/// - `Paths.get(pathString: String)` factory (java.nio.file.Paths)
/// - `CopyActionContext` type surface
/// - `CopyActionResult` enum surface
/// - `ExperimentalPathApi` marker annotation surface
/// - `FileVisitorBuilder` type surface
/// - `fileVisitor(builderAction)` top-level function
/// - `Path.visitFileTree(visitor, maxDepth, followLinks)` extension function
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
        let pathActionType = types.make(.functionType(FunctionType(
            params: [pathType],
            returnType: types.unitType,
            isSuspend: false,
            nullability: .nonNull
        )))
        let kotlinPkg = ensurePackage(path: ["kotlin"], symbols: symbols, interner: interner)
        let kotlinCollectionsPkg = ensurePackage(path: ["kotlin", "collections"], symbols: symbols, interner: interner)
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
        let stringActionType = types.make(.functionType(FunctionType(
            params: [types.stringType],
            returnType: types.unitType,
            isSuspend: false,
            nullability: .nonNull
        )))
        let nullableStringType = types.makeNullable(types.stringType)

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

        let linkOptionSymbol = ensureInterfaceSymbol(
            named: "LinkOption",
            in: javaNioFilePkg,
            symbols: symbols,
            interner: interner
        )
        if let javaNioFilePkgSymbol {
            symbols.setParentSymbol(javaNioFilePkgSymbol, for: linkOptionSymbol)
        }
        let linkOptionType = types.make(.classType(ClassType(
            classSymbol: linkOptionSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(linkOptionType, for: linkOptionSymbol)

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
        let fileVisitorBuilderSymbol = ensureInterfaceSymbol(
            named: "FileVisitorBuilder",
            in: kotlinIOPathPkg,
            symbols: symbols,
            interner: interner
        )
        let fileVisitorBuilderType = types.make(.classType(ClassType(
            classSymbol: fileVisitorBuilderSymbol,
            args: [],
            nullability: .nonNull
        )))
        let fileVisitorBuilderActionType = types.make(.functionType(FunctionType(
            receiver: fileVisitorBuilderType,
            params: [],
            returnType: types.unitType,
            isSuspend: false,
            nullability: .nonNull
        )))
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

        let exceptionSymbol = ensureClassSymbol(
            named: "Exception",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        if let kotlinPkgSymbol {
            symbols.setParentSymbol(kotlinPkgSymbol, for: exceptionSymbol)
        }
        let exceptionType = types.make(.classType(ClassType(
            classSymbol: exceptionSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(exceptionType, for: exceptionSymbol)

        let copyActionContextSymbol = ensureInterfaceSymbol(
            named: "CopyActionContext",
            in: kotlinIOPathPkg,
            symbols: symbols,
            interner: interner
        )
        if let kotlinIOPathPkgSymbol {
            symbols.setParentSymbol(kotlinIOPathPkgSymbol, for: copyActionContextSymbol)
        }
        let copyActionContextType = types.make(.classType(ClassType(
            classSymbol: copyActionContextSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(copyActionContextType, for: copyActionContextSymbol)

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

        let iterableFQName = kotlinCollectionsPkg + [interner.intern("Iterable")]
        let iterableSymbol = symbols.lookup(fqName: iterableFQName) ?? registerSyntheticIterableStub(
            symbols: symbols,
            types: types,
            interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg
        )
        let iterableOfCharSequenceType = types.make(.classType(ClassType(
            classSymbol: iterableSymbol,
            args: [.invariant(charSequenceType)],
            nullability: .nonNull
        )))

        let mapSymbol = symbols.lookup(
            fqName: kotlinCollectionsPkg + [interner.intern("Map")]
        ) ?? registerSyntheticMapStub(
            symbols: symbols,
            types: types,
            interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg
        ).mapSymbol
        let mapOfStringToNullableAnyType = types.make(.classType(ClassType(
            classSymbol: mapSymbol,
            args: [.invariant(types.stringType), .out(types.nullableAnyType)],
            nullability: .nonNull
        )))

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
        let javaIOPkg = ensurePackage(path: ["java", "io"], symbols: symbols, interner: interner)
        let javaIOPkgSymbol = symbols.lookup(fqName: javaIOPkg)
        let fileSymbol = symbols.lookup(fqName: javaIOPkg + [interner.intern("File")])
        let fileType: TypeID = if let fileSym = fileSymbol {
            types.make(.classType(ClassType(
                classSymbol: fileSym, args: [], nullability: .nonNull
            )))
        } else {
            types.anyType
        }

        let bufferedReaderSymbol = ensureClassSymbol(
            named: "BufferedReader",
            in: javaIOPkg,
            symbols: symbols,
            interner: interner
        )
        if let javaIOPkgSymbol {
            symbols.setParentSymbol(javaIOPkgSymbol, for: bufferedReaderSymbol)
        }
        let bufferedReaderType = types.make(.classType(ClassType(
            classSymbol: bufferedReaderSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(bufferedReaderType, for: bufferedReaderSymbol)

        let bufferedWriterSymbol = ensureClassSymbol(
            named: "BufferedWriter",
            in: javaIOPkg,
            symbols: symbols,
            interner: interner
        )
        if let javaIOPkgSymbol {
            symbols.setParentSymbol(javaIOPkgSymbol, for: bufferedWriterSymbol)
        }
        let bufferedWriterType = types.make(.classType(ClassType(
            classSymbol: bufferedWriterSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(bufferedWriterType, for: bufferedWriterSymbol)

        let outputStreamSymbol = ensureClassSymbol(
            named: "OutputStream",
            in: javaIOPkg,
            symbols: symbols,
            interner: interner
        )
        if let javaIOPkgSymbol {
            symbols.setParentSymbol(javaIOPkgSymbol, for: outputStreamSymbol)
        }
        let outputStreamType = types.make(.classType(ClassType(
            classSymbol: outputStreamSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(outputStreamType, for: outputStreamSymbol)

        let inputStreamSymbol = ensureClassSymbol(
            named: "InputStream",
            in: javaIOPkg,
            symbols: symbols,
            interner: interner
        )
        if let javaIOPkgSymbol {
            symbols.setParentSymbol(javaIOPkgSymbol, for: inputStreamSymbol)
        }
        let inputStreamType = types.make(.classType(ClassType(
            classSymbol: inputStreamSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(inputStreamType, for: inputStreamSymbol)

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

        let fileVisitorSymbol = ensureGenericPathFileVisitorSymbol(
            in: javaNioFilePackage,
            packageSymbol: javaNioFilePackageSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )
        let fileVisitorOfPathType = types.make(.classType(ClassType(
            classSymbol: fileVisitorSymbol,
            args: [.invariant(pathType)],
            nullability: .nonNull
        )))

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

        let fileAttributeViewSymbol = ensureInterfaceSymbol(
            named: "FileAttributeView",
            in: javaNioFileAttributePkg,
            symbols: symbols,
            interner: interner
        )
        if let javaNioFileAttributePkgSymbol {
            symbols.setParentSymbol(javaNioFileAttributePkgSymbol, for: fileAttributeViewSymbol)
        }
        let fileAttributeViewType = types.make(.classType(ClassType(
            classSymbol: fileAttributeViewSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(fileAttributeViewType, for: fileAttributeViewSymbol)

        let fileAttributeSymbol = ensureGenericFileAttributeSymbol(
            in: javaNioFileAttributePkg,
            packageSymbol: javaNioFileAttributePkgSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )
        let fileAttributeStarType = types.make(.classType(ClassType(
            classSymbol: fileAttributeSymbol,
            args: [.star],
            nullability: .nonNull
        )))

        let basicFileAttributesSymbol = ensureInterfaceSymbol(
            named: "BasicFileAttributes",
            in: javaNioFileAttributePkg,
            symbols: symbols,
            interner: interner
        )
        if let javaNioFileAttributePkgSymbol {
            symbols.setParentSymbol(javaNioFileAttributePkgSymbol, for: basicFileAttributesSymbol)
        }
        let basicFileAttributesType = types.make(.classType(ClassType(
            classSymbol: basicFileAttributesSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(basicFileAttributesType, for: basicFileAttributesSymbol)

        let fileTimeSymbol = ensureClassSymbol(
            named: "FileTime",
            in: javaNioFileAttributePkg,
            symbols: symbols,
            interner: interner
        )
        if let javaNioFileAttributePkgSymbol {
            symbols.setParentSymbol(javaNioFileAttributePkgSymbol, for: fileTimeSymbol)
        }
        let fileTimeType = types.make(.classType(ClassType(
            classSymbol: fileTimeSymbol, args: [], nullability: .nonNull
        )))
        symbols.setPropertyType(fileTimeType, for: fileTimeSymbol)

        let posixFilePermissionName = interner.intern("PosixFilePermission")
        let posixFilePermissionFQName = javaNioFileAttributePkg + [posixFilePermissionName]
        let posixFilePermissionSymbol = symbols.lookup(fqName: posixFilePermissionFQName) ?? symbols.define(
            kind: .enumClass,
            name: posixFilePermissionName,
            fqName: posixFilePermissionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        if let javaNioFileAttributePkgSymbol {
            symbols.setParentSymbol(javaNioFileAttributePkgSymbol, for: posixFilePermissionSymbol)
        }
        let posixFilePermissionType = types.make(.classType(ClassType(
            classSymbol: posixFilePermissionSymbol, args: [], nullability: .nonNull
        )))
        symbols.setPropertyType(posixFilePermissionType, for: posixFilePermissionSymbol)

        let setOfPosixFilePermissionType: TypeID = if let setSymbol = symbols.lookup(
            fqName: [interner.intern("kotlin"), interner.intern("collections"), interner.intern("Set")]
        ) {
            types.make(.classType(ClassType(
                classSymbol: setSymbol,
                args: [.out(posixFilePermissionType)],
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
            named: "fileName",
            externalLinkName: "kk_path_fileName",
            ownerSymbol: pathSymbol,
            returnType: nullablePathType,
            symbols: symbols,
            interner: interner
        )

        registerPathMemberProperty(
            named: "nameWithoutExtension",
            externalLinkName: "kk_path_nameWithoutExtension",
            ownerSymbol: pathSymbol,
            returnType: types.stringType,
            symbols: symbols,
            interner: interner
        )

        registerPathMemberProperty(
            named: "extension",
            externalLinkName: "kk_path_extension",
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

        registerPathExtensionFunction(
            named: "relativeTo",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [("base", pathType)],
            returnType: pathType,
            externalLinkName: "kk_path_relativeTo",
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "relativeToOrNull",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [("base", pathType)],
            returnType: nullablePathType,
            externalLinkName: "kk_path_relativeToOrNull",
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "readSymbolicLink",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [],
            returnType: pathType,
            externalLinkName: "kk_path_readSymbolicLink",
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "readAttributes",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [("attributes", types.stringType), ("options", linkOptionType)],
            returnType: mapOfStringToNullableAnyType,
            externalLinkName: "kk_path_readAttributes_string",
            valueParameterIsVararg: [false, true],
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

        registerPathExtensionProperty(
            named: "pathString",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            returnType: types.stringType,
            externalLinkName: "kk_path_pathString",
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "appendLines",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [("lines", iterableOfCharSequenceType)],
            returnType: pathType,
            externalLinkName: "kk_path_appendLines_iterable_default",
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "appendLines",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [("lines", iterableOfCharSequenceType), ("charset", charsetType)],
            returnType: pathType,
            externalLinkName: "kk_path_appendLines_iterable",
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "writeLines",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [
                ("lines", iterableOfCharSequenceType),
                ("charset", charsetType),
                ("options", openOptionType),
            ],
            returnType: pathType,
            externalLinkName: "kk_path_writeLines_iterable",
            valueParameterHasDefaultValues: [false, true, false],
            valueParameterIsVararg: [false, false, true],
            symbols: symbols,
            interner: interner
        )

        let kotlinSequencesPkg = ensurePackage(path: ["kotlin", "sequences"], symbols: symbols, interner: interner)
        let kotlinSequencesPkgSymbol = symbols.lookup(fqName: kotlinSequencesPkg)
        let sequenceSymbol = ensureInterfaceSymbol(
            named: "Sequence",
            in: kotlinSequencesPkg,
            symbols: symbols,
            interner: interner
        )
        if let kotlinSequencesPkgSymbol {
            symbols.setParentSymbol(kotlinSequencesPkgSymbol, for: sequenceSymbol)
        }
        let sequenceOfCharSequenceType = types.make(.classType(ClassType(
            classSymbol: sequenceSymbol,
            args: [.out(charSequenceType)],
            nullability: .nonNull
        )))
        let sequenceOfStringType = types.make(.classType(ClassType(
            classSymbol: sequenceSymbol,
            args: [.out(types.stringType)],
            nullability: .nonNull
        )))
        let sequenceOfPathType = types.make(.classType(ClassType(
            classSymbol: sequenceSymbol,
            args: [.out(pathType)],
            nullability: .nonNull
        )))

        registerPathExtensionFunction(
            named: "appendLines",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [("lines", sequenceOfCharSequenceType)],
            returnType: pathType,
            externalLinkName: "kk_path_appendLines_sequence_default",
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "appendLines",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [("lines", sequenceOfCharSequenceType), ("charset", charsetType)],
            returnType: pathType,
            externalLinkName: "kk_path_appendLines_sequence",
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "writeLines",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [
                ("lines", sequenceOfCharSequenceType),
                ("charset", charsetType),
                ("options", openOptionType),
            ],
            returnType: pathType,
            externalLinkName: "kk_path_writeLines_sequence",
            valueParameterHasDefaultValues: [false, true, false],
            valueParameterIsVararg: [false, false, true],
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "absolutePathString",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [],
            returnType: types.stringType,
            externalLinkName: "kk_path_toAbsolutePathString",
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "appendBytes",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [("array", byteArrayType)],
            returnType: types.unitType,
            externalLinkName: "kk_path_appendBytes",
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

        registerPathExtensionFunction(
            named: "exists",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [("options", linkOptionType)],
            returnType: types.booleanType,
            externalLinkName: "kk_path_exists",
            valueParameterIsVararg: [true],
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "isDirectory",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [("options", linkOptionType)],
            returnType: types.booleanType,
            externalLinkName: "kk_path_isDirectory",
            valueParameterIsVararg: [true],
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "isRegularFile",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [("options", linkOptionType)],
            returnType: types.booleanType,
            externalLinkName: "kk_path_isRegularFile",
            valueParameterIsVararg: [true],
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

        registerPathReadAttributesFunction(
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            optionsType: linkOptionType,
            basicFileAttributesUpperBound: basicFileAttributesType,
            symbols: symbols,
            types: types,
            interner: interner
        )

        registerPathFileAttributesViewFunction(
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            optionsType: linkOptionType,
            fileAttributeViewUpperBound: fileAttributeViewType,
            symbols: symbols,
            types: types,
            interner: interner
        )

        registerPathFileAttributesViewOrNullFunction(
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            optionsType: linkOptionType,
            fileAttributeViewUpperBound: fileAttributeViewType,
            symbols: symbols,
            types: types,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "getAttribute",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [("attribute", types.stringType), ("options", linkOptionType)],
            returnType: types.anyType,
            externalLinkName: "kk_path_getAttribute",
            valueParameterIsVararg: [false, true],
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "getLastModifiedTime",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [("options", linkOptionType)],
            returnType: fileTimeType,
            externalLinkName: "kk_path_getLastModifiedTime",
            valueParameterIsVararg: [true],
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

        registerPathExtensionFunction(
            named: "notExists",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [("options", linkOptionType)],
            returnType: types.booleanType,
            externalLinkName: "kk_path_notExists",
            valueParameterIsVararg: [true],
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "fileSize",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [],
            returnType: types.longType,
            externalLinkName: "kk_path_fileSize",
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "forEachDirectoryEntry",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [("glob", types.stringType), ("action", pathActionType)],
            returnType: types.unitType,
            externalLinkName: "kk_path_forEachDirectoryEntry",
            valueParameterHasDefaultValues: [true, false],
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "forEachDirectoryEntry",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [("action", pathActionType)],
            returnType: types.unitType,
            externalLinkName: "kk_path_forEachDirectoryEntry_default",
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "forEachLine",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [("charset", charsetType), ("action", stringActionType)],
            returnType: types.unitType,
            externalLinkName: "kk_path_forEachLine",
            valueParameterHasDefaultValues: [true, false],
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "forEachLine",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [("action", stringActionType)],
            returnType: types.unitType,
            externalLinkName: "kk_path_forEachLine_default",
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

        registerPathUseLinesFunction(
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            sequenceOfStringType: sequenceOfStringType,
            charsetType: charsetType,
            symbols: symbols,
            types: types,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "writeText",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [
                ("text", charSequenceType),
                ("charset", charsetType),
                ("options", openOptionType),
            ],
            returnType: pathType,
            externalLinkName: "kk_path_writeText_options",
            valueParameterHasDefaultValues: [false, true, false],
            valueParameterIsVararg: [false, false, true],
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "writeText",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [
                ("text", charSequenceType),
                ("charset", charsetType),
                ("options", openOptionType),
            ],
            returnType: pathType,
            externalLinkName: "kk_path_writeText_options",
            valueParameterHasDefaultValues: [false, true, false],
            valueParameterIsVararg: [false, false, true],
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
            named: "copyTo",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [("target", pathType), ("overwrite", types.booleanType)],
            returnType: pathType,
            externalLinkName: "kk_path_copyTo_overwrite",
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

        registerPathExtensionFunction(
            named: "writer",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [
                ("charset", charsetType),
                ("options", openOptionType),
            ],
            returnType: bufferedWriterType,
            externalLinkName: "kk_path_writer",
            valueParameterHasDefaultValues: [true, false],
            valueParameterIsVararg: [false, true],
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "outputStream",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [("options", openOptionType)],
            returnType: outputStreamType,
            externalLinkName: "kk_path_outputStream",
            valueParameterIsVararg: [true],
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "inputStream",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [("options", openOptionType)],
            returnType: inputStreamType,
            externalLinkName: "kk_path_inputStream",
            valueParameterIsVararg: [true],
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "bufferedReader",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [
                ("charset", charsetType),
                ("bufferSize", types.intType),
                ("options", openOptionType),
            ],
            returnType: bufferedReaderType,
            externalLinkName: "kk_path_bufferedReader",
            valueParameterHasDefaultValues: [true, true, false],
            valueParameterIsVararg: [false, false, true],
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "reader",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [
                ("charset", charsetType),
                ("options", openOptionType),
            ],
            returnType: bufferedReaderType,
            externalLinkName: "kk_path_reader",
            valueParameterHasDefaultValues: [true, false],
            valueParameterIsVararg: [false, true],
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "reader",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [],
            returnType: bufferedReaderType,
            externalLinkName: "kk_path_reader_default",
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "bufferedWriter",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [
                ("charset", charsetType),
                ("bufferSize", types.intType),
                ("options", openOptionType),
            ],
            returnType: bufferedWriterType,
            externalLinkName: "kk_path_bufferedWriter",
            valueParameterHasDefaultValues: [true, true, false],
            valueParameterIsVararg: [false, false, true],
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
            named: "createDirectories",
            externalLinkName: "kk_path_createDirectories_attributes",
            ownerSymbol: pathSymbol,
            ownerType: pathType,
            parameters: [("attributes", fileAttributeStarType)],
            returnType: pathType,
            valueParameterIsVararg: [true],
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "createDirectories",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [("attributes", fileAttributeStarType)],
            returnType: pathType,
            externalLinkName: "kk_path_createDirectories_attributes",
            valueParameterIsVararg: [true],
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "createSymbolicLinkPointingTo",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [
                ("target", pathType),
                ("attributes", fileAttributeStarType),
            ],
            returnType: pathType,
            externalLinkName: "kk_path_createSymbolicLinkPointingTo_attributes",
            valueParameterIsVararg: [false, true],
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "createDirectory",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [("attributes", fileAttributeStarType)],
            returnType: pathType,
            externalLinkName: "kk_path_createDirectory_attributes",
            valueParameterIsVararg: [true],
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "createFile",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [("attributes", fileAttributeStarType)],
            returnType: pathType,
            externalLinkName: "kk_path_createFile_attributes",
            valueParameterIsVararg: [true],
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

        registerPathExtensionFunction(
            named: "deleteIfExists",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [],
            returnType: types.booleanType,
            externalLinkName: "kk_path_deleteIfExists",
            symbols: symbols,
            interner: interner
        )
        annotatePathExtensionFunction(
            named: "deleteIfExists",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [],
            annotations: pathDeleteIfExistsAnnotations(),
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
            named: "getOwner",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [("options", linkOptionType)],
            returnType: userPrincipalType,
            externalLinkName: "kk_path_getOwner",
            valueParameterIsVararg: [true],
            symbols: symbols,
            interner: interner
        )
        registerPathExtensionFunction(
            named: "setAttribute",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [
                ("attribute", types.stringType),
                ("value", types.stringType),
                ("options", linkOptionType),
            ],
            returnType: pathType,
            externalLinkName: "kk_path_setAttribute",
            valueParameterIsVararg: [false, false, true],
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "setPosixFilePermissions",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [("value", setOfPosixFilePermissionType)],
            returnType: pathType,
            externalLinkName: "kk_path_setPosixFilePermissions",
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "getPosixFilePermissions",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [("options", linkOptionType)],
            returnType: setOfPosixFilePermissionType,
            externalLinkName: "kk_path_getPosixFilePermissions",
            valueParameterIsVararg: [true],
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

        let copyToRecursivelyOnErrorType = types.make(.functionType(FunctionType(
            params: [pathType, pathType, exceptionType],
            returnType: onErrorResultType,
            isSuspend: false,
            nullability: .nonNull
        )))
        let copyToRecursivelyCopyActionType = types.make(.functionType(FunctionType(
            receiver: copyActionContextType,
            params: [pathType, pathType],
            returnType: copyActionResultType,
            isSuspend: false,
            nullability: .nonNull
        )))
        registerPathExtensionFunction(
            named: "copyToRecursively",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [
                ("target", pathType),
                ("onError", copyToRecursivelyOnErrorType),
                ("followLinks", types.booleanType),
                ("overwrite", types.booleanType),
            ],
            returnType: pathType,
            externalLinkName: "kk_path_copyToRecursively_overwrite",
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "copyToRecursively",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [
                ("target", pathType),
                ("onError", copyToRecursivelyOnErrorType),
                ("followLinks", types.booleanType),
                ("copyAction", copyToRecursivelyCopyActionType),
            ],
            returnType: pathType,
            externalLinkName: "kk_path_copyToRecursively_copyAction",
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "listDirectoryEntries",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [("glob", types.stringType)],
            returnType: listOfPathType,
            externalLinkName: "kk_path_listDirectoryEntries",
            valueParameterHasDefaultValues: [true],
            symbols: symbols,
            interner: interner
        )

        registerPathUseDirectoryEntriesFunction(
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            sequenceOfPathType: sequenceOfPathType,
            globType: types.stringType,
            symbols: symbols,
            types: types,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "walk",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [("options", pathWalkOptionType)],
            returnType: sequenceOfPathType,
            externalLinkName: "kk_path_walk",
            valueParameterIsVararg: [true],
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

        registerPathExtensionFunction(
            named: "moveTo",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [("target", pathType), ("options", copyOptionType)],
            returnType: pathType,
            externalLinkName: "kk_path_moveTo_options",
            valueParameterIsVararg: [false, true],
            symbols: symbols,
            interner: interner
        )

        registerPathTopLevelFunction(
            named: "createTempDirectory",
            packageFQName: kotlinIOPathPkg,
            parameters: [
                ("directory", nullablePathType),
                ("prefix", nullableStringType),
                ("attributes", fileAttributeStarType),
            ],
            returnType: pathType,
            externalLinkName: "kk_path_createTempDirectory_directory_prefix_attributes",
            valueParameterHasDefaultValues: [false, true, false],
            valueParameterIsVararg: [false, false, true],
            symbols: symbols,
            interner: interner
        )

        registerPathTopLevelFunction(
            named: "createTempDirectory",
            packageFQName: kotlinIOPathPkg,
            parameters: [
                ("prefix", nullableStringType),
                ("attributes", fileAttributeStarType),
            ],
            returnType: pathType,
            externalLinkName: "kk_path_createTempDirectory_prefix_attributes",
            valueParameterHasDefaultValues: [true, false],
            valueParameterIsVararg: [false, true],
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

        registerPathTopLevelFunction(
            named: "Path",
            packageFQName: kotlinIOPathPkg,
            parameters: [("base", types.stringType), ("subpaths", types.stringType)],
            returnType: pathType,
            externalLinkName: "kk_path_get_base_subpaths",
            valueParameterIsVararg: [false, true],
            symbols: symbols,
            interner: interner
        )

        registerPathTopLevelFunction(
            named: "fileVisitor",
            packageFQName: kotlinIOPathPkg,
            parameters: [("builderAction", fileVisitorBuilderActionType)],
            returnType: fileVisitorOfPathType,
            externalLinkName: "kk_path_fileVisitor",
            symbols: symbols,
            interner: interner
        )

        registerPathExtensionFunction(
            named: "visitFileTree",
            packageFQName: kotlinIOPathPkg,
            receiverType: pathType,
            parameters: [
                ("visitor", fileVisitorOfPathType),
                ("maxDepth", types.intType),
                ("followLinks", types.booleanType),
            ],
            returnType: types.unitType,
            externalLinkName: "kk_path_visitFileTree",
            valueParameterHasDefaultValues: [false, true, true],
            symbols: symbols,
            interner: interner
        )

        registerPathTopLevelFunction(
            named: "createTempFile",
            packageFQName: kotlinIOPathPkg,
            parameters: [
                ("directory", nullablePathType),
                ("prefix", nullableStringType),
                ("suffix", nullableStringType),
                ("attributes", fileAttributeStarType),
            ],
            returnType: pathType,
            externalLinkName: "kk_path_createTempFile_directory_prefix_suffix_attributes",
            valueParameterHasDefaultValues: [false, true, true, false],
            valueParameterIsVararg: [false, false, false, true],
            symbols: symbols,
            interner: interner
        )

        registerPathTopLevelFunction(
            named: "createTempFile",
            packageFQName: kotlinIOPathPkg,
            parameters: [
                ("prefix", nullableStringType),
                ("suffix", nullableStringType),
                ("attributes", fileAttributeStarType),
            ],
            returnType: pathType,
            externalLinkName: "kk_path_createTempFile_prefix_suffix_attributes",
            valueParameterHasDefaultValues: [true, true, false],
            valueParameterIsVararg: [false, false, true],
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

    private func ensureGenericPathFileVisitorSymbol(
        in packageFQName: [InternedString],
        packageSymbol: SymbolID?,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> SymbolID {
        let fileVisitorSymbol = ensureInterfaceSymbol(
            named: "FileVisitor",
            in: packageFQName,
            symbols: symbols,
            interner: interner
        )
        if let packageSymbol {
            symbols.setParentSymbol(packageSymbol, for: fileVisitorSymbol)
        }

        let typeParamName = interner.intern("T")
        let typeParamFQName = packageFQName + [interner.intern("FileVisitor"), typeParamName]
        let typeParamSymbol = symbols.lookup(fqName: typeParamFQName) ?? symbols.define(
            kind: .typeParameter,
            name: typeParamName,
            fqName: typeParamFQName,
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(fileVisitorSymbol, for: typeParamSymbol)
        symbols.setTypeParameterUpperBounds([types.anyType], for: typeParamSymbol)
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: fileVisitorSymbol)
        types.setNominalTypeParameterVariances([.invariant], for: fileVisitorSymbol)

        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        let fileVisitorType = types.make(.classType(ClassType(
            classSymbol: fileVisitorSymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))
        symbols.setPropertyType(fileVisitorType, for: fileVisitorSymbol)
        return fileVisitorSymbol
    }

    private func ensureGenericFileAttributeSymbol(
        in packageFQName: [InternedString],
        packageSymbol: SymbolID?,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> SymbolID {
        let fileAttributeSymbol = ensureInterfaceSymbol(
            named: "FileAttribute",
            in: packageFQName,
            symbols: symbols,
            interner: interner
        )
        if let packageSymbol {
            symbols.setParentSymbol(packageSymbol, for: fileAttributeSymbol)
        }

        let typeParamName = interner.intern("T")
        let typeParamFQName = packageFQName + [interner.intern("FileAttribute"), typeParamName]
        let typeParamSymbol = symbols.lookup(fqName: typeParamFQName) ?? symbols.define(
            kind: .typeParameter,
            name: typeParamName,
            fqName: typeParamFQName,
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(fileAttributeSymbol, for: typeParamSymbol)
        symbols.setTypeParameterUpperBounds([types.anyType], for: typeParamSymbol)
        types.setNominalTypeParameterSymbols([typeParamSymbol], for: fileAttributeSymbol)
        types.setNominalTypeParameterVariances([.invariant], for: fileAttributeSymbol)

        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        let fileAttributeType = types.make(.classType(ClassType(
            classSymbol: fileAttributeSymbol,
            args: [.invariant(typeParamType)],
            nullability: .nonNull
        )))
        symbols.setPropertyType(fileAttributeType, for: fileAttributeSymbol)
        return fileAttributeSymbol
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
        valueParameterIsVararg: [Bool]? = nil,
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
                valueParameterIsVararg: valueParameterIsVararg ?? Array(repeating: false, count: parameterSymbols.count)
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

    private func annotatePathExtensionFunction(
        named name: String,
        packageFQName: [InternedString],
        receiverType: TypeID,
        parameters: [(name: String, type: TypeID)],
        annotations: [MetadataAnnotationRecord],
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let functionFQName = packageFQName + [interner.intern(name)]
        let parameterTypes = parameters.map(\.type)
        guard let functionSymbol = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let signature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == receiverType
                && signature.parameterTypes == parameterTypes
        }) else {
            return
        }

        for annotation in annotations {
            appendSyntheticAnnotation(annotation, to: functionSymbol, symbols: symbols)
        }
    }

    private func pathDeleteIfExistsAnnotations() -> [MetadataAnnotationRecord] {
        [
            MetadataAnnotationRecord(annotationFQName: "kotlin.IgnorableReturnValue"),
            MetadataAnnotationRecord(
                annotationFQName: KnownCompilerAnnotation.sinceKotlin.qualifiedName,
                arguments: ["1.5"]
            ),
            MetadataAnnotationRecord(
                annotationFQName: KnownCompilerAnnotation.rootThrows.qualifiedName,
                arguments: ["java.io.IOException::class"]
            )
        ]
    }

    private func registerPathUseLinesFunction(
        packageFQName: [InternedString],
        receiverType: TypeID,
        sequenceOfStringType: TypeID,
        charsetType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        registerPathUseLinesFunction(
            packageFQName: packageFQName,
            receiverType: receiverType,
            sequenceOfStringType: sequenceOfStringType,
            parameters: [("charset", charsetType)],
            externalLinkName: "kk_path_useLines",
            valueParameterHasDefaultValuesPrefix: [true],
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerPathUseLinesFunction(
            packageFQName: packageFQName,
            receiverType: receiverType,
            sequenceOfStringType: sequenceOfStringType,
            parameters: [],
            externalLinkName: "kk_path_useLines_default",
            valueParameterHasDefaultValuesPrefix: [],
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func registerPathUseLinesFunction(
        packageFQName: [InternedString],
        receiverType: TypeID,
        sequenceOfStringType: TypeID,
        parameters: [(name: String, type: TypeID)],
        externalLinkName: String,
        valueParameterHasDefaultValuesPrefix: [Bool],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let functionName = interner.intern("useLines")
        let functionFQName = packageFQName + [functionName]
        let parameterTypesPrefix = parameters.map(\.type)

        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let signature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == receiverType
                && Array(signature.parameterTypes.dropLast()) == parameterTypesPrefix
                && signature.typeParameterSymbols.count == 1
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

        let typeParamName = interner.intern("T")
        let typeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: typeParamName,
            fqName: functionFQName + [interner.intern("$synthetic"), typeParamName, interner.intern(externalLinkName)],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(functionSymbol, for: typeParamSymbol)
        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        let blockType = types.make(.functionType(FunctionType(
            params: [sequenceOfStringType],
            returnType: typeParamType,
            isSuspend: false,
            nullability: .nonNull
        )))

        var valueParameterSymbols: [SymbolID] = []
        for parameterName in parameters.map(\.name) + ["block"] {
            let name = interner.intern(parameterName)
            let parameterSymbol = symbols.define(
                kind: .valueParameter,
                name: name,
                fqName: functionFQName + [name, interner.intern(externalLinkName)],
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
                parameterTypes: parameterTypesPrefix + [blockType],
                returnType: typeParamType,
                isSuspend: false,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: valueParameterHasDefaultValuesPrefix + [false],
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count),
                typeParameterSymbols: [typeParamSymbol]
            ),
            for: functionSymbol
        )
    }

    private func registerPathUseDirectoryEntriesFunction(
        packageFQName: [InternedString],
        receiverType: TypeID,
        sequenceOfPathType: TypeID,
        globType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        registerPathUseDirectoryEntriesFunction(
            packageFQName: packageFQName,
            receiverType: receiverType,
            sequenceOfPathType: sequenceOfPathType,
            parameters: [("glob", globType)],
            externalLinkName: "kk_path_useDirectoryEntries",
            valueParameterHasDefaultValuesPrefix: [true],
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerPathUseDirectoryEntriesFunction(
            packageFQName: packageFQName,
            receiverType: receiverType,
            sequenceOfPathType: sequenceOfPathType,
            parameters: [],
            externalLinkName: "kk_path_useDirectoryEntries_default",
            valueParameterHasDefaultValuesPrefix: [],
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func registerPathUseDirectoryEntriesFunction(
        packageFQName: [InternedString],
        receiverType: TypeID,
        sequenceOfPathType: TypeID,
        parameters: [(name: String, type: TypeID)],
        externalLinkName: String,
        valueParameterHasDefaultValuesPrefix: [Bool],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let functionName = interner.intern("useDirectoryEntries")
        let functionFQName = packageFQName + [functionName]
        let parameterTypesPrefix = parameters.map(\.type)

        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let signature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == receiverType
                && Array(signature.parameterTypes.dropLast()) == parameterTypesPrefix
                && signature.typeParameterSymbols.count == 1
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

        let typeParamName = interner.intern("T")
        let typeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: typeParamName,
            fqName: functionFQName + [interner.intern("$synthetic"), typeParamName, interner.intern(externalLinkName)],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(functionSymbol, for: typeParamSymbol)
        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        let blockType = types.make(.functionType(FunctionType(
            params: [sequenceOfPathType],
            returnType: typeParamType,
            isSuspend: false,
            nullability: .nonNull
        )))

        var valueParameterSymbols: [SymbolID] = []
        for parameterName in parameters.map(\.name) + ["block"] {
            let name = interner.intern(parameterName)
            let parameterSymbol = symbols.define(
                kind: .valueParameter,
                name: name,
                fqName: functionFQName + [name, interner.intern(externalLinkName)],
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
                parameterTypes: parameterTypesPrefix + [blockType],
                returnType: typeParamType,
                isSuspend: false,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: valueParameterHasDefaultValuesPrefix + [false],
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count),
                typeParameterSymbols: [typeParamSymbol]
            ),
            for: functionSymbol
        )
    }

    private func registerPathReadAttributesFunction(
        packageFQName: [InternedString],
        receiverType: TypeID,
        optionsType: TypeID,
        basicFileAttributesUpperBound: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let functionName = interner.intern("readAttributes")
        let functionFQName = packageFQName + [functionName]
        let parameterTypes = [optionsType]

        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let existingSignature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return existingSignature.receiverType == receiverType
                && existingSignature.parameterTypes == parameterTypes
                && existingSignature.typeParameterSymbols.count == 1
        }) {
            symbols.setExternalLinkName("kk_path_readAttributes", for: existing)
            if let existingSignature = symbols.functionSignature(for: existing),
               let typeParamSymbol = existingSignature.typeParameterSymbols.first {
                let returnType = types.make(.typeParam(TypeParamType(
                    symbol: typeParamSymbol,
                    nullability: .nonNull
                )))
                symbols.setTypeParameterUpperBounds([basicFileAttributesUpperBound], for: typeParamSymbol)
                symbols.insertFlags([.reifiedTypeParameter], for: typeParamSymbol)
                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: receiverType,
                        parameterTypes: parameterTypes,
                        returnType: returnType,
                        isSuspend: existingSignature.isSuspend,
                        valueParameterSymbols: existingSignature.valueParameterSymbols,
                        valueParameterHasDefaultValues: [false],
                        valueParameterIsVararg: [true],
                        typeParameterSymbols: [typeParamSymbol],
                        reifiedTypeParameterIndices: [0],
                        typeParameterUpperBoundsList: [[basicFileAttributesUpperBound]]
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
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: functionSymbol)
        }
        symbols.setExternalLinkName("kk_path_readAttributes", for: functionSymbol)

        let typeParamName = interner.intern("A")
        let typeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: typeParamName,
            fqName: functionFQName + [interner.intern("$synthetic"), typeParamName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic, .reifiedTypeParameter]
        )
        symbols.setParentSymbol(functionSymbol, for: typeParamSymbol)
        symbols.setTypeParameterUpperBounds([basicFileAttributesUpperBound], for: typeParamSymbol)
        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))

        let optionsParamName = interner.intern("options")
        let optionsParamSymbol = symbols.define(
            kind: .valueParameter,
            name: optionsParamName,
            fqName: functionFQName + [optionsParamName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(functionSymbol, for: optionsParamSymbol)

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: parameterTypes,
                returnType: typeParamType,
                isSuspend: false,
                valueParameterSymbols: [optionsParamSymbol],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [true],
                typeParameterSymbols: [typeParamSymbol],
                reifiedTypeParameterIndices: [0],
                typeParameterUpperBoundsList: [[basicFileAttributesUpperBound]]
            ),
            for: functionSymbol
        )
    }

    private func registerPathFileAttributesViewFunction(
        packageFQName: [InternedString],
        receiverType: TypeID,
        optionsType: TypeID,
        fileAttributeViewUpperBound: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let functionName = interner.intern("fileAttributesView")
        let functionFQName = packageFQName + [functionName]
        let parameterTypes = [optionsType]

        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let existingSignature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return existingSignature.receiverType == receiverType
                && existingSignature.parameterTypes == parameterTypes
                && existingSignature.typeParameterSymbols.count == 1
        }) {
            symbols.setExternalLinkName("kk_path_fileAttributesView", for: existing)
            if let existingSignature = symbols.functionSignature(for: existing),
               let typeParamSymbol = existingSignature.typeParameterSymbols.first {
                let returnType = types.make(.typeParam(TypeParamType(
                    symbol: typeParamSymbol,
                    nullability: .nonNull
                )))
                symbols.setTypeParameterUpperBounds([fileAttributeViewUpperBound], for: typeParamSymbol)
                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: receiverType,
                        parameterTypes: parameterTypes,
                        returnType: returnType,
                        isSuspend: existingSignature.isSuspend,
                        valueParameterSymbols: existingSignature.valueParameterSymbols,
                        valueParameterHasDefaultValues: [false],
                        valueParameterIsVararg: [true],
                        typeParameterSymbols: [typeParamSymbol],
                        typeParameterUpperBoundsList: [[fileAttributeViewUpperBound]]
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
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: functionSymbol)
        }
        symbols.setExternalLinkName("kk_path_fileAttributesView", for: functionSymbol)

        let typeParamName = interner.intern("V")
        let typeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: typeParamName,
            fqName: functionFQName + [interner.intern("$synthetic"), typeParamName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(functionSymbol, for: typeParamSymbol)
        symbols.setTypeParameterUpperBounds([fileAttributeViewUpperBound], for: typeParamSymbol)
        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))

        let optionsParamName = interner.intern("options")
        let optionsParamSymbol = symbols.define(
            kind: .valueParameter,
            name: optionsParamName,
            fqName: functionFQName + [optionsParamName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(functionSymbol, for: optionsParamSymbol)

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: parameterTypes,
                returnType: typeParamType,
                isSuspend: false,
                valueParameterSymbols: [optionsParamSymbol],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [true],
                typeParameterSymbols: [typeParamSymbol],
                typeParameterUpperBoundsList: [[fileAttributeViewUpperBound]]
            ),
            for: functionSymbol
        )
    }

    private func registerPathFileAttributesViewOrNullFunction(
        packageFQName: [InternedString],
        receiverType: TypeID,
        optionsType: TypeID,
        fileAttributeViewUpperBound: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let functionName = interner.intern("fileAttributesViewOrNull")
        let functionFQName = packageFQName + [functionName]
        let parameterTypes = [optionsType]

        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let existingSignature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return existingSignature.receiverType == receiverType
                && existingSignature.parameterTypes == parameterTypes
                && existingSignature.typeParameterSymbols.count == 1
        }) {
            symbols.setExternalLinkName("kk_path_fileAttributesViewOrNull", for: existing)
            if let existingSignature = symbols.functionSignature(for: existing),
               let typeParamSymbol = existingSignature.typeParameterSymbols.first {
                let typeParamType = types.make(.typeParam(TypeParamType(
                    symbol: typeParamSymbol,
                    nullability: .nonNull
                )))
                symbols.setTypeParameterUpperBounds([fileAttributeViewUpperBound], for: typeParamSymbol)
                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: receiverType,
                        parameterTypes: parameterTypes,
                        returnType: types.makeNullable(typeParamType),
                        isSuspend: existingSignature.isSuspend,
                        valueParameterSymbols: existingSignature.valueParameterSymbols,
                        valueParameterHasDefaultValues: [false],
                        valueParameterIsVararg: [true],
                        typeParameterSymbols: [typeParamSymbol],
                        typeParameterUpperBoundsList: [[fileAttributeViewUpperBound]]
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
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: functionSymbol)
        }
        symbols.setExternalLinkName("kk_path_fileAttributesViewOrNull", for: functionSymbol)

        let typeParamName = interner.intern("V")
        let typeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: typeParamName,
            fqName: functionFQName + [interner.intern("$synthetic"), typeParamName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(functionSymbol, for: typeParamSymbol)
        symbols.setTypeParameterUpperBounds([fileAttributeViewUpperBound], for: typeParamSymbol)
        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))

        let optionsParamName = interner.intern("options")
        let optionsParamSymbol = symbols.define(
            kind: .valueParameter,
            name: optionsParamName,
            fqName: functionFQName + [optionsParamName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(functionSymbol, for: optionsParamSymbol)

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: parameterTypes,
                returnType: types.makeNullable(typeParamType),
                isSuspend: false,
                valueParameterSymbols: [optionsParamSymbol],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [true],
                typeParameterSymbols: [typeParamSymbol],
                typeParameterUpperBoundsList: [[fileAttributeViewUpperBound]]
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
        valueParameterHasDefaultValues: [Bool]? = nil,
        valueParameterIsVararg: [Bool]? = nil,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
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
            return existingSignature.parameterTypes == parameterTypes
                && existingSignature.returnType == returnType
        }) {
            symbols.setExternalLinkName(externalLinkName, for: existing)
            if let existingSignature = symbols.functionSignature(for: existing) {
                let shouldUpdateSignature =
                    existingSignature.valueParameterHasDefaultValues != defaults
                    || existingSignature.valueParameterIsVararg != varargs
                guard shouldUpdateSignature else {
                    return
                }
                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: existingSignature.receiverType,
                        parameterTypes: existingSignature.parameterTypes,
                        returnType: existingSignature.returnType,
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
}
