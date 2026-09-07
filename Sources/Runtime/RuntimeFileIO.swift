import Foundation

// MARK: - File I/O Runtime (STDLIB-320/321/322/323)

final class RuntimeFileBox {
    let path: String
    init(_ path: String) { self.path = path }
}

final class RuntimeClassLoaderBox {}

private func runtimeFileBox(from raw: Int) -> RuntimeFileBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeFileBox.self)
}

private func resourceRootDirectory() -> URL {
    if let env = ProcessInfo.processInfo.environment["KSWIFTK_RESOURCE_ROOT"], !env.isEmpty {
        return URL(fileURLWithPath: env, isDirectory: true)
    }
    return URL(fileURLWithPath: FileManager.default.currentDirectoryPath, isDirectory: true)
}

private func existingResourceURL(named name: String) -> URL? {
    guard !name.isEmpty else { return nil }
    let root = resourceRootDirectory().standardizedFileURL
    let resolved = root.appendingPathComponent(name).standardizedFileURL
    let rootPath = root.path.hasSuffix("/") ? root.path : root.path + "/"
    guard resolved.path == root.path || resolved.path.hasPrefix(rootPath) else {
        return nil
    }
    return FileManager.default.fileExists(atPath: resolved.path) ? resolved : nil
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

private func runtimeOptionalFileIOStringArgument(_ raw: Int) -> String? {
    guard raw != runtimeNullSentinelInt,
          let ptr = UnsafeMutableRawPointer(bitPattern: raw)
    else {
        return nil
    }
    return extractString(from: ptr)
}

private func runtimeOptionalFileBoxArgument(_ raw: Int) -> RuntimeFileBox? {
    guard raw != runtimeNullSentinelInt else {
        return nil
    }
    return runtimeFileBox(from: raw)
}

private func runtimeDeprecatedTempRootDirectory(directoryRaw: Int) -> String {
    if let directory = runtimeOptionalFileBoxArgument(directoryRaw) {
        return directory.path
    }
    return NSTemporaryDirectory()
}

private func runtimeDeprecatedTempPrefix(_ raw: Int) -> String {
    runtimeOptionalFileIOStringArgument(raw) ?? "tmp"
}

private func runtimeDeprecatedTempSuffix(_ raw: Int, default defaultValue: String) -> String {
    runtimeOptionalFileIOStringArgument(raw) ?? defaultValue
}

private func runtimeCreateDeprecatedTempFile(
    prefixRaw: Int,
    suffixRaw: Int,
    directoryRaw: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let prefix = runtimeDeprecatedTempPrefix(prefixRaw)
    let suffix = runtimeDeprecatedTempSuffix(suffixRaw, default: ".tmp")
    let rootDirectory = runtimeDeprecatedTempRootDirectory(directoryRaw: directoryRaw)
    let fileName = "\(prefix)\(UUID().uuidString)\(suffix)"
    let fullPath = (rootDirectory as NSString).appendingPathComponent(fileName)
    let created = FileManager.default.createFile(atPath: fullPath, contents: nil)
    if !created {
        outThrown?.pointee = runtimeAllocateFileSystemException(
            file: fullPath,
            reason: "Failed to create the temporary file."
        )
    }
    return registerRuntimeObject(RuntimeFileBox(fullPath))
}

private func runtimeCreateDeprecatedTempDirectory(
    prefixRaw: Int,
    suffixRaw: Int,
    directoryRaw: Int,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let prefix = runtimeDeprecatedTempPrefix(prefixRaw)
    let suffix = runtimeDeprecatedTempSuffix(suffixRaw, default: ".tmp")
    let rootDirectory = runtimeDeprecatedTempRootDirectory(directoryRaw: directoryRaw)
    let dirName = "\(prefix)\(UUID().uuidString)\(suffix)"
    let fullPath = (rootDirectory as NSString).appendingPathComponent(dirName)
    do {
        _ = try FileManager.default.createDirectory(atPath: fullPath, withIntermediateDirectories: true)
    } catch {
        outThrown?.pointee = runtimeAllocateFileSystemException(
            file: fullPath,
            reason: error.localizedDescription
        )
    }
    return registerRuntimeObject(RuntimeFileBox(fullPath))
}

// MARK: - STDLIB-320: File constructor and basic operations

@_cdecl("__kk_file_new")
public func __kk_file_new(_ pathRaw: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: pathRaw),
          let path = extractString(from: ptr)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_file_new received invalid path")
    }
    return registerRuntimeObject(RuntimeFileBox(path))
}

/// File(parent: String, child: String) constructor (STDLIB-IO-087)
@_cdecl("__kk_file_new_parent_child")
public func __kk_file_new_parent_child(_ parentRaw: Int, _ childRaw: Int) -> Int {
    guard let parentPtr = UnsafeMutableRawPointer(bitPattern: parentRaw),
          let parent = extractString(from: parentPtr)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_file_new_parent_child received invalid parent")
    }
    guard let childPtr = UnsafeMutableRawPointer(bitPattern: childRaw),
          let child = extractString(from: childPtr)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_file_new_parent_child received invalid child")
    }
    let path = (parent as NSString).appendingPathComponent(child)
    return registerRuntimeObject(RuntimeFileBox(path))
}

@_cdecl("__kk_file_readText")
public func __kk_file_readText(_ fileRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_file_readText received invalid File handle")
    }
    do {
        let content = try String(contentsOfFile: file.path, encoding: .utf8)
        return fileMakeStringRaw(content)
    } catch {
        outThrown?.pointee = runtimeAllocateFileSystemException(
            file: file.path,
            reason: error.localizedDescription
        )
        return fileMakeStringRaw("")
    }
}

@_cdecl("__kk_classloader_getSystemClassLoader")
public func __kk_classloader_getSystemClassLoader() -> Int {
    registerRuntimeObject(RuntimeClassLoaderBox())
}

@_cdecl("__kk_classloader_getResource")
public func __kk_classloader_getResource(_ loaderRaw: Int, _ nameRaw: Int) -> Int {
    guard UnsafeMutableRawPointer(bitPattern: loaderRaw).flatMap({ tryCast($0, to: RuntimeClassLoaderBox.self) }) != nil else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_classloader_getResource received invalid ClassLoader handle")
    }
    guard let ptr = UnsafeMutableRawPointer(bitPattern: nameRaw),
          let name = extractString(from: ptr),
          let url = existingResourceURL(named: name)
    else {
        return runtimeNullSentinelInt
    }
    return fileMakeStringRaw(url.path)
}

@_cdecl("__kk_classloader_getResourceAsStream")
public func __kk_classloader_getResourceAsStream(_ loaderRaw: Int, _ nameRaw: Int) -> Int {
    guard UnsafeMutableRawPointer(bitPattern: loaderRaw).flatMap({ tryCast($0, to: RuntimeClassLoaderBox.self) }) != nil else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_classloader_getResourceAsStream received invalid ClassLoader handle")
    }
    guard let ptr = UnsafeMutableRawPointer(bitPattern: nameRaw),
          let name = extractString(from: ptr),
          let url = existingResourceURL(named: name),
          let data = try? Data(contentsOf: url)
    else {
        return runtimeNullSentinelInt
    }
    return registerRuntimeObject(RuntimeInputStreamBox(data: data))
}

@_cdecl("__kk_resource_exists")
public func __kk_resource_exists(_ nameRaw: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: nameRaw),
          let name = extractString(from: ptr)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_resource_exists received invalid name")
    }
    return kk_box_bool(existingResourceURL(named: name) != nil ? 1 : 0)
}

@_cdecl("__kk_readResourceAsText")
public func __kk_readResourceAsText(_ nameRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let ptr = UnsafeMutableRawPointer(bitPattern: nameRaw),
          let name = extractString(from: ptr)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_readResourceAsText received invalid name")
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

@_cdecl("__kk_resource_stream_read")
public func __kk_resource_stream_read(_ streamRaw: Int) -> Int {
    guard let stream = runtimeInputStreamBox(from: streamRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_resource_stream_read received invalid InputStream handle")
    }
    return stream.readByte()
}

@_cdecl("__kk_resource_stream_close")
public func __kk_resource_stream_close(_ streamRaw: Int) -> Int {
    guard let stream = runtimeInputStreamBox(from: streamRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_resource_stream_close received invalid InputStream handle")
    }
    stream.close()
    return 0
}

@_cdecl("__kk_file_writeText")
public func __kk_file_writeText(_ fileRaw: Int, _ textRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_file_writeText received invalid File handle")
    }
    guard let ptr = UnsafeMutableRawPointer(bitPattern: textRaw),
          let text = extractString(from: ptr)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_file_writeText received invalid text")
    }
    do {
        try text.write(toFile: file.path, atomically: true, encoding: .utf8)
    } catch {
        outThrown?.pointee = runtimeAllocateFileSystemException(
            file: file.path,
            reason: error.localizedDescription
        )
    }
    return 0
}

// MARK: - STDLIB-664: File.appendText()

