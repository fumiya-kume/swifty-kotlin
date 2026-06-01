/// Synthetic stubs for java.io.File type.
///
/// Covers:
/// - STDLIB-320: `File(String)` constructor, `readText`, `writeText`, `readLines`
/// - STDLIB-664: `appendText(text: String)` member function
/// - STDLIB-321: `name`, `path` properties; `exists()`, `isFile()`, `isDirectory()` query methods
/// - STDLIB-322: `forEachLine(action:)` member function
/// - STDLIB-323: `delete()`, `mkdirs()`, `listFiles()`, `walk()` filesystem operations
/// - STDLIB-664: `appendText(text: String)` member function
/// - STDLIB-567: `bufferedReader()` returning `BufferedReader` with `readLine()`, `readLines()`, `close()`
///
/// Each stub registers the java.io.File class, its constructor, member properties,
/// and member functions in the symbol table so that name resolution and type
/// checking succeed without requiring a full java.io runtime on the classpath.
extension DataFlowSemaPhase {
    func registerSyntheticFileIOStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let javaIOPkg = ensureJavaIOPackage(symbols: symbols, interner: interner)
        let javaIOPkgSymbol = symbols.lookup(fqName: javaIOPkg)

        let fileSymbol = ensureClassSymbol(
            named: "File",
            in: javaIOPkg,
            symbols: symbols,
            interner: interner
        )
        if let javaIOPkgSymbol {
            symbols.setParentSymbol(javaIOPkgSymbol, for: fileSymbol)
        }
        let fileType = types.make(.classType(ClassType(
            classSymbol: fileSymbol, args: [], nullability: .nonNull
        )))
        symbols.setPropertyType(fileType, for: fileSymbol)

        // List<File> type for listFiles return
        let listSymbol = resolveListSymbol(symbols: symbols, interner: interner)
        if listSymbol == nil {
            assertionFailure("kotlin.collections.List symbol not found; File IO stubs will use Any as fallback")
        }
        let listOfFileType: TypeID = if let listSym = listSymbol {
            types.make(.classType(ClassType(
                classSymbol: listSym,
                args: [.out(fileType)],
                nullability: .nonNull
            )))
        } else {
            types.anyType
        }
        let nullableListOfFileType = types.makeNullable(listOfFileType)

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

        // (String) -> Unit function type for forEachLine action parameter
        let stringToUnitType = types.make(.functionType(FunctionType(
            params: [types.stringType],
            returnType: types.unitType,
            isSuspend: false,
            nullability: .nonNull
        )))

        // MARK: - File(String) constructor (STDLIB-320)

        registerFileConstructor(
            ownerSymbol: fileSymbol,
            ownerType: fileType,
            parameters: [("path", types.stringType)],
            externalLinkName: "kk_file_new",
            symbols: symbols,
            interner: interner
        )

        // MARK: - File(parent, child) constructor (STDLIB-IO-087)

        registerFileConstructor(
            ownerSymbol: fileSymbol,
            ownerType: fileType,
            parameters: [("parent", types.stringType), ("child", types.stringType)],
            externalLinkName: "kk_file_new_parent_child",
            symbols: symbols,
            interner: interner
        )

        // MARK: - File properties (STDLIB-321)

        registerFileMemberProperty(
            named: "name",
            externalLinkName: "kk_file_name",
            ownerSymbol: fileSymbol,
            returnType: types.stringType,
            symbols: symbols,
            interner: interner
        )

        // STDLIB-IO-PROP-005: File.nameWithoutExtension extension property
        registerFileMemberProperty(
            named: "nameWithoutExtension",
            externalLinkName: "kk_file_nameWithoutExtension",
            ownerSymbol: fileSymbol,
            returnType: types.stringType,
            symbols: symbols,
            interner: interner
        )

        registerFileMemberProperty(
            named: "path",
            externalLinkName: "kk_file_path",
            ownerSymbol: fileSymbol,
            returnType: types.stringType,
            symbols: symbols,
            interner: interner
        )

        // MARK: - Additional File properties (STDLIB-IO-087)

        registerFileMemberProperty(
            named: "absolutePath",
            externalLinkName: "kk_file_absolutePath",
            ownerSymbol: fileSymbol,
            returnType: types.stringType,
            symbols: symbols,
            interner: interner
        )

        registerFileMemberProperty(
            named: "canonicalPath",
            externalLinkName: "kk_file_canonicalPath",
            ownerSymbol: fileSymbol,
            returnType: types.stringType,
            symbols: symbols,
            interner: interner
        )

        let nullableStringType = types.makeNullable(types.stringType)
        registerFileMemberProperty(
            named: "parent",
            externalLinkName: "kk_file_parent",
            ownerSymbol: fileSymbol,
            returnType: nullableStringType,
            symbols: symbols,
            interner: interner
        )

        // MARK: - File extension property (STDLIB-IO-PROP-002)

        // `kotlin.io.File.extension` is a non-null `String` extension property that
        // returns the substring after the last `.` of the file name. When the file
        // name contains no dot, the property returns an empty string. This matches
        // Kotlin's stdlib `kotlin.io.FileTreeWalk.kt` definition. The Sema layer
        // exposes it as a synthetic member on `java.io.File` because KSwiftK does
        // not yet model Kotlin extension properties separately from members.
        registerFileMemberProperty(
            named: "extension",
            externalLinkName: "kk_file_extension",
            ownerSymbol: fileSymbol,
            returnType: types.stringType,
            symbols: symbols,
            interner: interner
        )

        // MARK: - File query methods (STDLIB-321)

        registerFileMemberFunction(
            named: "exists",
            externalLinkName: "kk_file_exists",
            ownerSymbol: fileSymbol,
            ownerType: fileType,
            parameters: [],
            returnType: types.booleanType,
            symbols: symbols,
            interner: interner
        )

        registerFileMemberFunction(
            named: "isFile",
            externalLinkName: "kk_file_isFile",
            ownerSymbol: fileSymbol,
            ownerType: fileType,
            parameters: [],
            returnType: types.booleanType,
            symbols: symbols,
            interner: interner
        )

        registerFileMemberFunction(
            named: "isDirectory",
            externalLinkName: "kk_file_isDirectory",
            ownerSymbol: fileSymbol,
            ownerType: fileType,
            parameters: [],
            returnType: types.booleanType,
            symbols: symbols,
            interner: interner
        )

        // MARK: - Additional File query/operation methods (STDLIB-IO-087)

        registerFileMemberFunction(
            named: "createNewFile",
            externalLinkName: "kk_file_createNewFile",
            ownerSymbol: fileSymbol,
            ownerType: fileType,
            parameters: [],
            returnType: types.booleanType,
            symbols: symbols,
            interner: interner
        )

        registerFileMemberFunction(
            named: "length",
            externalLinkName: "kk_file_length",
            ownerSymbol: fileSymbol,
            ownerType: fileType,
            parameters: [],
            returnType: types.longType,
            symbols: symbols,
            interner: interner
        )

        registerFileMemberFunction(
            named: "lastModified",
            externalLinkName: "kk_file_lastModified",
            ownerSymbol: fileSymbol,
            ownerType: fileType,
            parameters: [],
            returnType: types.longType,
            symbols: symbols,
            interner: interner
        )

        registerFileMemberFunction(
            named: "canRead",
            externalLinkName: "kk_file_canRead",
            ownerSymbol: fileSymbol,
            ownerType: fileType,
            parameters: [],
            returnType: types.booleanType,
            symbols: symbols,
            interner: interner
        )

