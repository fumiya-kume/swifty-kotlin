import Foundation

// MARK: - File I/O Runtime (STDLIB-320/321/322/323)

final class RuntimeFileBox {
    let path: String
    init(_ path: String) { self.path = path }
}

final class RuntimeClassLoaderBox {}

final class RuntimeResourceInputStreamBox {
    private let data: Data
    private var offset: Int = 0
    private var closed = false

    init(data: Data) {
        self.data = data
    }

    func readByte() -> Int {
        guard !closed, offset < data.count else { return -1 }
        defer { offset += 1 }
        return Int(data[offset])
    }

    func close() {
        closed = true
    }
}

private func runtimeFileBox(from raw: Int) -> RuntimeFileBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeFileBox.self)
}

private func runtimeResourceInputStreamBox(from raw: Int) -> RuntimeResourceInputStreamBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeResourceInputStreamBox.self)
}

private func resourceRootDirectory() -> URL {
    if let env = ProcessInfo.processInfo.environment["KSWIFTK_RESOURCE_ROOT"], !env.isEmpty {
        return URL(fileURLWithPath: env, isDirectory: true)
    }
    return URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
}

private func existingResourceURL(named name: String) -> URL? {
    let url = resourceRootDirectory().appendingPathComponent(name)
    return FileManager.default.fileExists(atPath: url.path) ? url : nil
}

/// Split file content into lines, matching Kotlin behaviour:
/// - Empty string returns an empty array (not `[""]`).
/// - A trailing newline does NOT produce a final empty element.
private func fileSplitLines(_ content: String) -> [String] {
    if content.isEmpty { return [] }
    var lines = content.components(separatedBy: "\n")
    if lines.last == "" { lines.removeLast() }
    return lines
}

private func fileMakeStringRaw(_ value: String) -> Int {
    Int(bitPattern: value.withCString { cstr in
        cstr.withMemoryRebound(to: UInt8.self, capacity: value.utf8.count) { pointer in
            kk_string_from_utf8(pointer, Int32(value.utf8.count))
        }
    })
}

// MARK: - STDLIB-320: File constructor and basic operations

@_cdecl("kk_file_new")
public func kk_file_new(_ pathRaw: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: pathRaw),
          let path = extractString(from: ptr)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_new received invalid path")
    }
    return registerRuntimeObject(RuntimeFileBox(path))
}

@_cdecl("kk_file_readText")
public func kk_file_readText(_ fileRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_readText received invalid File handle")
    }
    do {
        let content = try String(contentsOfFile: file.path, encoding: .utf8)
        return fileMakeStringRaw(content)
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
        return fileMakeStringRaw("")
    }
}

@_cdecl("kk_classloader_getSystemClassLoader")
public func kk_classloader_getSystemClassLoader() -> Int {
    registerRuntimeObject(RuntimeClassLoaderBox())
}

@_cdecl("kk_classloader_getResource")
public func kk_classloader_getResource(_ loaderRaw: Int, _ nameRaw: Int) -> Int {
    guard UnsafeMutableRawPointer(bitPattern: loaderRaw).flatMap({ tryCast($0, to: RuntimeClassLoaderBox.self) }) != nil else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_classloader_getResource received invalid ClassLoader handle")
    }
    guard let ptr = UnsafeMutableRawPointer(bitPattern: nameRaw),
          let name = extractString(from: ptr),
          let url = existingResourceURL(named: name)
    else {
        return runtimeNullSentinelInt
    }
    return fileMakeStringRaw(url.path)
}

@_cdecl("kk_classloader_getResourceAsStream")
public func kk_classloader_getResourceAsStream(_ loaderRaw: Int, _ nameRaw: Int) -> Int {
    guard UnsafeMutableRawPointer(bitPattern: loaderRaw).flatMap({ tryCast($0, to: RuntimeClassLoaderBox.self) }) != nil else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_classloader_getResourceAsStream received invalid ClassLoader handle")
    }
    guard let ptr = UnsafeMutableRawPointer(bitPattern: nameRaw),
          let name = extractString(from: ptr),
          let url = existingResourceURL(named: name),
          let data = try? Data(contentsOf: url)
    else {
        return runtimeNullSentinelInt
    }
    return registerRuntimeObject(RuntimeResourceInputStreamBox(data: data))
}

