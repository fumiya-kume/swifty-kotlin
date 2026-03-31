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

        // MARK: - BufferedReader type and File.bufferedReader() (STDLIB-567)

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
            classSymbol: bufferedReaderSymbol, args: [], nullability: .nonNull
        )))
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

        // Register BufferedReader as a Closeable subtype (STDLIB-IO-093)
        // so that .use {} pattern works: `file.bufferedReader().use { reader -> ... }`
        if let closeableSymbol = types.closeableInterfaceSymbol {
            symbols.setDirectSupertypes([closeableSymbol], for: bufferedReaderSymbol)
            types.setNominalDirectSupertypes([closeableSymbol], for: bufferedReaderSymbol)
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

        // MARK: - BufferedWriter type and File.bufferedWriter() (STDLIB-IO-091/093)

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
            classSymbol: bufferedWriterSymbol, args: [], nullability: .nonNull
        )))
        symbols.setPropertyType(bufferedWriterType, for: bufferedWriterSymbol)

        // Register BufferedWriter as a Closeable subtype (STDLIB-IO-093)
        if let closeableSymbol = types.closeableInterfaceSymbol {
            symbols.setDirectSupertypes([closeableSymbol], for: bufferedWriterSymbol)
            types.setNominalDirectSupertypes([closeableSymbol], for: bufferedWriterSymbol)
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
            symbols.setParentSymbol(javaIOPkgSymbol, for: sequenceInputStreamSymbol)
            symbols.setParentSymbol(javaIOPkgSymbol, for: outputStreamSymbol)
        }

        let inputStreamType = types.make(.classType(ClassType(
            classSymbol: inputStreamSymbol, args: [], nullability: .nonNull
        )))
        let sequenceInputStreamType = types.make(.classType(ClassType(
            classSymbol: sequenceInputStreamSymbol, args: [], nullability: .nonNull
        )))
        let outputStreamType = types.make(.classType(ClassType(
            classSymbol: outputStreamSymbol, args: [], nullability: .nonNull
        )))
        symbols.setPropertyType(inputStreamType, for: inputStreamSymbol)
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
        let nullableInputStreamType = types.makeNullable(inputStreamType)

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

        let kotlinIOPkg = ensurePackage(
            path: ["kotlin", "io"],
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
}