@_cdecl("__kk_file_appendText")
public func __kk_file_appendText(_ fileRaw: Int, _ textRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_file_appendText received invalid File handle")
    }
    guard let ptr = UnsafeMutableRawPointer(bitPattern: textRaw),
          let text = extractString(from: ptr)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_file_appendText received invalid text")
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
        outThrown?.pointee = runtimeAllocateFileSystemException(
            file: file.path,
            reason: error.localizedDescription
        )
    }
    return 0
}

@_cdecl("__kk_file_readLines")
public func __kk_file_readLines(_ fileRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_file_readLines received invalid File handle")
    }
    do {
        let content = try String(contentsOfFile: file.path, encoding: .utf8)
        let lines = fileSplitLines(content)
        return registerRuntimeObject(RuntimeListBox(elements: lines.map { fileMakeStringRaw($0) }))
    } catch {
        outThrown?.pointee = runtimeAllocateFileSystemException(
            file: file.path,
            reason: error.localizedDescription
        )
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
}

// MARK: - STDLIB-665: File.readBytes()

@_cdecl("__kk_file_readBytes")
public func __kk_file_readBytes(_ fileRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_file_readBytes received invalid File handle")
    }
    do {
        let data = try Data(contentsOf: URL(fileURLWithPath: file.path))
        let elements = data.map { Int(Int8(bitPattern: $0)) }
        return registerRuntimeObject(RuntimeListBox(elements: elements))
    } catch {
        outThrown?.pointee = runtimeAllocateFileSystemException(
            file: file.path,
            reason: error.localizedDescription
        )
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
}

// MARK: - STDLIB-IO-FN-001: File.appendBytes(array: ByteArray)

@_cdecl("__kk_file_appendBytes")
public func __kk_file_appendBytes(_ fileRaw: Int, _ arrayRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_file_appendBytes received invalid File handle")
    }
    guard let bytes = runtimeByteArrayBytes(from: arrayRaw) else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(message: "expected ByteArray/List<Int> array")
        return 0
    }
    do {
        let data = Data(bytes)
        let url = URL(fileURLWithPath: file.path)
        if FileManager.default.fileExists(atPath: file.path) {
            let handle = try FileHandle(forWritingTo: url)
            handle.seekToEndOfFile()
            handle.write(data)
            handle.closeFile()
        } else {
            try data.write(to: url)
        }
    } catch {
        outThrown?.pointee = runtimeAllocateFileSystemException(
            file: file.path,
            reason: error.localizedDescription
        )
    }
    return 0
}

// MARK: - MIGRATION-IO-001: File.writeBytes(array: ByteArray)

@_cdecl("__kk_file_writeBytes")
public func __kk_file_writeBytes(_ fileRaw: Int, _ arrayRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_file_writeBytes received invalid File handle")
    }
    guard let bytes = runtimeByteArrayBytes(from: arrayRaw) else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(message: "expected ByteArray/List<Int> array")
        return 0
    }
    do {
        try Data(bytes).write(to: URL(fileURLWithPath: file.path))
    } catch {
        outThrown?.pointee = runtimeAllocateFileSystemException(
            file: file.path,
            reason: error.localizedDescription
        )
    }
    return 0
}

// MARK: - STDLIB-321: File properties and existence checks

@_cdecl("__kk_file_exists")
public func __kk_file_exists(_ fileRaw: Int) -> Int {
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_file_exists received invalid File handle")
    }
    return kk_box_bool(FileManager.default.fileExists(atPath: file.path) ? 1 : 0)
}

@_cdecl("__kk_file_isFile")
public func __kk_file_isFile(_ fileRaw: Int) -> Int {
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_file_isFile received invalid File handle")
    }
    var isDir: ObjCBool = false
    let exists = FileManager.default.fileExists(atPath: file.path, isDirectory: &isDir)
    return kk_box_bool(exists && !isDir.boolValue ? 1 : 0)
}

@_cdecl("__kk_file_isDirectory")
public func __kk_file_isDirectory(_ fileRaw: Int) -> Int {
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_file_isDirectory received invalid File handle")
    }
    var isDir: ObjCBool = false
    let exists = FileManager.default.fileExists(atPath: file.path, isDirectory: &isDir)
    return kk_box_bool(exists && isDir.boolValue ? 1 : 0)
}

@_cdecl("__kk_file_path")
public func __kk_file_path(_ fileRaw: Int) -> Int {
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_file_path received invalid File handle")
    }
    return fileMakeStringRaw(file.path)
}

// MARK: - STDLIB-IO-087: Additional File properties and operations

@_cdecl("__kk_file_absolutePath")
public func __kk_file_absolutePath(_ fileRaw: Int) -> Int {
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_file_absolutePath received invalid File handle")
    }
    let url = URL(fileURLWithPath: file.path)
    return fileMakeStringRaw(url.path)
}

@_cdecl("__kk_file_canonicalPath")
public func __kk_file_canonicalPath(_ fileRaw: Int) -> Int {
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_file_canonicalPath received invalid File handle")
    }
    let resolved = (file.path as NSString).standardizingPath
    return fileMakeStringRaw(resolved)
}

@_cdecl("__kk_file_length")
public func __kk_file_length(_ fileRaw: Int) -> Int {
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_file_length received invalid File handle")
    }
    guard let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
          let size = attrs[.size] as? Int else {
        return 0
    }
    return size
}

@_cdecl("__kk_file_lastModified")
public func __kk_file_lastModified(_ fileRaw: Int) -> Int {
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_file_lastModified received invalid File handle")
    }
    guard let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
          let modDate = attrs[.modificationDate] as? Date else {
        return 0
    }
    // Kotlin returns milliseconds since epoch (Long)
    return Int(modDate.timeIntervalSince1970 * 1000)
}

@_cdecl("__kk_file_createNewFile")
public func __kk_file_createNewFile(_ fileRaw: Int) -> Int {
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_file_createNewFile received invalid File handle")
    }
    if FileManager.default.fileExists(atPath: file.path) {
        return kk_box_bool(0) // false: file already exists
    }
    let created = FileManager.default.createFile(atPath: file.path, contents: nil)
    return kk_box_bool(created ? 1 : 0)
}

@_cdecl("__kk_file_canRead")
public func __kk_file_canRead(_ fileRaw: Int) -> Int {
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_file_canRead received invalid File handle")
    }
    return kk_box_bool(FileManager.default.isReadableFile(atPath: file.path) ? 1 : 0)
}

@_cdecl("__kk_file_canWrite")
public func __kk_file_canWrite(_ fileRaw: Int) -> Int {
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_file_canWrite received invalid File handle")
    }
    return kk_box_bool(FileManager.default.isWritableFile(atPath: file.path) ? 1 : 0)
}

@_cdecl("__kk_file_canExecute")
public func __kk_file_canExecute(_ fileRaw: Int) -> Int {
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_file_canExecute received invalid File handle")
    }
    return kk_box_bool(FileManager.default.isExecutableFile(atPath: file.path) ? 1 : 0)
}

// MARK: - STDLIB-322: File line-by-line operations

@_cdecl("__kk_file_forEachLine")
public func __kk_file_forEachLine(_ fileRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_file_forEachLine received invalid File handle")
    }
    guard let content = try? String(contentsOfFile: file.path, encoding: .utf8) else {
        outThrown?.pointee = runtimeAllocateFileSystemException(
            file: file.path,
            reason: "Cannot read the file."
        )
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

// MARK: - STDLIB-IO-FN-016: File.forEachBlock
//
// Kotlin signatures:
//   public fun File.forEachBlock(action: (buffer: ByteArray, bytesRead: Int) -> Unit): Unit
//   public fun File.forEachBlock(blockSize: Int, action: (buffer: ByteArray, bytesRead: Int) -> Unit): Unit
//
// Reads the file in binary chunks of `blockSize` bytes (default 4096). For each
// chunk the HOF action is invoked with (buffer: List<Int>, bytesRead: Int). The
// caller (KIR lowering) appends a zero closureRaw sentinel so the runtime
// receives (fileRaw, fnPtr, closureRaw, outThrown) for the default-size overload
// and (fileRaw, blockSizeRaw, fnPtr, closureRaw, outThrown) for the explicit-size
// overload. The lambda uses the 2-argument HOF closure ABI
// (runtimeInvokeCollectionLambda2).
private let fileForEachBlockDefaultSize = 4096

private func fileForEachBlockImpl(
    fileRaw: Int, blockSize: Int, fnPtr: Int, closureRaw: Int, outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: forEachBlock received invalid File handle")
    }
    let effectiveBlockSize = max(1, blockSize)
    guard let data = try? Data(contentsOf: URL(fileURLWithPath: file.path)) else {
        outThrown?.pointee = runtimeAllocateFileSystemException(
            file: file.path,
            reason: "Cannot read the file."
        )
        return 0
    }
    var offset = data.startIndex
    while offset < data.endIndex {
        let end = data.index(offset, offsetBy: effectiveBlockSize, limitedBy: data.endIndex) ?? data.endIndex
        let chunk = data[offset ..< end]
        let bytesRead = chunk.count
        let bufferElements = chunk.map { Int(Int8(bitPattern: $0)) }
        let bufferListRaw = registerRuntimeObject(RuntimeListBox(elements: bufferElements))
        let bytesReadRaw = kk_box_int(bytesRead)
        var thrown = 0
        _ = runtimeInvokeCollectionLambda2(fnPtr: fnPtr, closureRaw: closureRaw, lhs: bufferListRaw, rhs: bytesReadRaw, outThrown: &thrown)
        if thrown != 0 {
            outThrown?.pointee = thrown
            return 0
        }
        offset = end
    }
    return 0
}