@_cdecl("kk_resource_exists")
public func kk_resource_exists(_ nameRaw: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: nameRaw),
          let name = extractString(from: ptr)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_resource_exists received invalid name")
    }
    return kk_box_bool(existingResourceURL(named: name) != nil ? 1 : 0)
}

@_cdecl("kk_readResourceAsText")
public func kk_readResourceAsText(_ nameRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let ptr = UnsafeMutableRawPointer(bitPattern: nameRaw),
          let name = extractString(from: ptr)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_readResourceAsText received invalid name")
    }
    guard let url = existingResourceURL(named: name) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: Resource not found: \(name)")
        return fileMakeStringRaw("")
    }
    do {
        return fileMakeStringRaw(try String(contentsOf: url, encoding: .utf8))
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
        return fileMakeStringRaw("")
    }
}

@_cdecl("kk_resource_stream_read")
public func kk_resource_stream_read(_ streamRaw: Int) -> Int {
    guard let stream = runtimeResourceInputStreamBox(from: streamRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_resource_stream_read received invalid InputStream handle")
    }
    return stream.readByte()
}

@_cdecl("kk_resource_stream_close")
public func kk_resource_stream_close(_ streamRaw: Int) -> Int {
    guard let stream = runtimeResourceInputStreamBox(from: streamRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_resource_stream_close received invalid InputStream handle")
    }
    stream.close()
    return 0
}

@_cdecl("kk_file_writeText")
public func kk_file_writeText(_ fileRaw: Int, _ textRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_writeText received invalid File handle")
    }
    guard let ptr = UnsafeMutableRawPointer(bitPattern: textRaw),
          let text = extractString(from: ptr)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_writeText received invalid text")
    }
    do {
        try text.write(toFile: file.path, atomically: true, encoding: .utf8)
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
    }
    return 0
}

// MARK: - STDLIB-664: File.appendText()


@_cdecl("kk_file_appendText")
public func kk_file_appendText(_ fileRaw: Int, _ textRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_appendText received invalid File handle")
    }
    guard let ptr = UnsafeMutableRawPointer(bitPattern: textRaw),
          let text = extractString(from: ptr)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_appendText received invalid text")
    }
    do {
        let url = URL(fileURLWithPath: file.path)
        if FileManager.default.fileExists(atPath: file.path) {
            let handle = try FileHandle(forWritingTo: url)
            handle.seekToEndOfFile()
            if let data = text.data(using: .utf8) {
                handle.write(data)
            }
            handle.closeFile()
        } else {
            try text.write(toFile: file.path, atomically: true, encoding: .utf8)
        }
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
    }
    return 0
}

@_cdecl("kk_file_readLines")
public func kk_file_readLines(_ fileRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_readLines received invalid File handle")
    }
    do {
        let content = try String(contentsOfFile: file.path, encoding: .utf8)
        let lines = fileSplitLines(content)
        return registerRuntimeObject(RuntimeListBox(elements: lines.map { fileMakeStringRaw($0) }))
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
}

// MARK: - STDLIB-665: File.readBytes()

@_cdecl("kk_file_readBytes")
public func kk_file_readBytes(_ fileRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_readBytes received invalid File handle")
    }
    do {
        let data = try Data(contentsOf: URL(fileURLWithPath: file.path))
        let elements = data.map { Int(Int8(bitPattern: $0)) }
        return registerRuntimeObject(RuntimeListBox(elements: elements))
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
}

// MARK: - STDLIB-321: File properties and existence checks

@_cdecl("kk_file_exists")
public func kk_file_exists(_ fileRaw: Int) -> Int {
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_exists received invalid File handle")
    }
    return kk_box_bool(FileManager.default.fileExists(atPath: file.path) ? 1 : 0)
}

@_cdecl("kk_file_isFile")
public func kk_file_isFile(_ fileRaw: Int) -> Int {
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_isFile received invalid File handle")
    }
    var isDir: ObjCBool = false
    let exists = FileManager.default.fileExists(atPath: file.path, isDirectory: &isDir)
    return kk_box_bool(exists && !isDir.boolValue ? 1 : 0)
}

