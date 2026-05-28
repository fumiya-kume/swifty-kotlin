/// `RuntimeABISpec.fileIOFunctions` (STDLIB-320/321/322/323) extracted from
/// `RuntimeABISpec.swift`.
public extension RuntimeABISpec {
    // MARK: - File I/O (STDLIB-320/321/322/323)

    public static let fileIOFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_file_new",
            parameters: [
                RuntimeABIParameter(name: "pathRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_file_readText",
            parameters: [
                RuntimeABIParameter(name: "fileRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_file_writeText",
            parameters: [
                RuntimeABIParameter(name: "fileRaw", type: .intptr),
                RuntimeABIParameter(name: "textRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_file_appendText",
            parameters: [
                RuntimeABIParameter(name: "fileRaw", type: .intptr),
                RuntimeABIParameter(name: "textRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_file_readLines",
            parameters: [
                RuntimeABIParameter(name: "fileRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_file_readBytes",
            parameters: [
                RuntimeABIParameter(name: "fileRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_file_forEachLine",
            parameters: [
                RuntimeABIParameter(name: "fileRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_file_exists",
            parameters: [
                RuntimeABIParameter(name: "fileRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_file_isFile",
            parameters: [
                RuntimeABIParameter(name: "fileRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_file_isDirectory",
            parameters: [
                RuntimeABIParameter(name: "fileRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_file_name",
            parameters: [
                RuntimeABIParameter(name: "fileRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        // STDLIB-IO-PROP-005: File.nameWithoutExtension extension property
        RuntimeABIFunctionSpec(
            name: "kk_file_nameWithoutExtension",
            parameters: [
                RuntimeABIParameter(name: "fileRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_file_path",
            parameters: [
                RuntimeABIParameter(name: "fileRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_file_delete",
            parameters: [
                RuntimeABIParameter(name: "fileRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_file_mkdirs",
            parameters: [
                RuntimeABIParameter(name: "fileRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_file_listFiles",
            parameters: [
                RuntimeABIParameter(name: "fileRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_file_walk",
            parameters: [
                RuntimeABIParameter(name: "fileRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        // STDLIB-IO-FN-015: File.copyTo(target, overwrite, bufferSize)
        RuntimeABIFunctionSpec(
            name: "kk_file_copyTo",
            parameters: [
                RuntimeABIParameter(name: "fileRaw", type: .intptr),
                RuntimeABIParameter(name: "targetRaw", type: .intptr),
                RuntimeABIParameter(name: "overwriteRaw", type: .intptr),
                RuntimeABIParameter(name: "bufferSizeRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        // STDLIB-567: File.bufferedReader()
        RuntimeABIFunctionSpec(
            name: "kk_file_bufferedReader",
            parameters: [
                RuntimeABIParameter(name: "fileRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_buffered_reader_readLine",
            parameters: [
                RuntimeABIParameter(name: "readerRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_buffered_reader_readLines",
            parameters: [
                RuntimeABIParameter(name: "readerRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_buffered_reader_close",
            parameters: [
                RuntimeABIParameter(name: "readerRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        // STDLIB-IO-091: BufferedReader.read() / ready()
        RuntimeABIFunctionSpec(
            name: "kk_buffered_reader_read",
            parameters: [
                RuntimeABIParameter(name: "readerRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_buffered_reader_ready",
            parameters: [
                RuntimeABIParameter(name: "readerRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        // STDLIB-IO-FN-022: BufferedReader.iterator() -> Iterator<String>
        RuntimeABIFunctionSpec(
            name: "kk_buffered_reader_iterator",
            parameters: [
                RuntimeABIParameter(name: "readerRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        // STDLIB-IO-FN-040: Reader.useLines { lines -> T }
        RuntimeABIFunctionSpec(
            name: "kk_buffered_reader_useLines",
            parameters: [
                RuntimeABIParameter(name: "readerRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        // STDLIB-IO-091/093: BufferedWriter
        RuntimeABIFunctionSpec(
            name: "kk_file_bufferedWriter",
            parameters: [
                RuntimeABIParameter(name: "fileRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_buffered_writer_write",
            parameters: [
                RuntimeABIParameter(name: "writerRaw", type: .intptr),
                RuntimeABIParameter(name: "textRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_buffered_writer_new_line",
            parameters: [
                RuntimeABIParameter(name: "writerRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_buffered_writer_flush",
            parameters: [
                RuntimeABIParameter(name: "writerRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_buffered_writer_close",
            parameters: [
                RuntimeABIParameter(name: "writerRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_file_inputStream",
            parameters: [
                RuntimeABIParameter(name: "fileRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_file_outputStream",
            parameters: [
                RuntimeABIParameter(name: "fileRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_bytearrayinputstream_new",
            parameters: [
                RuntimeABIParameter(name: "bufferRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        // STDLIB-IO-FN-011: String.byteInputStream()
        RuntimeABIFunctionSpec(
            name: "kk_string_byteInputStream",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        // STDLIB-IO-FN-011: String.byteInputStream(charset: Charset)
        RuntimeABIFunctionSpec(
            name: "kk_string_byteInputStream_charset",
            parameters: [
                RuntimeABIParameter(name: "strRaw", type: .intptr),
                RuntimeABIParameter(name: "charsetTag", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_input_stream_read",
            parameters: [
                RuntimeABIParameter(name: "streamRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_input_stream_available",
            parameters: [
                RuntimeABIParameter(name: "streamRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_input_stream_skip",
            parameters: [
                RuntimeABIParameter(name: "streamRaw", type: .intptr),
                RuntimeABIParameter(name: "countRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_input_stream_read_bytes",
            parameters: [
                RuntimeABIParameter(name: "streamRaw", type: .intptr),
                RuntimeABIParameter(name: "bytesRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_input_stream_close",
            parameters: [
                RuntimeABIParameter(name: "streamRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        // STDLIB-IO-FN-003: InputStream.buffered(bufferSize) returning BufferedInputStream
        RuntimeABIFunctionSpec(
            name: "kk_input_stream_buffered_default",
            parameters: [
                RuntimeABIParameter(name: "streamRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_input_stream_buffered",
            parameters: [
                RuntimeABIParameter(name: "streamRaw", type: .intptr),
                RuntimeABIParameter(name: "bufferSizeRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        // STDLIB-IO-FN-013: InputStream.copyTo(out, bufferSize) -> Long
        RuntimeABIFunctionSpec(
            name: "kk_input_stream_copyTo",
            parameters: [
                RuntimeABIParameter(name: "streamRaw", type: .intptr),
                RuntimeABIParameter(name: "outStreamRaw", type: .intptr),
                RuntimeABIParameter(name: "bufferSizeRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_output_stream_write_byte",
            parameters: [
                RuntimeABIParameter(name: "streamRaw", type: .intptr),
                RuntimeABIParameter(name: "valueRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_output_stream_write_bytes",
            parameters: [
                RuntimeABIParameter(name: "streamRaw", type: .intptr),
                RuntimeABIParameter(name: "bytesRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_output_stream_flush",
            parameters: [
                RuntimeABIParameter(name: "streamRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_output_stream_close",
            parameters: [
                RuntimeABIParameter(name: "streamRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        // STDLIB-IO-FN-009: OutputStream.bufferedWriter(charset)
        RuntimeABIFunctionSpec(
            name: "kk_output_stream_bufferedWriter",
            parameters: [
                RuntimeABIParameter(name: "streamRaw", type: .intptr),
                RuntimeABIParameter(name: "charsetRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_output_stream_bufferedWriter_default",
            parameters: [
                RuntimeABIParameter(name: "streamRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_classloader_getSystemClassLoader",
            parameters: [],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_classloader_getResource",
            parameters: [
                RuntimeABIParameter(name: "loaderRaw", type: .intptr),
                RuntimeABIParameter(name: "nameRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_classloader_getResourceAsStream",
            parameters: [
                RuntimeABIParameter(name: "loaderRaw", type: .intptr),
                RuntimeABIParameter(name: "nameRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_resource_exists",
            parameters: [
                RuntimeABIParameter(name: "nameRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_readResourceAsText",
            parameters: [
                RuntimeABIParameter(name: "nameRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_resource_stream_read",
            parameters: [
                RuntimeABIParameter(name: "streamRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_resource_stream_close",
            parameters: [
                RuntimeABIParameter(name: "streamRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_file_useLines",
            parameters: [
                RuntimeABIParameter(name: "fileRaw", type: .intptr),
                RuntimeABIParameter(name: "fnPtr", type: .intptr),
                RuntimeABIParameter(name: "closureRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uri_new",
            parameters: [
                RuntimeABIParameter(name: "specRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(name: "kk_uri_toString", parameters: [RuntimeABIParameter(name: "uriRaw", type: .intptr)], returnType: .intptr, section: "FileIO"),
        RuntimeABIFunctionSpec(name: "kk_uri_scheme", parameters: [RuntimeABIParameter(name: "uriRaw", type: .intptr)], returnType: .intptr, section: "FileIO"),
        RuntimeABIFunctionSpec(name: "kk_uri_authority", parameters: [RuntimeABIParameter(name: "uriRaw", type: .intptr)], returnType: .intptr, section: "FileIO"),
        RuntimeABIFunctionSpec(name: "kk_uri_path", parameters: [RuntimeABIParameter(name: "uriRaw", type: .intptr)], returnType: .intptr, section: "FileIO"),
        RuntimeABIFunctionSpec(name: "kk_uri_query", parameters: [RuntimeABIParameter(name: "uriRaw", type: .intptr)], returnType: .intptr, section: "FileIO"),
        RuntimeABIFunctionSpec(name: "kk_uri_fragment", parameters: [RuntimeABIParameter(name: "uriRaw", type: .intptr)], returnType: .intptr, section: "FileIO"),
        RuntimeABIFunctionSpec(name: "kk_uri_normalize", parameters: [RuntimeABIParameter(name: "uriRaw", type: .intptr)], returnType: .intptr, section: "FileIO"),
        RuntimeABIFunctionSpec(
            name: "kk_uri_resolve",
            parameters: [
                RuntimeABIParameter(name: "baseRaw", type: .intptr),
                RuntimeABIParameter(name: "otherRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_uri_relativize",
            parameters: [
                RuntimeABIParameter(name: "baseRaw", type: .intptr),
                RuntimeABIParameter(name: "otherRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_url_new",
            parameters: [
                RuntimeABIParameter(name: "specRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_url_new_relative",
            parameters: [
                RuntimeABIParameter(name: "baseRaw", type: .intptr),
                RuntimeABIParameter(name: "relativeRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(name: "kk_url_protocol", parameters: [RuntimeABIParameter(name: "urlRaw", type: .intptr)], returnType: .intptr, section: "FileIO"),
        RuntimeABIFunctionSpec(name: "kk_url_host", parameters: [RuntimeABIParameter(name: "urlRaw", type: .intptr)], returnType: .intptr, section: "FileIO"),
        RuntimeABIFunctionSpec(name: "kk_url_port", parameters: [RuntimeABIParameter(name: "urlRaw", type: .intptr)], returnType: .intptr, section: "FileIO"),
        RuntimeABIFunctionSpec(name: "kk_url_path", parameters: [RuntimeABIParameter(name: "urlRaw", type: .intptr)], returnType: .intptr, section: "FileIO"),
        RuntimeABIFunctionSpec(name: "kk_url_query", parameters: [RuntimeABIParameter(name: "urlRaw", type: .intptr)], returnType: .intptr, section: "FileIO"),
        RuntimeABIFunctionSpec(name: "kk_url_fragment", parameters: [RuntimeABIParameter(name: "urlRaw", type: .intptr)], returnType: .intptr, section: "FileIO"),
        RuntimeABIFunctionSpec(
            name: "kk_url_toURI",
            parameters: [
                RuntimeABIParameter(name: "urlRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(name: "kk_url_toExternalForm", parameters: [RuntimeABIParameter(name: "urlRaw", type: .intptr)], returnType: .intptr, section: "FileIO"),
        RuntimeABIFunctionSpec(
            name: "kk_url_sameFile",
            parameters: [
                RuntimeABIParameter(name: "lhsRaw", type: .intptr),
                RuntimeABIParameter(name: "rhsRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_url_equals",
            parameters: [
                RuntimeABIParameter(name: "lhsRaw", type: .intptr),
                RuntimeABIParameter(name: "rhsRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(name: "kk_url_hashCode", parameters: [RuntimeABIParameter(name: "urlRaw", type: .intptr)], returnType: .intptr, section: "FileIO"),
        RuntimeABIFunctionSpec(name: "kk_url_encode", parameters: [RuntimeABIParameter(name: "valueRaw", type: .intptr)], returnType: .intptr, section: "FileIO"),
        RuntimeABIFunctionSpec(name: "kk_url_decode", parameters: [RuntimeABIParameter(name: "valueRaw", type: .intptr)], returnType: .intptr, section: "FileIO"),
        // STDLIB-IO-087: Additional File operations
        RuntimeABIFunctionSpec(
            name: "kk_file_new_parent_child",
            parameters: [
                RuntimeABIParameter(name: "parentRaw", type: .intptr),
                RuntimeABIParameter(name: "childRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_file_absolutePath",
            parameters: [
                RuntimeABIParameter(name: "fileRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_file_canonicalPath",
            parameters: [
                RuntimeABIParameter(name: "fileRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_file_parent",
            parameters: [
                RuntimeABIParameter(name: "fileRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_file_invariantSeparatorsPath",
            parameters: [
                RuntimeABIParameter(name: "fileRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_file_length",
            parameters: [
                RuntimeABIParameter(name: "fileRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_file_lastModified",
            parameters: [
                RuntimeABIParameter(name: "fileRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_file_createNewFile",
            parameters: [
                RuntimeABIParameter(name: "fileRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_file_canRead",
            parameters: [
                RuntimeABIParameter(name: "fileRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_file_canWrite",
            parameters: [
                RuntimeABIParameter(name: "fileRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_file_canExecute",
            parameters: [
                RuntimeABIParameter(name: "fileRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_file_startsWith_file",
            parameters: [
                RuntimeABIParameter(name: "fileRaw", type: .intptr),
                RuntimeABIParameter(name: "otherRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_file_startsWith_string",
            parameters: [
                RuntimeABIParameter(name: "fileRaw", type: .intptr),
                RuntimeABIParameter(name: "otherRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(name: "kk_logger_getLogger", parameters: [RuntimeABIParameter(name: "nameRaw", type: .intptr)], returnType: .intptr, section: "FileIO"),
        RuntimeABIFunctionSpec(name: "kk_logging_level_info", parameters: [], returnType: .intptr, section: "FileIO"),
        RuntimeABIFunctionSpec(name: "kk_logging_level_config", parameters: [], returnType: .intptr, section: "FileIO"),
        RuntimeABIFunctionSpec(name: "kk_logging_level_fine", parameters: [], returnType: .intptr, section: "FileIO"),
        RuntimeABIFunctionSpec(name: "kk_logging_level_finer", parameters: [], returnType: .intptr, section: "FileIO"),
        RuntimeABIFunctionSpec(name: "kk_logging_level_finest", parameters: [], returnType: .intptr, section: "FileIO"),
        RuntimeABIFunctionSpec(name: "kk_logging_level_warning", parameters: [], returnType: .intptr, section: "FileIO"),
        RuntimeABIFunctionSpec(name: "kk_logging_level_severe", parameters: [], returnType: .intptr, section: "FileIO"),
        RuntimeABIFunctionSpec(name: "kk_console_handler_new", parameters: [], returnType: .intptr, section: "FileIO"),
        RuntimeABIFunctionSpec(name: "kk_file_handler_new", parameters: [RuntimeABIParameter(name: "pathRaw", type: .intptr)], returnType: .intptr, section: "FileIO"),
        RuntimeABIFunctionSpec(name: "kk_logger_addHandler", parameters: [RuntimeABIParameter(name: "loggerRaw", type: .intptr), RuntimeABIParameter(name: "handlerRaw", type: .intptr)], returnType: .intptr, section: "FileIO"),
        RuntimeABIFunctionSpec(name: "kk_logger_log", parameters: [RuntimeABIParameter(name: "loggerRaw", type: .intptr), RuntimeABIParameter(name: "levelRaw", type: .intptr), RuntimeABIParameter(name: "messageRaw", type: .intptr)], returnType: .intptr, section: "FileIO"),
        RuntimeABIFunctionSpec(name: "kk_logger_log_throwable", parameters: [RuntimeABIParameter(name: "loggerRaw", type: .intptr), RuntimeABIParameter(name: "levelRaw", type: .intptr), RuntimeABIParameter(name: "messageRaw", type: .intptr), RuntimeABIParameter(name: "throwableRaw", type: .intptr)], returnType: .intptr, section: "FileIO"),
        RuntimeABIFunctionSpec(name: "kk_logger_info", parameters: [RuntimeABIParameter(name: "loggerRaw", type: .intptr), RuntimeABIParameter(name: "messageRaw", type: .intptr)], returnType: .intptr, section: "FileIO"),
        RuntimeABIFunctionSpec(name: "kk_logger_warning", parameters: [RuntimeABIParameter(name: "loggerRaw", type: .intptr), RuntimeABIParameter(name: "messageRaw", type: .intptr)], returnType: .intptr, section: "FileIO"),
        RuntimeABIFunctionSpec(name: "kk_logger_severe", parameters: [RuntimeABIParameter(name: "loggerRaw", type: .intptr), RuntimeABIParameter(name: "messageRaw", type: .intptr)], returnType: .intptr, section: "FileIO"),
        RuntimeABIFunctionSpec(name: "kk_message_digest_getInstance", parameters: [RuntimeABIParameter(name: "algorithmRaw", type: .intptr), RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer)], returnType: .intptr, section: "FileIO"),
        RuntimeABIFunctionSpec(name: "kk_message_digest_digest", parameters: [RuntimeABIParameter(name: "digestRaw", type: .intptr), RuntimeABIParameter(name: "dataRaw", type: .intptr), RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer)], returnType: .intptr, section: "FileIO"),
        RuntimeABIFunctionSpec(name: "kk_mac_getInstance", parameters: [RuntimeABIParameter(name: "algorithmRaw", type: .intptr), RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer)], returnType: .intptr, section: "FileIO"),
        RuntimeABIFunctionSpec(name: "kk_mac_init", parameters: [RuntimeABIParameter(name: "macRaw", type: .intptr), RuntimeABIParameter(name: "keyRaw", type: .intptr), RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer)], returnType: .intptr, section: "FileIO"),
        RuntimeABIFunctionSpec(name: "kk_mac_doFinal", parameters: [RuntimeABIParameter(name: "macRaw", type: .intptr), RuntimeABIParameter(name: "dataRaw", type: .intptr), RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer)], returnType: .intptr, section: "FileIO"),
        RuntimeABIFunctionSpec(name: "kk_cache_new", parameters: [RuntimeABIParameter(name: "capacityRaw", type: .intptr)], returnType: .intptr, section: "FileIO"),
        RuntimeABIFunctionSpec(name: "kk_cache_put", parameters: [RuntimeABIParameter(name: "cacheRaw", type: .intptr), RuntimeABIParameter(name: "keyRaw", type: .intptr), RuntimeABIParameter(name: "valueRaw", type: .intptr)], returnType: .intptr, section: "FileIO"),
        RuntimeABIFunctionSpec(name: "kk_cache_get", parameters: [RuntimeABIParameter(name: "cacheRaw", type: .intptr), RuntimeABIParameter(name: "keyRaw", type: .intptr)], returnType: .intptr, section: "FileIO"),
        RuntimeABIFunctionSpec(name: "kk_cache_size", parameters: [RuntimeABIParameter(name: "cacheRaw", type: .intptr)], returnType: .intptr, section: "FileIO"),
        RuntimeABIFunctionSpec(
            name: "kk_resource_bundle_getBundle",
            parameters: [
                RuntimeABIParameter(name: "nameRaw", type: .intptr),
                RuntimeABIParameter(name: "localeRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_resource_bundle_getString",
            parameters: [
                RuntimeABIParameter(name: "bundleRaw", type: .intptr),
                RuntimeABIParameter(name: "keyRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_resource_bundle_getObject",
            parameters: [
                RuntimeABIParameter(name: "bundleRaw", type: .intptr),
                RuntimeABIParameter(name: "keyRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "FileIO"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_resource_bundle_getKeys",
            parameters: [RuntimeABIParameter(name: "bundleRaw", type: .intptr)],
            returnType: .intptr,
            section: "FileIO"
        ),
    ]

}