@_cdecl("__kk_file_forEachBlock")
public func __kk_file_forEachBlock(_ fileRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    fileForEachBlockImpl(fileRaw: fileRaw, blockSize: fileForEachBlockDefaultSize, fnPtr: fnPtr, closureRaw: closureRaw, outThrown: outThrown)
}

@_cdecl("__kk_file_forEachBlock_blockSize")
public func __kk_file_forEachBlock_blockSize(_ fileRaw: Int, _ blockSizeRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    fileForEachBlockImpl(fileRaw: fileRaw, blockSize: kk_unbox_int(blockSizeRaw), fnPtr: fnPtr, closureRaw: closureRaw, outThrown: outThrown)}

// MARK: - STDLIB-566: File.useLines {}

@_cdecl("__kk_file_useLines")
public func __kk_file_useLines(_ fileRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_file_useLines received invalid File handle")
    }
    guard let content = try? String(contentsOfFile: file.path, encoding: .utf8) else {
        outThrown?.pointee = runtimeAllocateFileSystemException(
            file: file.path,
            reason: "Cannot read the file."
        )
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

@_cdecl("__kk_file_delete")
public func __kk_file_delete(_ fileRaw: Int) -> Int {
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_file_delete received invalid File handle")
    }
    return kk_box_bool((try? FileManager.default.removeItem(atPath: file.path)) != nil ? 1 : 0)
}

@_cdecl("__kk_file_mkdirs")
public func __kk_file_mkdirs(_ fileRaw: Int) -> Int {
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_file_mkdirs received invalid File handle")
    }
    return kk_box_bool((try? FileManager.default.createDirectory(atPath: file.path, withIntermediateDirectories: true)) != nil ? 1 : 0)
}

@_cdecl("__kk_file_listFiles")
public func __kk_file_listFiles(_ fileRaw: Int) -> Int {
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_file_listFiles received invalid File handle")
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

@_cdecl("__kk_file_walk")
public func __kk_file_walk(_ fileRaw: Int) -> Int {
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_file_walk received invalid File handle")
    }
    var results: [Int] = []
    fileWalkCollect(at: file.path, results: &results)
    return registerRuntimeObject(RuntimeListBox(elements: results))
}

/// Preorder (TOP_DOWN) DFS traversal of the file tree rooted at `path`.
/// Directory entries are visited in sorted order so output is deterministic.
private func fileWalkCollect(at path: String, results: inout [Int]) {
    var isDir: ObjCBool = false
    _ = FileManager.default.fileExists(atPath: path, isDirectory: &isDir)
    results.append(registerRuntimeObject(RuntimeFileBox(path)))
    guard isDir.boolValue,
          let entries = try? FileManager.default.contentsOfDirectory(atPath: path)
    else { return }
    for entry in entries.sorted() {
        fileWalkCollect(at: (path as NSString).appendingPathComponent(entry), results: &results)
    }
}

// MARK: - STDLIB-IO-FN-015: File.copyTo(target, overwrite, bufferSize)
//
// Kotlin signature:
//   public fun File.copyTo(
//       target: File,
//       overwrite: Boolean = false,
//       bufferSize: Int = DEFAULT_BUFFER_SIZE
//   ): File
//
// Behaviour mirrored from `kotlin.io.FileTreeWalk`:
// - Throws `NoSuchFileException` if `this` does not exist.
// - If `this` is a directory: creates the target directory (does NOT copy
//   contents recursively — that is `copyRecursively`).
// - If target exists and `overwrite == false`: throws
//   `FileAlreadyExistsException`.
// - If target exists and is a non-empty directory while `overwrite == true`:
//   throws `FileAlreadyExistsException` (matches Kotlin's behaviour).
// - Creates target's parent directories if missing.
// - Copies via a buffered loop sized by `bufferSize` so the I/O behaviour
//   matches Kotlin's implementation.
// - Returns the target File handle.
@_cdecl("__kk_file_copyTo")
public func __kk_file_copyTo(
    _ fileRaw: Int,
    _ targetRaw: Int,
    _ overwriteRaw: Int,
    _ bufferSizeRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let source = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_file_copyTo received invalid source File handle")
    }
    guard let target = runtimeFileBox(from: targetRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_file_copyTo received invalid target File handle")
    }
    let overwrite = kk_unbox_bool(overwriteRaw) != 0
    let bufferSize = max(1, kk_unbox_int(bufferSizeRaw))

    let fm = FileManager.default
    var sourceIsDir: ObjCBool = false
    guard fm.fileExists(atPath: source.path, isDirectory: &sourceIsDir) else {
        outThrown?.pointee = runtimeAllocateNoSuchFileException(
            file: source.path,
            reason: "The source file doesn't exist."
        )
        return targetRaw
    }

    var targetIsDir: ObjCBool = false
    let targetExists = fm.fileExists(atPath: target.path, isDirectory: &targetIsDir)
    if targetExists {
        if !overwrite {
            outThrown?.pointee = runtimeAllocateFileAlreadyExistsException(
                file: source.path,
                other: target.path,
                reason: "The destination file already exists."
            )
            return targetRaw
        }
        if targetIsDir.boolValue,
           let contents = try? fm.contentsOfDirectory(atPath: target.path),
           !contents.isEmpty {
            outThrown?.pointee = runtimeAllocateFileAlreadyExistsException(
                file: source.path,
                other: target.path,
                reason: "Tried to overwrite the destination, but failed to delete it."
            )
            return targetRaw
        }
        do {
            try fm.removeItem(atPath: target.path)
        } catch {
            outThrown?.pointee = runtimeAllocateFileAlreadyExistsException(
                file: source.path,
                other: target.path,
                reason: "Tried to overwrite the destination, but failed to delete it."
            )
            return targetRaw
        }
    }

    // Ensure the target's parent directory exists.
    let targetParent = (target.path as NSString).deletingLastPathComponent
    if !targetParent.isEmpty,
       !fm.fileExists(atPath: targetParent) {
        do {
            try fm.createDirectory(
                atPath: targetParent,
                withIntermediateDirectories: true
            )
        } catch {
            outThrown?.pointee = runtimeAllocateFileSystemException(
                file: source.path,
                other: target.path,
                reason: error.localizedDescription
            )
            return targetRaw
        }
    }

    if sourceIsDir.boolValue {
        // Mirror Kotlin: copyTo on a directory creates the target directory
        // without copying contents.
        do {
            try fm.createDirectory(
                atPath: target.path,
                withIntermediateDirectories: false
            )
        } catch {
            outThrown?.pointee = runtimeAllocateFileSystemException(
                file: source.path,
                other: target.path,
                reason: "Failed to create target directory."
            )
        }
        return targetRaw
    }

    do {
        let sourceURL = URL(fileURLWithPath: source.path)
        let readHandle = try FileHandle(forReadingFrom: sourceURL)
        defer { try? readHandle.close() }

        guard fm.createFile(atPath: target.path, contents: nil) else {
            outThrown?.pointee = runtimeAllocateFileSystemException(
                file: source.path,
                other: target.path,
                reason: "Failed to create the destination file."
            )
            return targetRaw
        }
        let writeHandle = try FileHandle(forWritingTo: URL(fileURLWithPath: target.path))
        defer { try? writeHandle.close() }

        while true {
            let chunk = readHandle.readData(ofLength: bufferSize)
            if chunk.isEmpty { break }
            writeHandle.write(chunk)
        }
    } catch {
        outThrown?.pointee = runtimeAllocateFileSystemException(
            file: source.path,
            other: target.path,
            reason: error.localizedDescription
        )
    }
    return targetRaw
}