@_cdecl("kk_file_isDirectory")
public func kk_file_isDirectory(_ fileRaw: Int) -> Int {
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_isDirectory received invalid File handle")
    }
    var isDir: ObjCBool = false
    let exists = FileManager.default.fileExists(atPath: file.path, isDirectory: &isDir)
    return kk_box_bool(exists && isDir.boolValue ? 1 : 0)
}

@_cdecl("kk_file_name")
public func kk_file_name(_ fileRaw: Int) -> Int {
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_name received invalid File handle")
    }
    return fileMakeStringRaw((file.path as NSString).lastPathComponent)
}

@_cdecl("kk_file_path")
public func kk_file_path(_ fileRaw: Int) -> Int {
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_path received invalid File handle")
    }
    return fileMakeStringRaw(file.path)
}

// MARK: - STDLIB-322: File line-by-line operations

@_cdecl("kk_file_forEachLine")
public func kk_file_forEachLine(_ fileRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_forEachLine received invalid File handle")
    }
    guard let content = try? String(contentsOfFile: file.path, encoding: .utf8) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: Cannot read file \(file.path)")
        return 0
    }
    let lines = fileSplitLines(content)
    for line in lines {
        let lineRaw = fileMakeStringRaw(line)
        var thrown = 0
        _ = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: lineRaw, outThrown: &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            return 0
        }
    }
    return 0
}

// MARK: - STDLIB-566: File.useLines {}

@_cdecl("kk_file_useLines")
public func kk_file_useLines(_ fileRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_useLines received invalid File handle")
    }
    guard let content = try? String(contentsOfFile: file.path, encoding: .utf8) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: Cannot read file \(file.path)")
        return 0
    }
    let lines = fileSplitLines(content)
    let linesList = RuntimeListBox(elements: lines.map { fileMakeStringRaw($0) })
    let linesListRaw = registerRuntimeObject(linesList)
    var thrown = 0
    let result = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: linesListRaw, outThrown: &thrown)
    if thrown != 0 {
        outThrown?.pointee = thrown
        return 0
    }
    return result
}

// MARK: - STDLIB-323: File filesystem operations

@_cdecl("kk_file_delete")
public func kk_file_delete(_ fileRaw: Int) -> Int {
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_delete received invalid File handle")
    }
    return kk_box_bool((try? FileManager.default.removeItem(atPath: file.path)) != nil ? 1 : 0)
}

@_cdecl("kk_file_mkdirs")
public func kk_file_mkdirs(_ fileRaw: Int) -> Int {
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_mkdirs received invalid File handle")
    }
    return kk_box_bool((try? FileManager.default.createDirectory(atPath: file.path, withIntermediateDirectories: true)) != nil ? 1 : 0)
}

@_cdecl("kk_file_listFiles")
public func kk_file_listFiles(_ fileRaw: Int) -> Int {
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_listFiles received invalid File handle")
    }
    guard let entries = try? FileManager.default.contentsOfDirectory(atPath: file.path) else {
        return runtimeNullSentinelInt
    }
    let elements = entries.map { entry -> Int in
        let childPath = (file.path as NSString).appendingPathComponent(entry)
        return registerRuntimeObject(RuntimeFileBox(childPath))
    }
    return registerRuntimeObject(RuntimeListBox(elements: elements))
}

@_cdecl("kk_file_walk")
public func kk_file_walk(_ fileRaw: Int) -> Int {
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_walk received invalid File handle")
    }
    // Kotlin's File.walk() includes the root directory itself as the first element
    var files: [Int] = [registerRuntimeObject(RuntimeFileBox(file.path))]
    if let enumerator = FileManager.default.enumerator(atPath: file.path) {
        while let relativePath = enumerator.nextObject() as? String {
            let fullPath = (file.path as NSString).appendingPathComponent(relativePath)
            files.append(registerRuntimeObject(RuntimeFileBox(fullPath)))
        }
    }
    // Return as a Sequence (list of File handles)
    let listBox = RuntimeListBox(elements: files)
    return registerRuntimeObject(listBox)
}

// MARK: - STDLIB-567: File.bufferedReader()

private func runtimeBufferedReaderBox(from raw: Int) -> RuntimeBufferedReaderBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeBufferedReaderBox.self)
}