        registerFileMemberFunction(
            named: "canWrite",
            externalLinkName: "kk_file_canWrite",
            ownerSymbol: fileSymbol,
            ownerType: fileType,
            parameters: [],
            returnType: types.booleanType,
            symbols: symbols,
            interner: interner
        )

        registerFileMemberFunction(
            named: "canExecute",
            externalLinkName: "kk_file_canExecute",
            ownerSymbol: fileSymbol,
            ownerType: fileType,
            parameters: [],
            returnType: types.booleanType,
            symbols: symbols,
            interner: interner
        )

        // MARK: - File.resolveSibling (STDLIB-IO-FN-036)
        //
        // Two overloads matching kotlin.io.File:
        //   fun File.resolveSibling(relative: File): File
        //   fun File.resolveSibling(relative: String): File
        // Both replace the last path component of the receiver with `relative`,
        // mirroring kotlin.io.File.resolveSibling semantics.

        registerFileMemberFunction(
            named: "resolveSibling",
            externalLinkName: "kk_file_resolveSibling_file",
            ownerSymbol: fileSymbol,
            ownerType: fileType,
            parameters: [("relative", fileType)],
            returnType: fileType,
            symbols: symbols,
            interner: interner
        )

        registerFileMemberFunction(
            named: "resolveSibling",
            externalLinkName: "kk_file_resolveSibling_string",
            ownerSymbol: fileSymbol,
            ownerType: fileType,
            parameters: [("relative", types.stringType)],
            returnType: fileType,
            symbols: symbols,
            interner: interner
        )

        // MARK: - File.startsWith (STDLIB-IO-FN-037)
        //
        // Two overloads matching kotlin.io.File:
        //   fun File.startsWith(other: File): Boolean
        //   fun File.startsWith(other: String): Boolean
        // Both compare path components against the receiver, returning true when
        // the receiver's path begins with all components of `other`.

        registerFileMemberFunction(
            named: "startsWith",
            externalLinkName: "kk_file_startsWith_file",
            ownerSymbol: fileSymbol,
            ownerType: fileType,
            parameters: [("other", fileType)],
            returnType: types.booleanType,
            symbols: symbols,
            interner: interner
        )

        registerFileMemberFunction(
            named: "startsWith",
            externalLinkName: "kk_file_startsWith_string",
            ownerSymbol: fileSymbol,
            ownerType: fileType,
            parameters: [("other", types.stringType)],
            returnType: types.booleanType,
            symbols: symbols,
            interner: interner
        )

        // MARK: - STDLIB-IO-FN-038: File.toRelativeString(base: File): String
        //
        // Produces the relative path string from `base` to `this`, mirroring the
        // semantics of `kotlin.io.File.toRelativeString`. The synthetic stub
        // binds to the runtime helper `kk_file_toRelativeString`, which is
        // responsible for raising `IllegalArgumentException` via the standard
        // `outThrown` channel when the two paths cannot share a common root.
        registerFileMemberFunction(
            named: "toRelativeString",
            externalLinkName: "kk_file_toRelativeString",
            ownerSymbol: fileSymbol,
            ownerType: fileType,
            parameters: [("base", fileType)],
            returnType: types.stringType,
            symbols: symbols,
            interner: interner
        )

        // MARK: - File read/write methods (STDLIB-320)

        registerFileMemberFunction(
            named: "readText",
            externalLinkName: "kk_file_readText",
            ownerSymbol: fileSymbol,
            ownerType: fileType,
            parameters: [],
            returnType: types.stringType,
            symbols: symbols,
            interner: interner
        )

        registerFileMemberFunction(
            named: "writeText",
            externalLinkName: "kk_file_writeText",
            ownerSymbol: fileSymbol,
            ownerType: fileType,
            parameters: [("text", types.stringType)],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )

        // MARK: - File.appendText() (STDLIB-664)

        registerFileMemberFunction(
            named: "appendText",
            externalLinkName: "kk_file_appendText",
            ownerSymbol: fileSymbol,
            ownerType: fileType,
            parameters: [("text", types.stringType)],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )

        registerFileMemberFunction(
            named: "appendText",
            externalLinkName: "kk_file_appendText",
            ownerSymbol: fileSymbol,
            ownerType: fileType,
            parameters: [("text", types.stringType)],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )

        registerFileMemberFunction(
            named: "readLines",
            externalLinkName: "kk_file_readLines",
            ownerSymbol: fileSymbol,
            ownerType: fileType,
            parameters: [],
            returnType: listOfStringType,
            symbols: symbols,
            interner: interner
        )

        // MARK: - File.readBytes() (STDLIB-665)

        // ByteArray is represented as List<Int> in the runtime
        let intType = types.intType
        let listOfIntType: TypeID = if let listSym = listSymbol {
            types.make(.classType(ClassType(
                classSymbol: listSym,
                args: [.out(intType)],
                nullability: .nonNull
            )))
        } else {
            types.anyType
        }

        registerFileMemberFunction(
            named: "readBytes",
            externalLinkName: "kk_file_readBytes",
            ownerSymbol: fileSymbol,
            ownerType: fileType,
            parameters: [],
            returnType: listOfIntType,
            symbols: symbols,
            interner: interner
        )

        // MARK: - File.appendBytes() (STDLIB-IO-FN-001)
        //
        // Kotlin signature: `fun File.appendBytes(array: ByteArray): Unit`
        // ByteArray is represented internally as List<Int>; we register both
        // the ByteArray-typed overload (user-facing) and List<Int> (internal)
        // so that both `byteArrayOf(...)` and `listOf(...)` argument styles resolve.

        let byteArrayFQName: [InternedString] = [interner.intern("kotlin"), interner.intern("ByteArray")]
        let appendBytesByteArrayType: TypeID
        if let byteArraySymbol = symbols.lookup(fqName: byteArrayFQName) {
            appendBytesByteArrayType = types.make(.classType(ClassType(
                classSymbol: byteArraySymbol, args: [], nullability: .nonNull
            )))
        } else {
            appendBytesByteArrayType = listOfIntType
        }

        for arrayParamType in [appendBytesByteArrayType, listOfIntType] {
            registerFileMemberFunction(
                named: "appendBytes",
                externalLinkName: "kk_file_appendBytes",
                ownerSymbol: fileSymbol,
                ownerType: fileType,
                parameters: [("array", arrayParamType)],
                returnType: types.unitType,
                symbols: symbols,
                interner: interner
            )
        }

        // MARK: - File line-by-line operations (STDLIB-322)

        registerFileMemberFunction(
            named: "forEachLine",
            externalLinkName: "kk_file_forEachLine",
            ownerSymbol: fileSymbol,
            ownerType: fileType,
            parameters: [("action", stringToUnitType)],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )

        // MARK: - File.forEachBlock(action) and File.forEachBlock(blockSize, action) (STDLIB-IO-FN-016)
        let byteArrayToIntToUnitType = types.make(.functionType(FunctionType(
            params: [listOfIntType, types.intType],
            returnType: types.unitType,
            isSuspend: false,
            nullability: .nonNull
        )))
        registerFileMemberFunction(
            named: "forEachBlock",
            externalLinkName: "kk_file_forEachBlock",
            ownerSymbol: fileSymbol,
            ownerType: fileType,
            parameters: [("action", byteArrayToIntToUnitType)],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )
        registerFileMemberFunction(
            named: "forEachBlock",
            externalLinkName: "kk_file_forEachBlock_blockSize",
            ownerSymbol: fileSymbol,
            ownerType: fileType,
            parameters: [("blockSize", types.intType), ("action", byteArrayToIntToUnitType)],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )

        // MARK: - File.useLines {} (STDLIB-566)

        // (List<String>) -> T  (represented as Any for generic return)
        let listOfStringToAnyType = types.make(.functionType(FunctionType(
            params: [listOfStringType],
            returnType: types.anyType,
            isSuspend: false,
            nullability: .nonNull
        )))

        registerFileMemberFunction(
            named: "useLines",
            externalLinkName: "kk_file_useLines",
            ownerSymbol: fileSymbol,
            ownerType: fileType,
            parameters: [("block", listOfStringToAnyType)],
            returnType: types.anyType,
            symbols: symbols,
            interner: interner
        )

        // MARK: - File filesystem operations (STDLIB-323)

        registerFileMemberFunction(
            named: "delete",
            externalLinkName: "kk_file_delete",
            ownerSymbol: fileSymbol,
            ownerType: fileType,
            parameters: [],
            returnType: types.booleanType,
            symbols: symbols,
            interner: interner
        )

        registerFileMemberFunction(
            named: "mkdirs",
            externalLinkName: "kk_file_mkdirs",
            ownerSymbol: fileSymbol,
            ownerType: fileType,
            parameters: [],
            returnType: types.booleanType,
            symbols: symbols,
            interner: interner
        )

        registerFileMemberFunction(
            named: "listFiles",
            externalLinkName: "kk_file_listFiles",
            ownerSymbol: fileSymbol,
            ownerType: fileType,
            parameters: [],
            returnType: nullableListOfFileType,
            symbols: symbols,
            interner: interner
        )

        registerFileMemberFunction(
            named: "walk",
            externalLinkName: "kk_file_walk",
            ownerSymbol: fileSymbol,
            ownerType: fileType,
            parameters: [],
            returnType: listOfFileType,
            symbols: symbols,
            interner: interner
        )

        // MARK: - Reader / BufferedReader types and File.bufferedReader() (STDLIB-567)

        // `java.io.Reader` is the abstract supertype of `BufferedReader` and is
        // the receiver of `kotlin.io` extension functions such as
        // `Reader.readText()` (STDLIB-IO-FN-033). We register it as a synthetic
        // class so that extension calls on any concrete reader instance (which
        // is currently always a `BufferedReader`) resolve correctly.
        let readerSymbol = ensureClassSymbol(
            named: "Reader",
            in: javaIOPkg,
            symbols: symbols,
            interner: interner
        )
        let bufferedReaderSymbol = ensureClassSymbol(
            named: "BufferedReader",
            in: javaIOPkg,
            symbols: symbols,
            interner: interner
        )
        if let javaIOPkgSymbol {
            symbols.setParentSymbol(javaIOPkgSymbol, for: readerSymbol)
            symbols.setParentSymbol(javaIOPkgSymbol, for: bufferedReaderSymbol)
        }
        let readerType = types.make(.classType(ClassType(
            classSymbol: readerSymbol, args: [], nullability: .nonNull
        )))
        let bufferedReaderType = types.make(.classType(ClassType(
            classSymbol: bufferedReaderSymbol, args: [], nullability: .nonNull
        )))
        symbols.setPropertyType(readerType, for: readerSymbol)
        symbols.setPropertyType(bufferedReaderType, for: bufferedReaderSymbol)

        // File.bufferedReader() -> BufferedReader
        registerFileMemberFunction(
            named: "bufferedReader",
            externalLinkName: "kk_file_bufferedReader",
            ownerSymbol: fileSymbol,
            ownerType: fileType,
            parameters: [],
            returnType: bufferedReaderType,
            symbols: symbols,
            interner: interner
        )

        // BufferedReader.readLine() -> String?
        registerFileMemberFunction(
            named: "readLine",
            externalLinkName: "kk_buffered_reader_readLine",
            ownerSymbol: bufferedReaderSymbol,
            ownerType: bufferedReaderType,
            parameters: [],
            returnType: nullableStringType,
            symbols: symbols,
            interner: interner
        )

        // BufferedReader.readLines() -> List<String>
        registerFileMemberFunction(
            named: "readLines",
            externalLinkName: "kk_buffered_reader_readLines",
            ownerSymbol: bufferedReaderSymbol,
            ownerType: bufferedReaderType,
            parameters: [],
            returnType: listOfStringType,
            symbols: symbols,
            interner: interner
        )

        // BufferedReader.close() -> Unit
        registerFileMemberFunction(
            named: "close",
            externalLinkName: "kk_buffered_reader_close",
            ownerSymbol: bufferedReaderSymbol,
            ownerType: bufferedReaderType,
            parameters: [],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )

        // Register BufferedReader as a Reader/Closeable subtype.
        // - Reader supertype lets `Reader.readText()` (STDLIB-IO-FN-033) resolve
        //   when invoked on a `BufferedReader` value (the only concrete reader
        //   currently produced by `File.bufferedReader()` etc.).
        // - Closeable supertype (STDLIB-IO-093) lets `.use {}` work:
        //   `file.bufferedReader().use { reader -> ... }`.
        if let closeableSymbol = types.closeableInterfaceSymbol {
            symbols.setDirectSupertypes([closeableSymbol], for: readerSymbol)
            types.setNominalDirectSupertypes([closeableSymbol], for: readerSymbol)
            symbols.setDirectSupertypes([readerSymbol, closeableSymbol], for: bufferedReaderSymbol)
            types.setNominalDirectSupertypes([readerSymbol, closeableSymbol], for: bufferedReaderSymbol)
        } else {
            symbols.setDirectSupertypes([readerSymbol], for: bufferedReaderSymbol)
            types.setNominalDirectSupertypes([readerSymbol], for: bufferedReaderSymbol)
        }
        // MARK: - BufferedWriter type and File.bufferedWriter() (STDLIB-IO-091)

        // BufferedReader.read() -> Int  (STDLIB-IO-091)
        registerFileMemberFunction(
            named: "read",
            externalLinkName: "kk_buffered_reader_read",
            ownerSymbol: bufferedReaderSymbol,
            ownerType: bufferedReaderType,
            parameters: [],
            returnType: intType,
            symbols: symbols,
            interner: interner
        )

        // BufferedReader.ready() -> Boolean  (STDLIB-IO-091)
        registerFileMemberFunction(
            named: "ready",
            externalLinkName: "kk_buffered_reader_ready",
            ownerSymbol: bufferedReaderSymbol,
            ownerType: bufferedReaderType,
            parameters: [],
            returnType: types.booleanType,
            symbols: symbols,
            interner: interner
        )