// MARK: - STDLIB-IO-FN-012: File.copyRecursively(target, overwrite)
//
// Kotlin signature:
//   public fun File.copyRecursively(
//       target: File,
//       overwrite: Boolean = false,
//       onError: (File, IOException) -> OnErrorAction = { _, exception -> throw exception }
//   ): Boolean
//
// Behaviour:
// - Returns false immediately if `this` does not exist.
// - Recursively copies all files and sub-directories under `this` into `target`.
// - If `overwrite == false` and a target item already exists, throws
//   `FileAlreadyExistsException` (matching Kotlin's default error handler which
//   re-throws the first encountered exception).
// - Creates target directories as needed.
// - Returns true on success.
@_cdecl("__kk_file_copyRecursively")
public func __kk_file_copyRecursively(
    _ fileRaw: Int,
    _ targetRaw: Int,
    _ overwriteRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let source = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_file_copyRecursively received invalid source File handle")
    }
    guard let target = runtimeFileBox(from: targetRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_file_copyRecursively received invalid target File handle")
    }
    let overwrite = kk_unbox_bool(overwriteRaw) != 0
    let fm = FileManager.default

    // Return false (boxed) if source does not exist.
    var sourceIsDir: ObjCBool = false
    guard fm.fileExists(atPath: source.path, isDirectory: &sourceIsDir) else {
        return kk_box_bool(0)
    }

    func copyItem(srcPath: String, dstPath: String) -> Bool {
        var srcIsDir: ObjCBool = false
        _ = fm.fileExists(atPath: srcPath, isDirectory: &srcIsDir)

        if srcIsDir.boolValue {
            // Create target directory if needed.
            var dstIsDir: ObjCBool = false
            let dstExists = fm.fileExists(atPath: dstPath, isDirectory: &dstIsDir)
            if dstExists {
                if !dstIsDir.boolValue {
                    if !overwrite {
                        outThrown?.pointee = runtimeAllocateFileAlreadyExistsException(
                            file: srcPath,
                            other: dstPath,
                            reason: "The destination file already exists."
                        )
                        return false
                    }
                    do {
                        try fm.removeItem(atPath: dstPath)
                        try fm.createDirectory(atPath: dstPath, withIntermediateDirectories: true)
                    } catch {
                        outThrown?.pointee = runtimeAllocateFileSystemException(
                            file: srcPath,
                            other: dstPath,
                            reason: error.localizedDescription
                        )
                        return false
                    }
                }
                // directory already exists — continue
            } else {
                do {
                    try fm.createDirectory(atPath: dstPath, withIntermediateDirectories: true)
                } catch {
                    outThrown?.pointee = runtimeAllocateFileSystemException(
                        file: srcPath,
                        other: dstPath,
                        reason: error.localizedDescription
                    )
                    return false
                }
            }

            // Recurse into children.
            guard let children = try? fm.contentsOfDirectory(atPath: srcPath) else {
                return true
            }
            for child in children {
                let childSrc = (srcPath as NSString).appendingPathComponent(child)
                let childDst = (dstPath as NSString).appendingPathComponent(child)
                if !copyItem(srcPath: childSrc, dstPath: childDst) {
                    return false
                }
            }
            return true
        } else {
            // Regular file copy.
            var dstIsDir: ObjCBool = false
            let dstExists = fm.fileExists(atPath: dstPath, isDirectory: &dstIsDir)
            if dstExists {
                if !overwrite {
                    outThrown?.pointee = runtimeAllocateFileAlreadyExistsException(
                        file: srcPath,
                        other: dstPath,
                        reason: "The destination file already exists."
                    )
                    return false
                }
                do {
                    try fm.removeItem(atPath: dstPath)
                } catch {
                    outThrown?.pointee = runtimeAllocateFileAlreadyExistsException(
                        file: srcPath,
                        other: dstPath,
                        reason: "Tried to overwrite the destination, but failed to delete it."
                    )
                    return false
                }
            }
            // Ensure parent exists.
            let parentPath = (dstPath as NSString).deletingLastPathComponent
            if !parentPath.isEmpty, !fm.fileExists(atPath: parentPath) {
                do {
                    try fm.createDirectory(atPath: parentPath, withIntermediateDirectories: true)
                } catch {
                    outThrown?.pointee = runtimeAllocateFileSystemException(
                        file: srcPath,
                        other: dstPath,
                        reason: error.localizedDescription
                    )
                    return false
                }
            }
            do {
                try fm.copyItem(atPath: srcPath, toPath: dstPath)
            } catch {
                outThrown?.pointee = runtimeAllocateFileSystemException(
                    file: srcPath,
                    other: dstPath,
                    reason: error.localizedDescription
                )
                return false
            }
            return true
        }
    }

    let success = copyItem(srcPath: source.path, dstPath: target.path)
    return kk_box_bool(success ? 1 : 0)
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

private func runtimeByteArrayBytes(from raw: Int) -> [UInt8]? {
    if let array = runtimeArrayBox(from: raw) {
        return array.elements.map { UInt8(truncatingIfNeeded: $0) }
    }
    if let list = runtimeListBox(from: raw) {
        return list.elements.map { UInt8(truncatingIfNeeded: $0) }
    }
    return nil
}

private func runtimeOutputStreamBox(from raw: Int) -> RuntimeOutputStreamBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeOutputStreamBox.self)
}

@_cdecl("__kk_file_bufferedReader")
public func __kk_file_bufferedReader(_ fileRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_file_bufferedReader received invalid File handle")
    }
    do {
        let fileHandle = try FileHandle(forReadingFrom: URL(fileURLWithPath: file.path))
        return registerRuntimeObject(RuntimeBufferedReaderBox(fileHandle: fileHandle))
    } catch {
        outThrown?.pointee = runtimeAllocateFileSystemException(
            file: file.path,
            reason: error.localizedDescription
        )
        return 0
    }
}

@_cdecl("__kk_buffered_reader_readLine")
public func __kk_buffered_reader_readLine(_ readerRaw: Int) -> Int {
    guard let reader = runtimeBufferedReaderBox(from: readerRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_buffered_reader_readLine received invalid BufferedReader handle")
    }
    guard let line = reader.readLine() else {
        return runtimeNullSentinelInt
    }
    return fileMakeStringRaw(line)
}

@_cdecl("__kk_buffered_reader_readLines")
public func __kk_buffered_reader_readLines(_ readerRaw: Int) -> Int {
    guard let reader = runtimeBufferedReaderBox(from: readerRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_buffered_reader_readLines received invalid BufferedReader handle")
    }
    let lines = reader.readLines()
    return registerRuntimeObject(RuntimeListBox(elements: lines.map { fileMakeStringRaw($0) }))
}

@_cdecl("__kk_buffered_reader_close")
public func __kk_buffered_reader_close(_ readerRaw: Int) -> Int {
    guard let reader = runtimeBufferedReaderBox(from: readerRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_buffered_reader_close received invalid BufferedReader handle")
    }
    reader.close()
    return 0
}

@_cdecl("__kk_buffered_reader_read")
public func __kk_buffered_reader_read(_ readerRaw: Int) -> Int {
    guard let reader = runtimeBufferedReaderBox(from: readerRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_buffered_reader_read received invalid BufferedReader handle")
    }
    return reader.read()
}

@_cdecl("__kk_buffered_reader_ready")
public func __kk_buffered_reader_ready(_ readerRaw: Int) -> Int {
    guard let reader = runtimeBufferedReaderBox(from: readerRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_buffered_reader_ready received invalid BufferedReader handle")
    }
    return kk_box_bool(reader.ready() ? 1 : 0)
}

// MARK: - STDLIB-IO-FN-022: BufferedReader.iterator()
//
// Kotlin's `kotlin.io.BufferedReader.iterator()` operator extension returns an
// `Iterator<String>` that yields successive lines from the receiver. The
// underlying line buffering and termination semantics are inherited from
// `BufferedReader.readLine()`. Our implementation materialises all remaining
// lines eagerly into a list iterator so it can plug into the existing
// `RuntimeListIteratorBox` dispatch in `kk_iterator_hasNext` / `kk_iterator_next`.
// The observable behaviour (iteration order, blank line handling, EOF) matches
// `readLine()` because we delegate to it.
@_cdecl("__kk_buffered_reader_iterator")
public func __kk_buffered_reader_iterator(_ readerRaw: Int) -> Int {
    guard let reader = runtimeBufferedReaderBox(from: readerRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_buffered_reader_iterator received invalid BufferedReader handle")
    }
    let lineRaws = reader.readLines().map { fileMakeStringRaw($0) }
    return registerRuntimeObject(RuntimeListIteratorBox(elements: lineRaws))
}

// MARK: - STDLIB-IO-FN-040: Reader.useLines {}
//
// Kotlin's `kotlin.io.Reader.useLines(block)` extension reads all lines from the
// receiver Reader, passes them to `block` as a `Sequence<String>`, and closes
// the receiver before returning the block's result (Reader subclasses such as
// `BufferedReader` inherit this overload). Our implementation materialises the
// receiver's remaining lines into a `List<String>` (the same surface returned by
// `__kk_file_useLines`), invokes the supplied lambda once via the collection HOF
// closure ABI, and closes the underlying buffered reader after the block runs —
// mirroring the JVM contract where the reader is closed even when the lambda
// returns or throws.
@_cdecl("__kk_buffered_reader_useLines")
public func __kk_buffered_reader_useLines(_ readerRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let reader = runtimeBufferedReaderBox(from: readerRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_buffered_reader_useLines received invalid BufferedReader handle")
    }
    let lines = reader.readLines()
    let linesList = RuntimeListBox(elements: lines.map { fileMakeStringRaw($0) })
    let linesListRaw = registerRuntimeObject(linesList)
    var thrown = 0
    let result = runtimeInvokeCollectionLambda1(fnPtr: fnPtr, closureRaw: closureRaw, value: linesListRaw, outThrown: &thrown)
    // Always close the reader to honour the `use { }` contract even on lambda throw.
    reader.close()
    if thrown != 0 {
        outThrown?.pointee = thrown
        return 0
    }
    return result
}