private func runtimeInputStreamBox(from raw: Int) -> RuntimeInputStreamBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeInputStreamBox.self)
}

private func runtimeOutputStreamBox(from raw: Int) -> RuntimeOutputStreamBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeOutputStreamBox.self)
}

@_cdecl("kk_file_bufferedReader")
public func kk_file_bufferedReader(_ fileRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_bufferedReader received invalid File handle")
    }
    do {
        let fileHandle = try FileHandle(forReadingFrom: URL(fileURLWithPath: file.path))
        return registerRuntimeObject(RuntimeBufferedReaderBox(fileHandle: fileHandle))
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
        return 0
    }
}

@_cdecl("kk_buffered_reader_readLine")
public func kk_buffered_reader_readLine(_ readerRaw: Int) -> Int {
    guard let reader = runtimeBufferedReaderBox(from: readerRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_buffered_reader_readLine received invalid BufferedReader handle")
    }
    guard let line = reader.readLine() else {
        return runtimeNullSentinelInt
    }
    return fileMakeStringRaw(line)
}

@_cdecl("kk_buffered_reader_readLines")
public func kk_buffered_reader_readLines(_ readerRaw: Int) -> Int {
    guard let reader = runtimeBufferedReaderBox(from: readerRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_buffered_reader_readLines received invalid BufferedReader handle")
    }
    let lines = reader.readLines()
    return registerRuntimeObject(RuntimeListBox(elements: lines.map { fileMakeStringRaw($0) }))
}

@_cdecl("kk_buffered_reader_close")
public func kk_buffered_reader_close(_ readerRaw: Int) -> Int {
    guard let reader = runtimeBufferedReaderBox(from: readerRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_buffered_reader_close received invalid BufferedReader handle")
    }
    reader.close()
    return 0
}

@_cdecl("kk_buffered_reader_read")
public func kk_buffered_reader_read(_ readerRaw: Int) -> Int {
    guard let reader = runtimeBufferedReaderBox(from: readerRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_buffered_reader_read received invalid BufferedReader handle")
    }
    return reader.read()
}

@_cdecl("kk_buffered_reader_ready")
public func kk_buffered_reader_ready(_ readerRaw: Int) -> Int {
    guard let reader = runtimeBufferedReaderBox(from: readerRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_buffered_reader_ready received invalid BufferedReader handle")
    }
    return kk_box_bool(reader.ready() ? 1 : 0)
}

// MARK: - STDLIB-IO-091: BufferedWriter

private func runtimeBufferedWriterBox(from raw: Int) -> RuntimeBufferedWriterBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeBufferedWriterBox.self)
}

@_cdecl("kk_file_bufferedWriter")
public func kk_file_bufferedWriter(_ fileRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_bufferedWriter received invalid File handle")
    }
    let url = URL(fileURLWithPath: file.path)
    if !FileManager.default.fileExists(atPath: file.path) {
        FileManager.default.createFile(atPath: file.path, contents: Data())
    }
    do {
        let handle = try FileHandle(forWritingTo: url)
        handle.truncateFile(atOffset: 0)
        return registerRuntimeObject(RuntimeBufferedWriterBox(fileHandle: handle))
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
        return 0
    }
}

@_cdecl("kk_buffered_writer_write")
public func kk_buffered_writer_write(_ writerRaw: Int, _ textRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let writer = runtimeBufferedWriterBox(from: writerRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_buffered_writer_write received invalid BufferedWriter handle")
    }
    guard let ptr = UnsafeMutableRawPointer(bitPattern: textRaw),
          let text = extractString(from: ptr)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_buffered_writer_write received invalid text")
    }
    do {
        try writer.write(text)
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
    }
    return 0
}

@_cdecl("kk_buffered_writer_new_line")
public func kk_buffered_writer_new_line(_ writerRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let writer = runtimeBufferedWriterBox(from: writerRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_buffered_writer_new_line received invalid BufferedWriter handle")
    }
    do {
        try writer.newLine()
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
    }
    return 0
}

@_cdecl("kk_buffered_writer_flush")
public func kk_buffered_writer_flush(_ writerRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let writer = runtimeBufferedWriterBox(from: writerRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_buffered_writer_flush received invalid BufferedWriter handle")
    }
    do {
        try writer.flush()
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
    }
    return 0
}