        // BufferedReader.iterator() -> Iterator<String>  (STDLIB-IO-FN-022)
        //
        // The standard library declares `iterator()` as an `operator` extension on
        // `BufferedReader` so that `for (line in reader) { ... }` is a shorthand
        // for iterating over the reader's lines. We register the function as a
        // synthetic *operator* member here so it can be picked up both by
        // explicit calls (`reader.iterator()`) and by the for-loop lowering
        // (which requires the `.operatorFunction` flag).
        let iteratorOfStringType = syntheticIteratorType(
            elementType: types.stringType,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerFileMemberFunction(
            named: "iterator",
            externalLinkName: "kk_buffered_reader_iterator",
            ownerSymbol: bufferedReaderSymbol,
            ownerType: bufferedReaderType,
            parameters: [],
            returnType: iteratorOfStringType,
            symbols: symbols,
            interner: interner
        )
        // Promote the synthetic iterator member to an operator function so that
        // implicit `for (line in reader)` resolution succeeds. We look up the
        // symbol after registration because `registerFileMemberFunction` does
        // not surface the newly defined SymbolID.
        let iteratorFQName: [InternedString] = (symbols.symbol(bufferedReaderSymbol)?.fqName ?? [])
            + [interner.intern("iterator")]
        for candidate in symbols.lookupAll(fqName: iteratorFQName) {
            guard let info = symbols.symbol(candidate),
                  info.flags.contains(.synthetic),
                  let signature = symbols.functionSignature(for: candidate),
                  signature.receiverType == bufferedReaderType,
                  signature.parameterTypes.isEmpty
            else { continue }
            symbols.insertFlags(.operatorFunction, for: candidate)
        }

        // BufferedReader.useLines { lines: List<String> -> T } (STDLIB-IO-FN-040)
        //
        // Kotlin declares `useLines` as an extension function on `kotlin.io.Reader`
        // (which `BufferedReader` extends). The lambda is invoked with the receiver's
        // remaining lines as a `Sequence<String>`, and the reader is closed before
        // the function returns. We model the lambda parameter as `List<String>` for
        // parity with the existing `File.useLines` stub — both flow through the same
        // runtime helper shape (lines materialised eagerly into a `RuntimeListBox`).
        let listOfStringToAnyTypeBR = types.make(.functionType(FunctionType(
            params: [listOfStringType],
            returnType: types.anyType,
            isSuspend: false,
            nullability: .nonNull
        )))
        registerFileMemberFunction(
            named: "useLines",
            externalLinkName: "kk_buffered_reader_useLines",
            ownerSymbol: bufferedReaderSymbol,
            ownerType: bufferedReaderType,
            parameters: [("block", listOfStringToAnyTypeBR)],
            returnType: types.anyType,
            symbols: symbols,
            interner: interner
        )

        // BufferedReader.forEachLine { line: String -> Unit } (STDLIB-IO-FN-017)
        //
        // Kotlin declares `forEachLine` as an extension function on `kotlin.io.Reader`
        // (which `BufferedReader` extends). The lambda receives each line as a `String`
        // and returns `Unit`. We model it as a member of `java.io.BufferedReader` so
        // user code can call `file.bufferedReader().forEachLine { line -> ... }`.
        // Unlike `useLines`, the reader is NOT automatically closed after iteration.
        registerFileMemberFunction(
            named: "forEachLine",
            externalLinkName: "kk_buffered_reader_forEachLine",
            ownerSymbol: bufferedReaderSymbol,
            ownerType: bufferedReaderType,
            parameters: [("action", stringToUnitType)],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )

        // MARK: - BufferedWriter type and File.bufferedWriter() (STDLIB-IO-091/093)

        let writerSymbol = ensureClassSymbol(
            named: "Writer",
            in: javaIOPkg,
            symbols: symbols,
            interner: interner
        )
        let bufferedWriterSymbol = ensureClassSymbol(
            named: "BufferedWriter",
            in: javaIOPkg,
            symbols: symbols,
            interner: interner
        )
        if let javaIOPkgSymbol {
            symbols.setParentSymbol(javaIOPkgSymbol, for: writerSymbol)
            symbols.setParentSymbol(javaIOPkgSymbol, for: bufferedWriterSymbol)
        }
        let writerType = types.make(.classType(ClassType(
            classSymbol: writerSymbol, args: [], nullability: .nonNull
        )))
        let bufferedWriterType = types.make(.classType(ClassType(
            classSymbol: bufferedWriterSymbol, args: [], nullability: .nonNull
        )))
        symbols.setPropertyType(writerType, for: writerSymbol)
        symbols.setPropertyType(bufferedWriterType, for: bufferedWriterSymbol)

        // Register BufferedWriter as a Closeable subtype (STDLIB-IO-093)
        if let closeableSymbol = types.closeableInterfaceSymbol {
            symbols.setDirectSupertypes([closeableSymbol], for: writerSymbol)
            types.setNominalDirectSupertypes([closeableSymbol], for: writerSymbol)
            symbols.setDirectSupertypes([writerSymbol, closeableSymbol], for: bufferedWriterSymbol)
            types.setNominalDirectSupertypes([writerSymbol, closeableSymbol], for: bufferedWriterSymbol)
        } else {
            symbols.setDirectSupertypes([writerSymbol], for: bufferedWriterSymbol)
            types.setNominalDirectSupertypes([writerSymbol], for: bufferedWriterSymbol)
        }

        // File.bufferedWriter() -> BufferedWriter
        registerFileMemberFunction(
            named: "bufferedWriter",
            externalLinkName: "kk_file_bufferedWriter",
            ownerSymbol: fileSymbol,
            ownerType: fileType,
            parameters: [],
            returnType: bufferedWriterType,
            symbols: symbols,
            interner: interner
        )

        // BufferedWriter.write(text: String) -> Unit
        registerFileMemberFunction(
            named: "write",
            externalLinkName: "kk_buffered_writer_write",
            ownerSymbol: bufferedWriterSymbol,
            ownerType: bufferedWriterType,
            parameters: [("text", types.stringType)],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )

        // BufferedWriter.newLine() -> Unit
        registerFileMemberFunction(
            named: "newLine",
            externalLinkName: "kk_buffered_writer_new_line",
            ownerSymbol: bufferedWriterSymbol,
            ownerType: bufferedWriterType,
            parameters: [],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )

        // BufferedWriter.flush() -> Unit
        registerFileMemberFunction(
            named: "flush",
            externalLinkName: "kk_buffered_writer_flush",
            ownerSymbol: bufferedWriterSymbol,
            ownerType: bufferedWriterType,
            parameters: [],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )

        // BufferedWriter.close() -> Unit
        registerFileMemberFunction(
            named: "close",
            externalLinkName: "kk_buffered_writer_close",
            ownerSymbol: bufferedWriterSymbol,
            ownerType: bufferedWriterType,
            parameters: [],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )

        // MARK: - InputStream / OutputStream (STDLIB-IO-092)

        // MARK: - Resource access (STDLIB-IO-093)

        let javaLangPkg = ensurePackage(
            path: ["java", "lang"],
            symbols: symbols,
            interner: interner
        )
        let javaLangPkgSymbol = symbols.lookup(fqName: javaLangPkg)
        let classLoaderSymbol = ensureClassSymbol(
            named: "ClassLoader",
            in: javaLangPkg,
            symbols: symbols,
            interner: interner
        )
        if let javaLangPkgSymbol {
            symbols.setParentSymbol(javaLangPkgSymbol, for: classLoaderSymbol)
        }
        let classLoaderType = types.make(.classType(ClassType(
            classSymbol: classLoaderSymbol, args: [], nullability: .nonNull
        )))
        symbols.setPropertyType(classLoaderType, for: classLoaderSymbol)

        let inputStreamSymbol = ensureClassSymbol(
            named: "InputStream",
            in: javaIOPkg,
            symbols: symbols,
            interner: interner
        )
        let byteArrayInputStreamSymbol = ensureClassSymbol(
            named: "ByteArrayInputStream",
            in: javaIOPkg,
            symbols: symbols,
            interner: interner
        )
        let sequenceInputStreamSymbol = ensureClassSymbol(
            named: "SequenceInputStream",
            in: javaIOPkg,
            symbols: symbols,
            interner: interner
        )
        let outputStreamSymbol = ensureClassSymbol(
            named: "OutputStream",
            in: javaIOPkg,
            symbols: symbols,
            interner: interner
        )
        if let javaIOPkgSymbol {
            symbols.setParentSymbol(javaIOPkgSymbol, for: inputStreamSymbol)
            symbols.setParentSymbol(javaIOPkgSymbol, for: byteArrayInputStreamSymbol)
            symbols.setParentSymbol(javaIOPkgSymbol, for: sequenceInputStreamSymbol)
            symbols.setParentSymbol(javaIOPkgSymbol, for: outputStreamSymbol)
        }

        let inputStreamType = types.make(.classType(ClassType(
            classSymbol: inputStreamSymbol, args: [], nullability: .nonNull
        )))
        let byteArrayInputStreamType = types.make(.classType(ClassType(
            classSymbol: byteArrayInputStreamSymbol, args: [], nullability: .nonNull
        )))
        let sequenceInputStreamType = types.make(.classType(ClassType(
            classSymbol: sequenceInputStreamSymbol, args: [], nullability: .nonNull
        )))
        let outputStreamType = types.make(.classType(ClassType(
            classSymbol: outputStreamSymbol, args: [], nullability: .nonNull
        )))
        symbols.setPropertyType(inputStreamType, for: inputStreamSymbol)
        symbols.setPropertyType(byteArrayInputStreamType, for: byteArrayInputStreamSymbol)
        symbols.setPropertyType(sequenceInputStreamType, for: sequenceInputStreamSymbol)
        symbols.setPropertyType(outputStreamType, for: outputStreamSymbol)

        // Register InputStream/OutputStream as Closeable subtypes (STDLIB-IO-093)
        // so that .use {} works with stream resources.
        if let closeableSymbol = types.closeableInterfaceSymbol {
            symbols.setDirectSupertypes([closeableSymbol], for: inputStreamSymbol)
            types.setNominalDirectSupertypes([closeableSymbol], for: inputStreamSymbol)
            symbols.setDirectSupertypes([closeableSymbol], for: outputStreamSymbol)
            types.setNominalDirectSupertypes([closeableSymbol], for: outputStreamSymbol)
        }
        symbols.setDirectSupertypes([inputStreamSymbol], for: sequenceInputStreamSymbol)
        types.setNominalDirectSupertypes([inputStreamSymbol], for: sequenceInputStreamSymbol)
        symbols.setDirectSupertypes([inputStreamSymbol], for: byteArrayInputStreamSymbol)
        types.setNominalDirectSupertypes([inputStreamSymbol], for: byteArrayInputStreamSymbol)
        let nullableInputStreamType = types.makeNullable(inputStreamType)
        let listIntType: TypeID = if let listSym = listSymbol {
            types.make(.classType(ClassType(
                classSymbol: listSym,
                args: [.out(types.intType)],
                nullability: .nonNull
            )))
        } else {
            types.anyType
        }

        registerFileMemberFunction(
            named: "inputStream",
            externalLinkName: "kk_file_inputStream",
            ownerSymbol: fileSymbol,
            ownerType: fileType,
            parameters: [],
            returnType: inputStreamType,
            symbols: symbols,
            interner: interner
        )

        registerFileMemberFunction(
            named: "outputStream",
            externalLinkName: "kk_file_outputStream",
            ownerSymbol: fileSymbol,
            ownerType: fileType,
            parameters: [],
            returnType: outputStreamType,
            symbols: symbols,
            interner: interner
        )

        registerFileConstructor(
            ownerSymbol: sequenceInputStreamSymbol,
            ownerType: sequenceInputStreamType,
            parameters: [("first", inputStreamType), ("second", inputStreamType)],
            externalLinkName: "kk_sequence_input_stream_new",
            symbols: symbols,
            interner: interner
        )

        registerFileConstructor(
            ownerSymbol: byteArrayInputStreamSymbol,
            ownerType: byteArrayInputStreamType,
            parameters: [("buffer", listIntType)],
            externalLinkName: "kk_bytearrayinputstream_new",
            symbols: symbols,
            interner: interner
        )

        // STDLIB-IO-FN-011: String.byteInputStream(charset: Charset = Charsets.UTF_8): ByteArrayInputStream
        // Lives in kotlin.io as an extension function on String. Two overloads are
        // exposed so callers can resolve both `value.byteInputStream()` and
        // `value.byteInputStream(Charsets.UTF_16)` without relying on default-argument
        // synthesis. ByteArrayInputStream → InputStream → Closeable, so the return
        // type carries `.use {}` compatibility through existing supertype wiring.
        let kotlinIOPkg = ensureSyntheticPackageHierarchy(
            fqName: [interner.intern("kotlin"), interner.intern("io")],
            symbols: symbols
        )
        let kotlinTextPkg: [InternedString] = [interner.intern("kotlin"), interner.intern("text")]
        let charsetFQName = kotlinTextPkg + [interner.intern("Charset")]
        if let charsetSymbol = symbols.lookup(fqName: charsetFQName) {
            let charsetType = types.make(.classType(ClassType(
                classSymbol: charsetSymbol, args: [], nullability: .nonNull
            )))
            registerSyntheticStringExtensionFunction(
                named: "byteInputStream",
                externalLinkName: "kk_string_byteInputStream",
                receiverType: types.stringType,
                parameters: [],
                returnType: byteArrayInputStreamType,
                packageFQName: kotlinIOPkg,
                symbols: symbols,
                interner: interner
            )
            registerSyntheticStringExtensionFunction(
                named: "byteInputStream",
                externalLinkName: "kk_string_byteInputStream_charset",
                receiverType: types.stringType,
                parameters: [
                    ("charset", charsetType, false, false),
                ],
                returnType: byteArrayInputStreamType,
                packageFQName: kotlinIOPkg,
                symbols: symbols,
                interner: interner
            )
        }

        registerFileMemberFunction(
            named: "read",
            externalLinkName: "kk_input_stream_read",
            ownerSymbol: inputStreamSymbol,
            ownerType: inputStreamType,
            parameters: [],
            returnType: intType,
            symbols: symbols,
            interner: interner
        )

        registerFileMemberFunction(
            named: "available",
            externalLinkName: "kk_input_stream_available",
            ownerSymbol: inputStreamSymbol,
            ownerType: inputStreamType,
            parameters: [],
            returnType: intType,
            symbols: symbols,
            interner: interner
        )

        registerFileMemberFunction(
            named: "skip",
            externalLinkName: "kk_input_stream_skip",
            ownerSymbol: inputStreamSymbol,
            ownerType: inputStreamType,
            parameters: [("count", intType)],
            returnType: intType,
            symbols: symbols,
            interner: interner
        )

        registerFileMemberFunction(
            named: "read",
            externalLinkName: "kk_input_stream_read_bytes",
            ownerSymbol: inputStreamSymbol,
            ownerType: inputStreamType,
            parameters: [("buffer", listOfIntType)],
            returnType: intType,
            symbols: symbols,
            interner: interner
        )

        registerFileMemberFunction(
            named: "mark",
            externalLinkName: "kk_input_stream_mark",
            ownerSymbol: inputStreamSymbol,
            ownerType: inputStreamType,
            parameters: [("readLimit", intType)],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )

        registerFileMemberFunction(
            named: "reset",
            externalLinkName: "kk_input_stream_reset",
            ownerSymbol: inputStreamSymbol,
            ownerType: inputStreamType,
            parameters: [],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )

        registerFileMemberFunction(
            named: "markSupported",
            externalLinkName: "kk_input_stream_mark_supported",
            ownerSymbol: inputStreamSymbol,
            ownerType: inputStreamType,
            parameters: [],
            returnType: types.booleanType,
            symbols: symbols,
            interner: interner
        )

        registerFileMemberFunction(
            named: "close",
            externalLinkName: "kk_input_stream_close",
            ownerSymbol: inputStreamSymbol,
            ownerType: inputStreamType,
            parameters: [],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )

        // MARK: - BufferedInputStream and InputStream.buffered() (STDLIB-IO-FN-003)
        //
        // Kotlin defines:
        //   public inline fun InputStream.buffered(bufferSize: Int = DEFAULT_BUFFER_SIZE): BufferedInputStream
        // We model BufferedInputStream as a java.io.InputStream subtype and expose
        // both the zero-arg and bufferSize overloads as member-style synthetic stubs
        // on InputStream so user code can call `inputStream.buffered()` or
        // `inputStream.buffered(8 * 1024)` and receive a BufferedInputStream value.
        let bufferedInputStreamSymbol = ensureClassSymbol(
            named: "BufferedInputStream",
            in: javaIOPkg,
            symbols: symbols,
            interner: interner
        )
        if let javaIOPkgSymbol {
            symbols.setParentSymbol(javaIOPkgSymbol, for: bufferedInputStreamSymbol)
        }
        let bufferedInputStreamType = types.make(.classType(ClassType(
            classSymbol: bufferedInputStreamSymbol, args: [], nullability: .nonNull
        )))
        symbols.setPropertyType(bufferedInputStreamType, for: bufferedInputStreamSymbol)

        // BufferedInputStream extends InputStream so it inherits Closeable + read/skip/etc.
        symbols.setDirectSupertypes([inputStreamSymbol], for: bufferedInputStreamSymbol)
        types.setNominalDirectSupertypes([inputStreamSymbol], for: bufferedInputStreamSymbol)

        // InputStream.buffered() -> BufferedInputStream (uses DEFAULT_BUFFER_SIZE = 8 * 1024)
        registerFileMemberFunction(
            named: "buffered",
            externalLinkName: "kk_input_stream_buffered_default",
            ownerSymbol: inputStreamSymbol,
            ownerType: inputStreamType,
            parameters: [],
            returnType: bufferedInputStreamType,
            symbols: symbols,
            interner: interner
        )

        // InputStream.buffered(bufferSize: Int) -> BufferedInputStream
        registerFileMemberFunction(
            named: "buffered",
            externalLinkName: "kk_input_stream_buffered",
            ownerSymbol: inputStreamSymbol,
            ownerType: inputStreamType,
            parameters: [("bufferSize", intType)],
            returnType: bufferedInputStreamType,
            symbols: symbols,
            interner: interner
        )

        // STDLIB-IO-FN-013: InputStream.copyTo(out, bufferSize) -> Long
        //
        // Kotlin signature:
        //   public fun InputStream.copyTo(
        //       out: OutputStream,
        //       bufferSize: Int = DEFAULT_BUFFER_SIZE
        //   ): Long
        //
        // Registered as a kotlin.io extension function on InputStream.
        // Two overloads: one with an explicit bufferSize and one that
        // relies on the default (DEFAULT_BUFFER_SIZE = 8 * 1024).
        registerKotlinIOExtensionFunction(
            named: "copyTo",
            packageFQName: kotlinIOPkg,
            receiverType: inputStreamType,
            parameters: [
                ("out", outputStreamType),
                ("bufferSize", types.intType),
            ],
            returnType: types.longType,
            externalLinkName: "kk_input_stream_copyTo",
            valueParameterHasDefaultValues: [false, true],
            valueParameterIsVararg: [false, false],
            symbols: symbols,
            interner: interner
        )

        registerFileMemberFunction(
            named: "read",
            externalLinkName: "kk_sequence_input_stream_read",
            ownerSymbol: sequenceInputStreamSymbol,
            ownerType: sequenceInputStreamType,
            parameters: [],
            returnType: intType,
            symbols: symbols,
            interner: interner
        )

        registerFileMemberFunction(
            named: "available",
            externalLinkName: "kk_sequence_input_stream_available",
            ownerSymbol: sequenceInputStreamSymbol,
            ownerType: sequenceInputStreamType,
            parameters: [],
            returnType: intType,
            symbols: symbols,
            interner: interner
        )

        registerFileMemberFunction(
            named: "close",
            externalLinkName: "kk_sequence_input_stream_close",
            ownerSymbol: sequenceInputStreamSymbol,
            ownerType: sequenceInputStreamType,
            parameters: [],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )

        registerFileMemberFunction(
            named: "write",
            externalLinkName: "kk_output_stream_write_byte",
            ownerSymbol: outputStreamSymbol,
            ownerType: outputStreamType,
            parameters: [("value", intType)],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )

        registerFileMemberFunction(
            named: "write",
            externalLinkName: "kk_output_stream_write_bytes",
            ownerSymbol: outputStreamSymbol,
            ownerType: outputStreamType,
            parameters: [("buffer", listOfIntType)],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )

        registerFileMemberFunction(
            named: "flush",
            externalLinkName: "kk_output_stream_flush",
            ownerSymbol: outputStreamSymbol,
            ownerType: outputStreamType,
            parameters: [],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )

        registerFileMemberFunction(
            named: "close",
            externalLinkName: "kk_output_stream_close",
            ownerSymbol: outputStreamSymbol,
            ownerType: outputStreamType,
            parameters: [],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )

        // STDLIB-IO-FN-004: OutputStream.buffered() / buffered(bufferSize) extension members.
        // Returns an OutputStream that wraps the receiver with buffering. The runtime
        // implementation is identity-compatible: the underlying RuntimeOutputStreamBox
        // already streams through the OS, so the wrapped handle is the same instance.
        // This satisfies Kotlin's `fun OutputStream.buffered(bufferSize: Int = DEFAULT_BUFFER_SIZE): BufferedOutputStream`
        // contract at the Sema surface — callers can chain `.write(...)` / `.flush()` / `.close()` etc.
        registerFileMemberFunction(
            named: "buffered",
            externalLinkName: "kk_output_stream_buffered",
            ownerSymbol: outputStreamSymbol,
            ownerType: outputStreamType,
            parameters: [],
            returnType: outputStreamType,
            symbols: symbols,
            interner: interner
        )

        registerFileMemberFunction(
            named: "buffered",
            externalLinkName: "kk_output_stream_buffered_sized",
            ownerSymbol: outputStreamSymbol,
            ownerType: outputStreamType,
            parameters: [("bufferSize", intType)],
            returnType: outputStreamType,
            symbols: symbols,
            interner: interner
        )

        // ClassLoader resource access functions (STDLIB-IO-093)

        registerFileMemberFunction(
            named: "getResource",
            externalLinkName: "kk_classloader_getResource",
            ownerSymbol: classLoaderSymbol,
            ownerType: classLoaderType,
            parameters: [("name", types.stringType)],
            returnType: nullableStringType,
            symbols: symbols,
            interner: interner
        )

        registerFileMemberFunction(
            named: "getResourceAsStream",
            externalLinkName: "kk_classloader_getResourceAsStream",
            ownerSymbol: classLoaderSymbol,
            ownerType: classLoaderType,
            parameters: [("name", types.stringType)],
            returnType: nullableInputStreamType,
            symbols: symbols,
            interner: interner
        )

        registerTopLevelResourceFunction(
            packageFQName: javaLangPkg,
            name: "getSystemClassLoader",
            parameters: [],
            returnType: classLoaderType,
            externalLinkName: "kk_classloader_getSystemClassLoader",
            symbols: symbols,
            interner: interner
        )

        registerTopLevelResourceFunction(
            packageFQName: kotlinIOPkg,
            name: "resourceExists",
            parameters: [("name", types.stringType)],
            returnType: types.booleanType,
            externalLinkName: "kk_resource_exists",
            symbols: symbols,
            interner: interner
        )
        registerTopLevelResourceFunction(
            packageFQName: kotlinIOPkg,
            name: "readResourceAsText",
            parameters: [("name", types.stringType)],
            returnType: types.stringType,
            externalLinkName: "kk_readResourceAsText",
            symbols: symbols,
            interner: interner
        )

        // MARK: - File.invariantSeparatorsPath (STDLIB-IO-PROP-003)
        //
        // Kotlin signature: `public val File.invariantSeparatorsPath: String`
        // declared in the `kotlin.io` package.  Returns the file path with the
        // platform-specific separator replaced by a forward slash `/`.
        registerKotlinIOExtensionProperty(
            named: "invariantSeparatorsPath",
            packageFQName: kotlinIOPkg,
            receiverType: fileType,
            returnType: types.stringType,
            externalLinkName: "kk_file_invariantSeparatorsPath",
            symbols: symbols,
            interner: interner
        )

        // MARK: - OutputStream.bufferedWriter(charset) (STDLIB-IO-FN-009)
        //
        // Kotlin signature: `public fun OutputStream.bufferedWriter(
        //     charset: Charset = Charsets.UTF_8
        // ): BufferedWriter`  declared in the `kotlin.io` package.
        let kotlinTextPkgFQName = ensurePackage(
            path: ["kotlin", "text"],
            symbols: symbols,
            interner: interner
        )
        let kotlinTextPkgSymbol = symbols.lookup(fqName: kotlinTextPkgFQName)
        let outputStreamCharsetSymbol = ensureClassSymbol(
            named: "Charset",
            in: kotlinTextPkgFQName,
            symbols: symbols,
            interner: interner
        )
        if let kotlinTextPkgSymbol {
            symbols.setParentSymbol(kotlinTextPkgSymbol, for: outputStreamCharsetSymbol)
        }
        let outputStreamCharsetType = types.make(.classType(ClassType(
            classSymbol: outputStreamCharsetSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(outputStreamCharsetType, for: outputStreamCharsetSymbol)

        registerKotlinIOExtensionFunction(
            named: "bufferedWriter",
            packageFQName: kotlinIOPkg,
            receiverType: outputStreamType,
            parameters: [("charset", outputStreamCharsetType)],
            returnType: bufferedWriterType,
            externalLinkName: "kk_output_stream_bufferedWriter",
            valueParameterHasDefaultValues: [true],
            valueParameterIsVararg: [false],
            symbols: symbols,
            interner: interner
        )

        // MARK: - PrintWriter type and File.printWriter() (STDLIB-IO-FN-027)

        let printWriterSymbol = ensureClassSymbol(
            named: "PrintWriter",
            in: javaIOPkg,
            symbols: symbols,
            interner: interner
        )
        if let javaIOPkgSymbol {
            symbols.setParentSymbol(javaIOPkgSymbol, for: printWriterSymbol)
        }
        let printWriterType = types.make(.classType(ClassType(
            classSymbol: printWriterSymbol, args: [], nullability: .nonNull
        )))
        symbols.setPropertyType(printWriterType, for: printWriterSymbol)

        // Register PrintWriter as a Closeable subtype so that .use {} works
        if let closeableSymbol = types.closeableInterfaceSymbol {
            symbols.setDirectSupertypes([closeableSymbol], for: printWriterSymbol)
            types.setNominalDirectSupertypes([closeableSymbol], for: printWriterSymbol)
        }

        // File.printWriter() -> PrintWriter
        registerFileMemberFunction(
            named: "printWriter",
            externalLinkName: "kk_file_printWriter",
            ownerSymbol: fileSymbol,
            ownerType: fileType,
            parameters: [],
            returnType: printWriterType,
            symbols: symbols,
            interner: interner
        )

        // PrintWriter.print(text: String) -> Unit
        registerFileMemberFunction(
            named: "print",
            externalLinkName: "kk_print_writer_print",
            ownerSymbol: printWriterSymbol,
            ownerType: printWriterType,
            parameters: [("text", types.stringType)],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )

        // PrintWriter.println(text: String) -> Unit
        registerFileMemberFunction(
            named: "println",
            externalLinkName: "kk_print_writer_println",
            ownerSymbol: printWriterSymbol,
            ownerType: printWriterType,
            parameters: [("text", types.stringType)],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )

        // PrintWriter.println() -> Unit  (no-arg overload)
        registerFileMemberFunction(
            named: "println",
            externalLinkName: "kk_print_writer_println_no_arg",
            ownerSymbol: printWriterSymbol,
            ownerType: printWriterType,
            parameters: [],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )

        // PrintWriter.write(text: String) -> Unit
        registerFileMemberFunction(
            named: "write",
            externalLinkName: "kk_print_writer_write",
            ownerSymbol: printWriterSymbol,
            ownerType: printWriterType,
            parameters: [("text", types.stringType)],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )

        // PrintWriter.flush() -> Unit
        registerFileMemberFunction(
            named: "flush",
            externalLinkName: "kk_print_writer_flush",
            ownerSymbol: printWriterSymbol,
            ownerType: printWriterType,
            parameters: [],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )

        // PrintWriter.close() -> Unit
        registerFileMemberFunction(
            named: "close",
            externalLinkName: "kk_print_writer_close",
            ownerSymbol: printWriterSymbol,
            ownerType: printWriterType,
            parameters: [],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )

        // MARK: - File.copyTo(target, overwrite, bufferSize) (STDLIB-IO-FN-015)
        //
        // Kotlin signature: `public fun File.copyTo(
        //     target: File,
        //     overwrite: Boolean = false,
        //     bufferSize: Int = DEFAULT_BUFFER_SIZE
        // ): File` declared in the `kotlin.io` package.
        registerKotlinIOExtensionFunction(
            named: "copyTo",
            packageFQName: kotlinIOPkg,
            receiverType: fileType,
            parameters: [
                ("target", fileType),
                ("overwrite", types.booleanType),
                ("bufferSize", types.intType),
            ],
            returnType: fileType,
            externalLinkName: "kk_file_copyTo",
            valueParameterHasDefaultValues: [false, true, true],
            valueParameterIsVararg: [false, false, false],
            symbols: symbols,
            interner: interner
        )

        // MARK: - Reader.readText() (STDLIB-IO-FN-033)
        //
        // Kotlin signature: `public fun Reader.readText(): String` declared in
        // the `kotlin.io` package. Reads the entire remaining content of the
        // receiver into a single `String`. Mirrors the stdlib semantics of
        // exhausting the reader; the runtime helper `kk_reader_readText`
        // delegates to `RuntimeBufferedReaderBox.readText()`.
        registerKotlinIOExtensionFunction(
            named: "readText",
            packageFQName: kotlinIOPkg,
            receiverType: readerType,
            parameters: [],
            returnType: types.stringType,
            externalLinkName: "kk_reader_readText",
            symbols: symbols,
            interner: interner
        )

        // MARK: - ByteArray.inputStream() and ByteArray.inputStream(offset, length) (STDLIB-IO-FN-020 / STDLIB-IO-FN-021)
        //
        // Kotlin stdlib declares two overloads in kotlin.io:
        //   fun ByteArray.inputStream(): ByteArrayInputStream
        //   fun ByteArray.inputStream(offset: Int, length: Int): ByteArrayInputStream
        //
        // We register both on the ByteArray class symbol so that extension-receiver
        // resolution succeeds for both `bytes.inputStream()` and
        // `bytes.inputStream(offset, length)`.
        if let byteArraySymbol = symbols.lookup(fqName: byteArrayFQName) {
            let byteArrayType = types.make(.classType(ClassType(
                classSymbol: byteArraySymbol, args: [], nullability: .nonNull
            )))

            // STDLIB-IO-FN-020: ByteArray.inputStream() -> ByteArrayInputStream
            registerSyntheticStringExtensionFunction(
                named: "inputStream",
                externalLinkName: "kk_bytearray_inputStream",
                receiverType: byteArrayType,
                parameters: [],
                returnType: byteArrayInputStreamType,
                packageFQName: kotlinIOPkg,
                symbols: symbols,
                interner: interner
            )

            // STDLIB-IO-FN-021: ByteArray.inputStream(offset: Int, length: Int) -> ByteArrayInputStream
            registerSyntheticStringExtensionFunction(
                named: "inputStream",
                externalLinkName: "kk_bytearray_inputStream_range",
                receiverType: byteArrayType,
                parameters: [
                    ("offset", types.intType, false, false),
                    ("length", types.intType, false, false),
                ],
                returnType: byteArrayInputStreamType,
                packageFQName: kotlinIOPkg,
                symbols: symbols,
                interner: interner
            )
        }

        // MARK: - kotlin.io.Writer.buffered (STDLIB-IO-FN-006)
        // Writer.buffered(): BufferedWriter
        // Writer.buffered(bufferSize: Int): BufferedWriter
        registerFilePackageExtensionFunction(
            named: "buffered",
            packageFQName: kotlinIOPkg,
            receiverType: writerType,
            parameters: [],
            returnType: bufferedWriterType,
            externalLinkName: "kk_writer_buffered_default",
            symbols: symbols,
            interner: interner
        )
        registerFilePackageExtensionFunction(
            named: "buffered",
            packageFQName: kotlinIOPkg,
            receiverType: writerType,
            parameters: [("bufferSize", intType)],
            returnType: bufferedWriterType,
            externalLinkName: "kk_writer_buffered",
            symbols: symbols,
            interner: interner
        )


        // STDLIB-IO-FN-007: kotlin.io.InputStream.bufferedReader(charset)
        // Top-level extension function on java.io.InputStream returning BufferedReader.
        // Signature: fun InputStream.bufferedReader(charset: Charset = Charsets.UTF_8): BufferedReader
        let charsetFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("text"),
            interner.intern("Charset"),
        ]
        let resolvedCharsetType: TypeID = {
            if let charsetSymbol = symbols.lookup(fqName: charsetFQName) {
                return types.make(.classType(ClassType(
                    classSymbol: charsetSymbol,
                    args: [],
                    nullability: .nonNull
                )))
            }
            return types.anyType
        }()

        registerExtensionFunction(
            named: "bufferedReader",
            packageFQName: kotlinIOPkg,
            receiverType: inputStreamType,
            parameters: [("charset", resolvedCharsetType)],
            returnType: bufferedReaderType,
            externalLinkName: "kk_input_stream_bufferedReader",
            valueParameterHasDefaultValues: [true],
            symbols: symbols,
            interner: interner
        )
    }

    // MARK: - Private Helpers

    private func resolveListSymbol(
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

    private func registerFileConstructor(
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

    /// Registers a top-level extension function in a Kotlin package
    /// (e.g. `kotlin.io`) whose receiver is a class symbol such as
    /// `java.io.OutputStream`.  Used for stdlib extensions like
    /// `OutputStream.bufferedWriter(charset)` (STDLIB-IO-FN-009).
    private func registerKotlinIOExtensionFunction(
        named name: String,
        packageFQName: [InternedString],
        receiverType: TypeID,
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
            return existingSignature.receiverType == receiverType
                && existingSignature.parameterTypes == parameterTypes
        }) {
            symbols.setExternalLinkName(externalLinkName, for: existing)
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
            flags: [.synthetic]
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

    /// Registers a top-level extension property in a Kotlin package (e.g.
    /// `kotlin.io`) whose receiver is a class symbol such as `java.io.File`.
    /// Used for stdlib extensions like `File.invariantSeparatorsPath`
    /// (STDLIB-IO-PROP-003).
    private func registerKotlinIOExtensionProperty(
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

    private func registerFileMemberFunction(
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
            // Only overwrite synthetic symbols to avoid clobbering user/stdlib declarations
            guard let existingInfo = symbols.symbol(existing),
                  existingInfo.flags.contains(.synthetic) || existingInfo.declSite == nil else {
                return
            }
            symbols.setExternalLinkName(externalLinkName, for: existing)
            // Update the signature if the return type diverges from the intended type
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

    private func ensureJavaIOPackage(
        symbols: SymbolTable,
        interner: StringInterner
    ) -> [InternedString] {
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
        return javaIOPkg
    }

    /// Register a top-level Kotlin extension function in `packageFQName` with the
    /// provided receiver. Mirrors `registerPathExtensionFunction` from
    /// `HeaderHelpers+SyntheticPathStubs.swift`, scoped to FileIO so that
    /// extensions on `InputStream` / `OutputStream` can live next to the rest
    /// of the FileIO stubs without leaking helpers between extension files.
    private func registerExtensionFunction(
        named name: String,
        packageFQName: [InternedString],
        receiverType: TypeID,
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
            return existingSignature.receiverType == receiverType
                && existingSignature.parameterTypes == parameterTypes
        }) {
            symbols.setExternalLinkName(externalLinkName, for: existing)
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
            flags: [.synthetic]
        )
        if let pkgSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(pkgSymbol, for: functionSymbol)
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

    private func registerTopLevelResourceFunction(
        packageFQName: [InternedString],
        name: String,
        parameters: [(name: String, type: TypeID)],
        returnType: TypeID,
        externalLinkName: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let functionName = interner.intern(name)
        let functionFQName = packageFQName + [functionName]
        guard symbols.lookupAll(fqName: functionFQName).isEmpty else {
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
        if let pkgSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(pkgSymbol, for: functionSymbol)
        }
        symbols.setExternalLinkName(externalLinkName, for: functionSymbol)

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
            parameterSymbols.append(parameterSymbol)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: parameters.map(\.type),
                returnType: returnType,
                valueParameterSymbols: parameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: parameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: parameterSymbols.count)
            ),
            for: functionSymbol
        )
    }

    private func registerFileMemberProperty(
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
            // Only overwrite synthetic symbols to avoid clobbering user/stdlib declarations
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

    /// Registers a synthetic top-level extension function on a receiver type within
    /// a package (e.g. `kotlin.io.Writer.buffered()`).
    private func registerFilePackageExtensionFunction(
        named name: String,
        packageFQName: [InternedString],
        receiverType: TypeID,
        parameters: [(name: String, type: TypeID)],
        returnType: TypeID,
        externalLinkName: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let functionName = interner.intern(name)
        let functionFQName = packageFQName + [functionName]
        let parameterTypes = parameters.map(\.type)
        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let signature = symbols.functionSignature(for: symbolID) else { return false }
            return signature.receiverType == receiverType
                && signature.parameterTypes == parameterTypes
        }) {
            symbols.setExternalLinkName(externalLinkName, for: existing)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: parameterTypes,
                    returnType: returnType
                ),
                for: existing
            )
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
            parameterSymbols.append(parameterSymbol)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: parameterTypes,
                returnType: returnType,
                valueParameterSymbols: parameterSymbols,
                valueParameterHasDefaultValues: Array(repeating: false, count: parameters.count),
                valueParameterIsVararg: Array(repeating: false, count: parameters.count)
            ),
            for: functionSymbol
        )
    }

}