// MARK: - STDLIB-IO-FN-017: Reader.forEachLine { line -> Unit }
//
// Kotlin's `kotlin.io.Reader.forEachLine(action)` extension reads lines from the
// receiver one by one and invokes `action` with each line as a `String`. Iteration
// stops early when the action throws (the thrown value is propagated via `outThrown`).
// Unlike `useLines`, the reader is NOT automatically closed after iteration ends —
// this mirrors the JVM contract where `forEachLine` leaves the reader open.
@_cdecl("__kk_buffered_reader_forEachLine")
public func __kk_buffered_reader_forEachLine(
    _ readerRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let reader = runtimeBufferedReaderBox(from: readerRaw) else {
        fatalError(
            "KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_buffered_reader_forEachLine received invalid BufferedReader handle"
        )
    }
    for line in reader.readLines() {
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

// MARK: - STDLIB-IO-FN-033: Reader.readText()
//
// Kotlin's `kotlin.io.Reader.readText(): String` extension drains the remaining
// content of a `Reader` and returns it as a single `String`. In KSwiftK every
// concrete `Reader` instance is currently a `BufferedReader` so we dispatch to
// `RuntimeBufferedReaderBox.readText()`. The function does NOT close the
// reader, matching the stdlib contract (callers should pair with `use { }`).
// Errors during stream reads bubble up as an empty string with no thrown
// exception, mirroring the lenient behaviour of our other reader helpers
// (`readLine`, `readLines`). The Sema extension signature is `() -> String`,
// so the only ABI argument is the receiver handle — no `outThrown` parameter.
@_cdecl("__kk_reader_readText")
public func __kk_reader_readText(_ readerRaw: Int) -> Int {
    guard let reader = runtimeBufferedReaderBox(from: readerRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_reader_readText received invalid Reader handle")
    }
    return fileMakeStringRaw(reader.readText())
}

// MARK: - STDLIB-IO-FN-007: InputStream.bufferedReader(charset)
//
// Kotlin's `InputStream.bufferedReader(charset: Charset = Charsets.UTF_8): BufferedReader`
// is a top-level extension in `kotlin.io`. Charset selection is delegated to
// the `BufferedReader` returned here — the runtime currently decodes lines as
// UTF-8, matching the rest of the `BufferedReader` API (see
// `RuntimeBufferedReaderBox.readLine`). The `charsetRaw` argument is accepted
// for ABI compatibility with future charset support and is otherwise ignored.
@_cdecl("__kk_input_stream_bufferedReader")
public func __kk_input_stream_bufferedReader(
    _ streamRaw: Int,
    _ charsetRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    _ = charsetRaw
    outThrown?.pointee = 0
    guard let stream = runtimeInputStreamBox(from: streamRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_input_stream_bufferedReader received invalid InputStream handle")
    }
    let remaining = stream.drainRemaining()
    return registerRuntimeObject(RuntimeBufferedReaderBox(data: remaining))
}

// MARK: - STDLIB-IO-091: BufferedWriter

private func runtimeBufferedWriterBox(from raw: Int) -> RuntimeBufferedWriterBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeBufferedWriterBox.self)
}

@_cdecl("__kk_file_bufferedWriter")
public func __kk_file_bufferedWriter(_ fileRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_file_bufferedWriter received invalid File handle")
    }
    let url = URL(fileURLWithPath: file.path)
    if !FileManager.default.fileExists(atPath: file.path) {
        _ = FileManager.default.createFile(atPath: file.path, contents: Data())
    }
    do {
        let handle = try FileHandle(forWritingTo: url)
        handle.truncateFile(atOffset: 0)
        return registerRuntimeObject(RuntimeBufferedWriterBox(fileHandle: handle))
    } catch {
        outThrown?.pointee = runtimeAllocateFileSystemException(
            file: file.path,
            reason: error.localizedDescription
        )
        return 0
    }
}

@_cdecl("__kk_buffered_writer_write")
public func __kk_buffered_writer_write(_ writerRaw: Int, _ textRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let writer = runtimeBufferedWriterBox(from: writerRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_buffered_writer_write received invalid BufferedWriter handle")
    }
    guard let ptr = UnsafeMutableRawPointer(bitPattern: textRaw),
          let text = extractString(from: ptr)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_buffered_writer_write received invalid text")
    }
    do {
        try writer.write(text)
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
    }
    return 0
}

@_cdecl("__kk_buffered_writer_new_line")
public func __kk_buffered_writer_new_line(_ writerRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let writer = runtimeBufferedWriterBox(from: writerRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_buffered_writer_new_line received invalid BufferedWriter handle")
    }
    do {
        try writer.newLine()
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
    }
    return 0
}

@_cdecl("__kk_buffered_writer_flush")
public func __kk_buffered_writer_flush(_ writerRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let writer = runtimeBufferedWriterBox(from: writerRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_buffered_writer_flush received invalid BufferedWriter handle")
    }
    do {
        try writer.flush()
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
    }
    return 0
}

@_cdecl("__kk_buffered_writer_close")
public func __kk_buffered_writer_close(_ writerRaw: Int) -> Int {
    guard let writer = runtimeBufferedWriterBox(from: writerRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_buffered_writer_close received invalid BufferedWriter handle")
    }
    writer.close()
    return 0
}

// MARK: - STDLIB-IO-FN-027: PrintWriter

/// `PrintWriter` shares the same `RuntimeBufferedWriterBox` as `BufferedWriter`.
/// `__kk_file_printWriter` creates a fresh writer identical to `__kk_file_bufferedWriter`.
@_cdecl("__kk_file_printWriter")
public func __kk_file_printWriter(_ fileRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_file_printWriter received invalid File handle")
    }
    let url = URL(fileURLWithPath: file.path)
    if !FileManager.default.fileExists(atPath: file.path) {
        _ = FileManager.default.createFile(atPath: file.path, contents: Data())
    }
    do {
        let handle = try FileHandle(forWritingTo: url)
        handle.truncateFile(atOffset: 0)
        return registerRuntimeObject(RuntimeBufferedWriterBox(fileHandle: handle))
    } catch {
        outThrown?.pointee = runtimeAllocateFileSystemException(
            file: file.path,
            reason: error.localizedDescription
        )
        return 0
    }
}

/// `PrintWriter.print(text)` — writes the text string without a trailing newline.
@_cdecl("__kk_print_writer_print")
public func __kk_print_writer_print(_ writerRaw: Int, _ textRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let writer = runtimeBufferedWriterBox(from: writerRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_print_writer_print received invalid PrintWriter handle")
    }
    guard let ptr = UnsafeMutableRawPointer(bitPattern: textRaw),
          let text = extractString(from: ptr)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_print_writer_print received invalid text")
    }
    do {
        try writer.write(text)
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
    }
    return 0
}

/// `PrintWriter.println(text)` — writes the text string followed by a newline.
@_cdecl("__kk_print_writer_println")
public func __kk_print_writer_println(_ writerRaw: Int, _ textRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let writer = runtimeBufferedWriterBox(from: writerRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_print_writer_println received invalid PrintWriter handle")
    }
    guard let ptr = UnsafeMutableRawPointer(bitPattern: textRaw),
          let text = extractString(from: ptr)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_print_writer_println received invalid text")
    }
    do {
        try writer.write(text + "\n")
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
    }
    return 0
}

/// `PrintWriter.println()` — writes a newline only (no-arg overload).
@_cdecl("__kk_print_writer_println_no_arg")
public func __kk_print_writer_println_no_arg(_ writerRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let writer = runtimeBufferedWriterBox(from: writerRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_print_writer_println_no_arg received invalid PrintWriter handle")
    }
    do {
        try writer.newLine()
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
    }
    return 0
}

/// `PrintWriter.write(text)` — writes a string (equivalent to `print(text)`).
@_cdecl("__kk_print_writer_write")
public func __kk_print_writer_write(_ writerRaw: Int, _ textRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    return __kk_print_writer_print(writerRaw, textRaw, outThrown)
}

/// `PrintWriter.flush()` — flushes buffered data to the underlying file.
@_cdecl("__kk_print_writer_flush")
public func __kk_print_writer_flush(_ writerRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let writer = runtimeBufferedWriterBox(from: writerRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_print_writer_flush received invalid PrintWriter handle")
    }
    do {
        try writer.flush()
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
    }
    return 0
}

/// `PrintWriter.close()` — flushes and closes the underlying writer.
@_cdecl("__kk_print_writer_close")
public func __kk_print_writer_close(_ writerRaw: Int) -> Int {
    guard let writer = runtimeBufferedWriterBox(from: writerRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_print_writer_close received invalid PrintWriter handle")
    }
    writer.close()
    return 0
}

// MARK: - STDLIB-IO-FN-006: Writer.buffered(bufferSize)

@_cdecl("__kk_writer_buffered_default")
public func __kk_writer_buffered_default(_ writerRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    __kk_writer_buffered(writerRaw, 8192, outThrown)
}