@_cdecl("kk_buffered_writer_close")
public func kk_buffered_writer_close(_ writerRaw: Int) -> Int {
    guard let writer = runtimeBufferedWriterBox(from: writerRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_buffered_writer_close received invalid BufferedWriter handle")
    }
    writer.close()
    return 0
}

@_cdecl("kk_file_inputStream")
public func kk_file_inputStream(_ fileRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_inputStream received invalid File handle")
    }
    do {
        let data = try Data(contentsOf: URL(fileURLWithPath: file.path))
        return registerRuntimeObject(RuntimeInputStreamBox(data: data))
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
        return 0
    }
}

@_cdecl("kk_file_outputStream")
public func kk_file_outputStream(_ fileRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_outputStream received invalid File handle")
    }
    let url = URL(fileURLWithPath: file.path)
    if !FileManager.default.fileExists(atPath: file.path) {
        FileManager.default.createFile(atPath: file.path, contents: Data())
    }
    do {
        let handle = try FileHandle(forWritingTo: url)
        handle.truncateFile(atOffset: 0)
        return registerRuntimeObject(RuntimeOutputStreamBox(fileHandle: handle))
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
        return 0
    }
}

@_cdecl("kk_input_stream_read")
public func kk_input_stream_read(_ streamRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let stream = runtimeInputStreamBox(from: streamRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_input_stream_read received invalid InputStream handle")
    }
    return stream.readByte()
}

@_cdecl("kk_input_stream_available")
public func kk_input_stream_available(_ streamRaw: Int) -> Int {
    guard let stream = runtimeInputStreamBox(from: streamRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_input_stream_available received invalid InputStream handle")
    }
    return stream.available()
}

@_cdecl("kk_input_stream_skip")
public func kk_input_stream_skip(_ streamRaw: Int, _ countRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let stream = runtimeInputStreamBox(from: streamRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_input_stream_skip received invalid InputStream handle")
    }
    return stream.skip(countRaw)
}

@_cdecl("kk_input_stream_read_bytes")
public func kk_input_stream_read_bytes(_ streamRaw: Int, _ bytesRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let stream = runtimeInputStreamBox(from: streamRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_input_stream_read_bytes received invalid InputStream handle")
    }
    guard let list = runtimeListBox(from: bytesRaw) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IllegalArgumentException: expected ByteArray/List<Int> buffer")
        return -1
    }
    return stream.read(into: list)
}

@_cdecl("kk_input_stream_close")
public func kk_input_stream_close(_ streamRaw: Int) -> Int {
    guard let stream = runtimeInputStreamBox(from: streamRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_input_stream_close received invalid InputStream handle")
    }
    stream.close()
    return 0
}

@_cdecl("kk_output_stream_write_byte")
public func kk_output_stream_write_byte(_ streamRaw: Int, _ valueRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let stream = runtimeOutputStreamBox(from: streamRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_output_stream_write_byte received invalid OutputStream handle")
    }
    do {
        try stream.writeByte(valueRaw)
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
    }
    return 0
}

@_cdecl("kk_output_stream_write_bytes")
public func kk_output_stream_write_bytes(_ streamRaw: Int, _ bytesRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let stream = runtimeOutputStreamBox(from: streamRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_output_stream_write_bytes received invalid OutputStream handle")
    }
    guard let list = runtimeListBox(from: bytesRaw) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IllegalArgumentException: expected ByteArray/List<Int> buffer")
        return 0
    }
    do {
        try stream.writeBytes(list.elements)
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
    }
    return 0
}

@_cdecl("kk_output_stream_flush")
public func kk_output_stream_flush(_ streamRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let stream = runtimeOutputStreamBox(from: streamRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_output_stream_flush received invalid OutputStream handle")
    }
    do {
        try stream.flush()
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
    }
    return 0
}

@_cdecl("kk_output_stream_close")
public func kk_output_stream_close(_ streamRaw: Int) -> Int {
    guard let stream = runtimeOutputStreamBox(from: streamRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_output_stream_close received invalid OutputStream handle")
    }
    stream.close()
    return 0
}