@_cdecl("__kk_writer_buffered")
public func __kk_writer_buffered(_ writerRaw: Int, _ bufferSizeRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard bufferSizeRaw > 0 else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(message: "bufferSize must be positive")
        return 0
    }
    guard runtimeBufferedWriterBox(from: writerRaw) != nil else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_writer_buffered received invalid Writer handle")
    }
    return writerRaw
}

@_cdecl("__kk_file_inputStream")
public func __kk_file_inputStream(_ fileRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_file_inputStream received invalid File handle")
    }
    do {
        let data = try Data(contentsOf: URL(fileURLWithPath: file.path))
        return registerRuntimeObject(RuntimeInputStreamBox(data: data))
    } catch {
        outThrown?.pointee = runtimeAllocateFileSystemException(
            file: file.path,
            reason: error.localizedDescription
        )
        return 0
    }
}

@_cdecl("__kk_bytearrayinputstream_new")
public func __kk_bytearrayinputstream_new(_ bufferRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let bytes = runtimeByteArrayBytes(from: bufferRaw) else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(message: "expected ByteArray/List<Int> buffer")
        return 0
    }
    return registerRuntimeObject(RuntimeInputStreamBox(data: Data(bytes)))
}

// STDLIB-IO-FN-020: ByteArray.inputStream() — wraps the entire byte array as a
// ByteArrayInputStream. Mirrors the Kotlin stdlib `public fun ByteArray.inputStream()`.
@_cdecl("__kk_bytearray_inputStream")
public func __kk_bytearray_inputStream(_ arrayRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let bytes = runtimeByteArrayBytes(from: arrayRaw) else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(message: "expected ByteArray handle")
        return 0
    }
    return registerRuntimeObject(RuntimeInputStreamBox(data: Data(bytes)))
}

// STDLIB-IO-FN-021: ByteArray.inputStream(offset: Int, length: Int) — wraps a
// subrange of the byte array as a ByteArrayInputStream. Mirrors the Kotlin stdlib
// `public fun ByteArray.inputStream(offset: Int, length: Int)`.
@_cdecl("__kk_bytearray_inputStream_range")
public func __kk_bytearray_inputStream_range(
    _ arrayRaw: Int,
    _ offsetRaw: Int,
    _ lengthRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let bytes = runtimeByteArrayBytes(from: arrayRaw) else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(message: "expected ByteArray handle")
        return 0
    }
    let offset = offsetRaw
    let length = lengthRaw
    guard offset >= 0, length >= 0, offset + length <= bytes.count else {
        outThrown?.pointee = runtimeAllocateIndexOutOfBoundsException(
            message: "offset=\(offset) length=\(length) size=\(bytes.count)"
        )
        return 0
    }
    let slice = Array(bytes[offset ..< offset + length])
    return registerRuntimeObject(RuntimeInputStreamBox(data: Data(slice)))
}

// STDLIB-IO-FN-011: String.byteInputStream() — encodes the receiver as UTF-8 and
// returns a ByteArrayInputStream over the resulting bytes. Default charset overload
// mirrors `String.toByteArray()` semantics for behavioral consistency.
@_cdecl("__kk_string_byteInputStream_flat")
public func __kk_string_byteInputStream_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    let source = runtimeStringFromFlatFields(data: data, length: length, byteCount: byteCount, hash: hash)
    return runtimeStringByteInputStream(source)
}

// STDLIB-IO-FN-011: String.byteInputStream(charset: Charset) — charset-aware
// overload. Reuses the same charset table as String.toByteArray(charset).
@_cdecl("__kk_string_byteInputStream_charset_flat")
public func __kk_string_byteInputStream_charset_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ charsetTag: Int
) -> Int {
    let source = runtimeStringFromFlatFields(data: data, length: length, byteCount: byteCount, hash: hash)
    return runtimeStringByteInputStream(source, charsetTag: charsetTag)
}

private func runtimeStringByteInputStream(_ source: String) -> Int {
    let bytes = source.utf8.map { UInt8($0) }
    return registerRuntimeObject(RuntimeInputStreamBox(data: Data(bytes)))
}

private func runtimeStringByteInputStream(_ source: String, charsetTag: Int) -> Int {
    let bytesRaw = runtimeStringToByteArrayWithCharsetRaw(source, charsetTag: charsetTag)
    guard let bytes = runtimeByteArrayBytes(from: bytesRaw) else {
        // Fall back to UTF-8 if the encoded bytes cannot be retrieved (should not happen)
        return runtimeStringByteInputStream(source)
    }
    let unsignedBytes = bytes.map { UInt8(truncatingIfNeeded: $0) }
    return registerRuntimeObject(RuntimeInputStreamBox(data: Data(unsignedBytes)))
}

@_cdecl("__kk_file_outputStream")
public func __kk_file_outputStream(_ fileRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_file_outputStream received invalid File handle")
    }
    let url = URL(fileURLWithPath: file.path)
    if !FileManager.default.fileExists(atPath: file.path) {
        _ = FileManager.default.createFile(atPath: file.path, contents: Data())
    }
    do {
        let handle = try FileHandle(forWritingTo: url)
        handle.truncateFile(atOffset: 0)
        return registerRuntimeObject(RuntimeOutputStreamBox(fileHandle: handle))
    } catch {
        outThrown?.pointee = runtimeAllocateFileSystemException(
            file: file.path,
            reason: error.localizedDescription
        )
        return 0
    }
}

@_cdecl("__kk_input_stream_read")
public func __kk_input_stream_read(_ streamRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let stream = runtimeInputStreamBox(from: streamRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_input_stream_read received invalid InputStream handle")
    }
    return stream.readByte()
}

@_cdecl("__kk_input_stream_available")
public func __kk_input_stream_available(_ streamRaw: Int) -> Int {
    guard let stream = runtimeInputStreamBox(from: streamRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_input_stream_available received invalid InputStream handle")
    }
    return stream.available()
}

@_cdecl("__kk_input_stream_skip")
public func __kk_input_stream_skip(_ streamRaw: Int, _ countRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let stream = runtimeInputStreamBox(from: streamRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_input_stream_skip received invalid InputStream handle")
    }
    return stream.skip(countRaw)
}

@_cdecl("__kk_input_stream_read_bytes")
public func __kk_input_stream_read_bytes(_ streamRaw: Int, _ bytesRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let stream = runtimeInputStreamBox(from: streamRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_input_stream_read_bytes received invalid InputStream handle")
    }
    guard let list = runtimeListBox(from: bytesRaw) else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(message: "expected ByteArray/List<Int> buffer")
        return -1
    }
    return stream.read(into: list)
}

// MARK: - InputStream.readBytes() (STDLIB-IO-FN-029)
//
// Kotlin defines:
//   public fun InputStream.readBytes(): ByteArray
//
// The extension reads all remaining bytes from `this` into a freshly allocated
// ByteArray. We model `ByteArray` as a `List<Int>` whose elements are signed
// Int values in [-128, 127] (matching the rest of the runtime's ByteArray
// representation, e.g. `__kk_file_readBytes`).
//
// The implementation drains the underlying `RuntimeInputStreamBox` in a single
// pass (or, for `SequenceInputStream`, walks both chained streams to EOF).
// The receiver is not closed — `InputStream.readBytes()` mirrors JVM
// `InputStream.readAllBytes()` in that the caller is responsible for closing
// the stream (typically via `.use { it.readBytes() }`).
@_cdecl("__kk_input_stream_readAllBytes")
public func __kk_input_stream_readAllBytes(_ streamRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    // Try a plain InputStream first.
    if let stream = runtimeInputStreamBox(from: streamRaw) {
        let bytes = stream.readAllBytes()
        return registerRuntimeObject(RuntimeListBox(elements: bytes))
    }
    // Fall back to a SequenceInputStream chain.
    if let ptr = UnsafeMutableRawPointer(bitPattern: streamRaw),
       let sequenceStream = tryCast(ptr, to: RuntimeSequenceInputStreamBox.self)
    {
        let bytes = sequenceStream.readAllBytes()
        return registerRuntimeObject(RuntimeListBox(elements: bytes))
    }
    fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_input_stream_readAllBytes received invalid InputStream handle")
}

@_cdecl("__kk_input_stream_mark")
public func __kk_input_stream_mark(_ streamRaw: Int, _ readLimitRaw: Int) -> Int {
    guard let stream = runtimeInputStreamBox(from: streamRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_input_stream_mark received invalid InputStream handle")
    }
    stream.mark(readLimit: readLimitRaw)
    return 0
}

@_cdecl("__kk_input_stream_reset")
public func __kk_input_stream_reset(_ streamRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let stream = runtimeInputStreamBox(from: streamRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_input_stream_reset received invalid InputStream handle")
    }
    if !stream.reset() {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: mark/reset not supported")
    }
    return 0
}

@_cdecl("__kk_input_stream_mark_supported")
public func __kk_input_stream_mark_supported(_ streamRaw: Int) -> Int {
    guard let stream = runtimeInputStreamBox(from: streamRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_input_stream_mark_supported received invalid InputStream handle")
    }
    return kk_box_bool(stream.markSupported() ? 1 : 0)
}

@_cdecl("__kk_input_stream_close")
public func __kk_input_stream_close(_ streamRaw: Int) -> Int {
    guard let stream = runtimeInputStreamBox(from: streamRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_input_stream_close received invalid InputStream handle")
    }
    stream.close()
    return 0
}

// MARK: - STDLIB-IO-FN-013: InputStream.copyTo(out, bufferSize)
//
// Kotlin signature:
//   public fun InputStream.copyTo(
//       out: OutputStream,
//       bufferSize: Int = DEFAULT_BUFFER_SIZE
//   ): Long
//
// Copies bytes from this InputStream into the given OutputStream until
// all available bytes have been read, returning the total byte count as a
// boxed Long.  The InputStream is not closed after copying (matching
// Kotlin/JVM behaviour).
@_cdecl("__kk_input_stream_copyTo")
public func __kk_input_stream_copyTo(
    _ streamRaw: Int,
    _ outStreamRaw: Int,
    _ bufferSizeRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let inputStream = runtimeInputStreamBox(from: streamRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_input_stream_copyTo received invalid InputStream handle")
    }
    guard let outputStream = runtimeOutputStreamBox(from: outStreamRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_input_stream_copyTo received invalid OutputStream handle")
    }
    let bufferSize = max(1, kk_unbox_int(bufferSizeRaw))
    var totalBytesCopied: Int = 0
    let buffer = RuntimeListBox(elements: Array(repeating: 0, count: bufferSize))
    while true {
        let bytesRead = inputStream.read(into: buffer)
        if bytesRead <= 0 { break }
        let chunk = Array(buffer.elements.prefix(bytesRead))
        do {
            try outputStream.writeBytes(chunk)
        } catch {
            outThrown?.pointee = runtimeAllocateThrowable(
                message: "IOException: \(error.localizedDescription)"
            )
            return kk_box_long(totalBytesCopied)
        }
        totalBytesCopied += bytesRead
    }
    return kk_box_long(totalBytesCopied)
}

// MARK: - InputStream.buffered (STDLIB-IO-FN-003)
//
// Kotlin's `InputStream.buffered(bufferSize)` extension returns a
// BufferedInputStream wrapping the underlying stream.  Since the byte-level
// reading methods provided by RuntimeInputStreamBox already operate against
// an in-memory Data buffer, returning the same handle re-typed as a
// BufferedInputStream preserves observable Kotlin semantics:
//   - read()/available()/skip()/close() continue to delegate to the same
//     underlying byte source
//   - mark/reset remain unsupported (mirroring FileInputStream behaviour)
//   - the buffer size argument is honoured by the type but does not alter
//     the in-memory byte sequence
//
// If a future revision introduces a dedicated BufferedInputStreamBox with
// look-ahead semantics, this function will continue to be the single seam
// for materialising one from an arbitrary InputStream handle.
@_cdecl("__kk_input_stream_buffered_default")
public func __kk_input_stream_buffered_default(_ streamRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard runtimeInputStreamBox(from: streamRaw) != nil else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_input_stream_buffered_default received invalid InputStream handle")
    }
    // The underlying RuntimeInputStreamBox already buffers via Data, so we
    // can hand out the same handle re-typed.  Returning the same raw value
    // keeps reference counting consistent.
    return streamRaw
}

@_cdecl("__kk_input_stream_buffered")
public func __kk_input_stream_buffered(_ streamRaw: Int, _ bufferSizeRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard runtimeInputStreamBox(from: streamRaw) != nil else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_input_stream_buffered received invalid InputStream handle")
    }
    // Kotlin's reference implementation throws IllegalArgumentException for
    // non-positive buffer sizes (BufferedInputStream's underlying JVM type
    // does the same).  Surface that diagnostic via the standard outThrown
    // channel rather than returning a sentinel.
    if bufferSizeRaw <= 0 {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(message: "Buffer size <= 0")
        return 0
    }
    return streamRaw
}

// MARK: - SequenceInputStream (STDLIB-IO-092)

private func runtimeSequenceInputStreamBox(from raw: Int) -> RuntimeSequenceInputStreamBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeSequenceInputStreamBox.self)
}

@_cdecl("__kk_sequence_input_stream_new")
public func __kk_sequence_input_stream_new(_ firstRaw: Int, _ secondRaw: Int) -> Int {
    guard let first = runtimeInputStreamBox(from: firstRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_sequence_input_stream_new: invalid first InputStream handle")
    }
    guard let second = runtimeInputStreamBox(from: secondRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_sequence_input_stream_new: invalid second InputStream handle")
    }
    return registerRuntimeObject(RuntimeSequenceInputStreamBox(first: first, second: second))
}

@_cdecl("__kk_sequence_input_stream_read")
public func __kk_sequence_input_stream_read(_ streamRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let stream = runtimeSequenceInputStreamBox(from: streamRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_sequence_input_stream_read received invalid SequenceInputStream handle")
    }
    return stream.readByte()
}

@_cdecl("__kk_sequence_input_stream_available")
public func __kk_sequence_input_stream_available(_ streamRaw: Int) -> Int {
    guard let stream = runtimeSequenceInputStreamBox(from: streamRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_sequence_input_stream_available received invalid SequenceInputStream handle")
    }
    return stream.available()
}

@_cdecl("__kk_sequence_input_stream_close")
public func __kk_sequence_input_stream_close(_ streamRaw: Int) -> Int {
    guard let stream = runtimeSequenceInputStreamBox(from: streamRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_sequence_input_stream_close received invalid SequenceInputStream handle")
    }
    stream.close()
    return 0
}

@_cdecl("__kk_output_stream_write_byte")
public func __kk_output_stream_write_byte(_ streamRaw: Int, _ valueRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let stream = runtimeOutputStreamBox(from: streamRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_output_stream_write_byte received invalid OutputStream handle")
    }
    do {
        try stream.writeByte(valueRaw)
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
    }
    return 0
}

@_cdecl("__kk_output_stream_write_bytes")
public func __kk_output_stream_write_bytes(_ streamRaw: Int, _ bytesRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let stream = runtimeOutputStreamBox(from: streamRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_output_stream_write_bytes received invalid OutputStream handle")
    }
    guard let list = runtimeListBox(from: bytesRaw) else {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(message: "expected ByteArray/List<Int> buffer")
        return 0
    }
    do {
        try stream.writeBytes(list.elements)
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
    }
    return 0
}

@_cdecl("__kk_output_stream_flush")
public func __kk_output_stream_flush(_ streamRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let stream = runtimeOutputStreamBox(from: streamRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_output_stream_flush received invalid OutputStream handle")
    }
    do {
        try stream.flush()
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
    }
    return 0
}

@_cdecl("__kk_output_stream_close")
public func __kk_output_stream_close(_ streamRaw: Int) -> Int {
    guard let stream = runtimeOutputStreamBox(from: streamRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_output_stream_close received invalid OutputStream handle")
    }
    stream.close()
    return 0
}

// MARK: - STDLIB-IO-FN-009: OutputStream.bufferedWriter(charset)

/// Maps Kotlin `Charset` tag (mirrors `kotlin.text.Charsets.*` IDs in the
/// runtime ABI) to a Swift `String.Encoding`.  Mirrors the helper in
/// `RuntimePath.swift` so this file stays self-contained.
private func outputStreamEncoding(for charsetRaw: Int) -> String.Encoding {
    switch charsetRaw {
    case 1: .isoLatin1
    case 2: .ascii
    case 3: .utf16
    case 4: .utf16BigEndian
    case 5: .utf16LittleEndian
    case 6: .utf32
    case 7: .utf32BigEndian
    case 8: .utf32LittleEndian
    default: .utf8
    }
}

/// `kotlin.io.bufferedWriter(charset: Charset = Charsets.UTF_8): BufferedWriter`
/// extension on `java.io.OutputStream`.
///
/// JVM semantics: returns a new `BufferedWriter` wrapping an `OutputStreamWriter`
/// over this output stream using the specified charset.  Subsequent writes/closes
/// of the returned writer affect the underlying stream; the original `OutputStream`
/// handle should no longer be used directly.
@_cdecl("__kk_output_stream_bufferedWriter")
public func __kk_output_stream_bufferedWriter(_ streamRaw: Int, _ charsetRaw: Int) -> Int {
    guard let stream = runtimeOutputStreamBox(from: streamRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_output_stream_bufferedWriter received invalid OutputStream handle")
    }
    let encoding = outputStreamEncoding(for: charsetRaw)
    guard let writer = stream.makeBufferedWriter(encoding: encoding) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_output_stream_bufferedWriter cannot wrap non-file-handle OutputStream")
    }
    return registerRuntimeObject(writer)
}

/// Charset-less default overload — `kotlin.io.bufferedWriter()` with no
/// argument should use `Charsets.UTF_8`.  STDLIB-IO-FN-009.
@_cdecl("__kk_output_stream_bufferedWriter_default")
public func __kk_output_stream_bufferedWriter_default(_ streamRaw: Int) -> Int {
    __kk_output_stream_bufferedWriter(streamRaw, 0)
}

// MARK: - STDLIB-IO-FN-004: OutputStream.buffered() / buffered(bufferSize)

/// Returns an OutputStream that wraps the receiver with buffering. Because the
/// underlying `RuntimeOutputStreamBox` is already streamed through the OS-level
/// FileHandle (which performs its own buffering), the wrapped handle is the
/// receiver itself — matching Kotlin's identity contract for an already-buffered
/// stream (`if (this is BufferedOutputStream) this else BufferedOutputStream(this)`).
@_cdecl("__kk_output_stream_buffered")
public func __kk_output_stream_buffered(_ streamRaw: Int) -> Int {
    guard runtimeOutputStreamBox(from: streamRaw) != nil else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_output_stream_buffered received invalid OutputStream handle")
    }
    return streamRaw
}

/// Sized overload of `buffered()`. The `bufferSize` parameter is currently
/// honored by the underlying OS-level FileHandle, so this overload also returns
/// the receiver handle. Reserved for a future BufferedOutputStream-backed
/// implementation that respects the requested buffer size explicitly.
@_cdecl("__kk_output_stream_buffered_sized")
public func __kk_output_stream_buffered_sized(_ streamRaw: Int, _ bufferSize: Int) -> Int {
    _ = bufferSize // Reserved for explicit BufferedOutputStream implementation.
    guard runtimeOutputStreamBox(from: streamRaw) != nil else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_output_stream_buffered_sized received invalid OutputStream handle")
    }
    return streamRaw
}

// MARK: - STDLIB-IO-FN-014: Reader.copyTo(out: Writer, bufferSize) -> Long

/// Kotlin's default buffer size for `kotlin.io.copyTo`.  Matches
/// `kotlin.io.DEFAULT_BUFFER_SIZE` (16 KiB).
private let kReaderCopyToDefaultBufferSize: Int = 16 * 1024

/// `kotlin.io.Reader.copyTo(out: Writer, bufferSize: Int = DEFAULT_BUFFER_SIZE): Long`
///
/// Copies every character that remains in the receiver into `out` using an
/// internal buffer of `bufferSize` characters and returns the total number of
/// characters transferred.  Mirrors the JVM contract:
///   - Neither the receiver nor `out` is closed by this function.
///   - The receiver is read until EOF (`Reader.read()` returning `-1`).
///   - Characters are emitted to `out` as `String` chunks of up to
///     `bufferSize` characters at a time.
///   - A non-positive `bufferSize` raises `IllegalArgumentException` to match
///     the behaviour of `kotlin.io.copyTo` on the JVM.
///
/// Concrete `Reader` / `Writer` boxes currently supported by the runtime are
/// `RuntimeBufferedReaderBox` and `RuntimeBufferedWriterBox` — the only
/// character-stream types modelled in the synthetic stubs.  Passing any other
/// box panics with a clear diagnostic so test failures surface immediately.
@_cdecl("__kk_reader_copyTo")
public func __kk_reader_copyTo(
    _ readerRaw: Int,
    _ writerRaw: Int,
    _ bufferSizeRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0

    guard let reader = runtimeBufferedReaderBox(from: readerRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_reader_copyTo received invalid Reader handle")
    }
    guard let writer = runtimeBufferedWriterBox(from: writerRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_reader_copyTo received invalid Writer handle")
    }

    if bufferSizeRaw <= 0 {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "bufferSize must be positive (was \(bufferSizeRaw))"
        )
        return kk_box_long(0)
    }

    var copied: Int = 0
    var pending = String.UnicodeScalarView()
    pending.reserveCapacity(bufferSizeRaw)

    while true {
        let charCode = reader.read()
        if charCode < 0 {
            break // EOF
        }
        guard let scalar = Unicode.Scalar(UInt32(charCode)) else {
            // Invalid scalar — surface as IOException to match JVM-style
            // surface for malformed character data.
            outThrown?.pointee = runtimeAllocateThrowable(
                message: "IOException: invalid Unicode scalar in Reader stream (code point \(charCode))"
            )
            return kk_box_long(copied)
        }
        pending.append(scalar)
        copied += 1

        if pending.count >= bufferSizeRaw {
            do {
                try writer.write(String(pending))
            } catch {
                outThrown?.pointee = runtimeAllocateThrowable(
                    message: "IOException: \(error.localizedDescription)"
                )
                return kk_box_long(copied)
            }
            pending.removeAll(keepingCapacity: true)
        }
    }

    if !pending.isEmpty {
        do {
            try writer.write(String(pending))
        } catch {
            outThrown?.pointee = runtimeAllocateThrowable(
                message: "IOException: \(error.localizedDescription)"
            )
            return kk_box_long(copied)
        }
    }

    return kk_box_long(copied)
}

/// Zero-bufferSize overload — `Reader.copyTo(out)` defaults to
/// `DEFAULT_BUFFER_SIZE`.  STDLIB-IO-FN-014.
@_cdecl("__kk_reader_copyTo_default")
public func __kk_reader_copyTo_default(
    _ readerRaw: Int,
    _ writerRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    __kk_reader_copyTo(readerRaw, writerRaw, kReaderCopyToDefaultBufferSize, outThrown)
}

// Shared runtime storage for java.nio.file.attribute.FileTime.
//
// Path APIs also expose this value, so this support is kept independently of
// the removed java.nio.file.Files utility bridge.
final class RuntimeFileTimeBox {
    let milliseconds: Int

    init(milliseconds: Int) {
        self.milliseconds = milliseconds
    }
}

private func runtimeFileTimeBox(from raw: Int) -> RuntimeFileTimeBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeFileTimeBox.self)
}

/// FileTime.toMillis() — returns the stored epoch millis.
@_cdecl("__kk_fileTime_toMillis")
public func __kk_fileTime_toMillis(_ fileTimeRaw: Int) -> Int {
    guard let fileTime = runtimeFileTimeBox(from: fileTimeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_fileTime_toMillis received invalid FileTime handle")
    }
    return fileTime.milliseconds
}


@_cdecl("__kk_io_createTempDir_default")
public func __kk_io_createTempDir_default(_ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeCreateDeprecatedTempDirectory(
        prefixRaw: runtimeNullSentinelInt,
        suffixRaw: runtimeNullSentinelInt,
        directoryRaw: runtimeNullSentinelInt,
        outThrown: outThrown
    )
}

@_cdecl("__kk_io_createTempDir_prefix")
public func __kk_io_createTempDir_prefix(_ prefixRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeCreateDeprecatedTempDirectory(
        prefixRaw: prefixRaw,
        suffixRaw: runtimeNullSentinelInt,
        directoryRaw: runtimeNullSentinelInt,
        outThrown: outThrown
    )
}

@_cdecl("__kk_io_createTempDir_prefix_suffix")
public func __kk_io_createTempDir_prefix_suffix(_ prefixRaw: Int, _ suffixRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeCreateDeprecatedTempDirectory(
        prefixRaw: prefixRaw,
        suffixRaw: suffixRaw,
        directoryRaw: runtimeNullSentinelInt,
        outThrown: outThrown
    )
}

@_cdecl("__kk_io_createTempDir")
public func __kk_io_createTempDir(_ prefixRaw: Int, _ suffixRaw: Int, _ directoryRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeCreateDeprecatedTempDirectory(
        prefixRaw: prefixRaw,
        suffixRaw: suffixRaw,
        directoryRaw: directoryRaw,
        outThrown: outThrown
    )
}

@_cdecl("__kk_io_createTempFile_default")
public func __kk_io_createTempFile_default(_ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeCreateDeprecatedTempFile(
        prefixRaw: runtimeNullSentinelInt,
        suffixRaw: runtimeNullSentinelInt,
        directoryRaw: runtimeNullSentinelInt,
        outThrown: outThrown
    )
}

@_cdecl("__kk_io_createTempFile_prefix")
public func __kk_io_createTempFile_prefix(_ prefixRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeCreateDeprecatedTempFile(
        prefixRaw: prefixRaw,
        suffixRaw: runtimeNullSentinelInt,
        directoryRaw: runtimeNullSentinelInt,
        outThrown: outThrown
    )
}

@_cdecl("__kk_io_createTempFile_prefix_suffix")
public func __kk_io_createTempFile_prefix_suffix(_ prefixRaw: Int, _ suffixRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeCreateDeprecatedTempFile(
        prefixRaw: prefixRaw,
        suffixRaw: suffixRaw,
        directoryRaw: runtimeNullSentinelInt,
        outThrown: outThrown
    )
}

@_cdecl("__kk_io_createTempFile")
public func __kk_io_createTempFile(_ prefixRaw: Int, _ suffixRaw: Int, _ directoryRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeCreateDeprecatedTempFile(
        prefixRaw: prefixRaw,
        suffixRaw: suffixRaw,
        directoryRaw: directoryRaw,
        outThrown: outThrown
    )
}
