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
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: Failed to create temp file \(fullPath)")
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
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
    }
    return registerRuntimeObject(RuntimeFileBox(fullPath))
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

/// File(parent: String, child: String) constructor (STDLIB-IO-087)
@_cdecl("kk_file_new_parent_child")
public func kk_file_new_parent_child(_ parentRaw: Int, _ childRaw: Int) -> Int {
    guard let parentPtr = UnsafeMutableRawPointer(bitPattern: parentRaw),
          let parent = extractString(from: parentPtr)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_new_parent_child received invalid parent")
    }
    guard let childPtr = UnsafeMutableRawPointer(bitPattern: childRaw),
          let child = extractString(from: childPtr)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_new_parent_child received invalid child")
    }
    let path = (parent as NSString).appendingPathComponent(child)
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
    return registerRuntimeObject(RuntimeInputStreamBox(data: data))
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
    guard let stream = runtimeInputStreamBox(from: streamRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_resource_stream_read received invalid InputStream handle")
    }
    return stream.readByte()
}

@_cdecl("kk_resource_stream_close")
public func kk_resource_stream_close(_ streamRaw: Int) -> Int {
    guard let stream = runtimeInputStreamBox(from: streamRaw) else {
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

// MARK: - STDLIB-IO-FN-001: File.appendBytes(array: ByteArray)

@_cdecl("kk_file_appendBytes")
public func kk_file_appendBytes(_ fileRaw: Int, _ arrayRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_appendBytes received invalid File handle")
    }
    guard let list = runtimeListBox(from: arrayRaw) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IllegalArgumentException: expected ByteArray/List<Int> array")
        return 0
    }
    do {
        let bytes = list.elements.map { UInt8(bitPattern: Int8(truncatingIfNeeded: $0)) }
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
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
    }
    return 0
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

// STDLIB-IO-PROP-005: File.nameWithoutExtension extension property
// Returns the file name without an extension, equivalent to
// `name.substringBeforeLast(".")` in Kotlin. If the name has no extension
// (i.e. no '.' character), the full name is returned.
@_cdecl("kk_file_nameWithoutExtension")
public func kk_file_nameWithoutExtension(_ fileRaw: Int) -> Int {
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_nameWithoutExtension received invalid File handle")
    }
    let name = (file.path as NSString).lastPathComponent
    guard let dotIndex = name.lastIndex(of: ".") else {
        return fileMakeStringRaw(name)
    }
    return fileMakeStringRaw(String(name[..<dotIndex]))
}

@_cdecl("kk_file_path")
public func kk_file_path(_ fileRaw: Int) -> Int {
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_path received invalid File handle")
    }
    return fileMakeStringRaw(file.path)
}

// MARK: - STDLIB-IO-087: Additional File properties and operations

@_cdecl("kk_file_absolutePath")
public func kk_file_absolutePath(_ fileRaw: Int) -> Int {
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_absolutePath received invalid File handle")
    }
    let url = URL(fileURLWithPath: file.path)
    return fileMakeStringRaw(url.path)
}

@_cdecl("kk_file_canonicalPath")
public func kk_file_canonicalPath(_ fileRaw: Int) -> Int {
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_canonicalPath received invalid File handle")
    }
    let resolved = (file.path as NSString).standardizingPath
    return fileMakeStringRaw(resolved)
}

@_cdecl("kk_file_parent")
public func kk_file_parent(_ fileRaw: Int) -> Int {
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_parent received invalid File handle")
    }
    let parent = (file.path as NSString).deletingLastPathComponent
    // Return null sentinel if the path has no parent (e.g., root "/")
    if parent.isEmpty || parent == file.path {
        return runtimeNullSentinelInt
    }
    return fileMakeStringRaw(parent)
}

// MARK: - STDLIB-IO-PROP-003: File.invariantSeparatorsPath
//
// Kotlin signature: `public val File.invariantSeparatorsPath: String`
//
// Returns the file path string where the platform-specific separator character
// is replaced with the forward slash `/`. On POSIX platforms (macOS / Linux)
// the path is returned unchanged because the platform separator already is
// `/`; on Windows-style paths containing `\` the backslashes are replaced.
@_cdecl("kk_file_invariantSeparatorsPath")
public func kk_file_invariantSeparatorsPath(_ fileRaw: Int) -> Int {
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_invariantSeparatorsPath received invalid File handle")
    }
    return fileMakeStringRaw(file.path.replacingOccurrences(of: "\\", with: "/"))
}

@_cdecl("kk_file_length")
public func kk_file_length(_ fileRaw: Int) -> Int {
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_length received invalid File handle")
    }
    guard let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
          let size = attrs[.size] as? Int else {
        return 0
    }
    return size
}

@_cdecl("kk_file_lastModified")
public func kk_file_lastModified(_ fileRaw: Int) -> Int {
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_lastModified received invalid File handle")
    }
    guard let attrs = try? FileManager.default.attributesOfItem(atPath: file.path),
          let modDate = attrs[.modificationDate] as? Date else {
        return 0
    }
    // Kotlin returns milliseconds since epoch (Long)
    return Int(modDate.timeIntervalSince1970 * 1000)
}

@_cdecl("kk_file_createNewFile")
public func kk_file_createNewFile(_ fileRaw: Int) -> Int {
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_createNewFile received invalid File handle")
    }
    if FileManager.default.fileExists(atPath: file.path) {
        return kk_box_bool(0) // false: file already exists
    }
    let created = FileManager.default.createFile(atPath: file.path, contents: nil)
    return kk_box_bool(created ? 1 : 0)
}

@_cdecl("kk_file_canRead")
public func kk_file_canRead(_ fileRaw: Int) -> Int {
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_canRead received invalid File handle")
    }
    return kk_box_bool(FileManager.default.isReadableFile(atPath: file.path) ? 1 : 0)
}

@_cdecl("kk_file_canWrite")
public func kk_file_canWrite(_ fileRaw: Int) -> Int {
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_canWrite received invalid File handle")
    }
    return kk_box_bool(FileManager.default.isWritableFile(atPath: file.path) ? 1 : 0)
}

@_cdecl("kk_file_canExecute")
public func kk_file_canExecute(_ fileRaw: Int) -> Int {
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_canExecute received invalid File handle")
    }
    return kk_box_bool(FileManager.default.isExecutableFile(atPath: file.path) ? 1 : 0)
}

// MARK: - STDLIB-IO-FN-036: File.resolveSibling

/// Returns a new File whose path is formed by replacing the last component of
/// the receiver's path with `sibling`. Mirrors kotlin.io.File.resolveSibling:
///   - If the receiver has no parent (e.g. a bare file name like "foo.txt"), the
///     result is just `File(sibling)`.
///   - Otherwise the result is `File(parentDirectory + "/" + sibling)`.
private func fileResolveSiblingPath(base: String, sibling: String) -> String {
    // Trim trailing slashes so that "/a/b/" behaves like "/a/b"
    let trimmed = base.hasSuffix("/") && base.count > 1
        ? String(base.dropLast(1))
        : base
    guard let slashIndex = trimmed.lastIndex(of: "/") else {
        // No parent component (bare filename like "foo.txt") — return the sibling directly
        return sibling
    }
    // Build the parent prefix: everything up to but not including the last "/"
    let parent = String(trimmed[..<slashIndex])
    if parent.isEmpty {
        // Receiver is at root level (e.g. "/foo") — parent is "/"
        return "/" + sibling
    }
    return parent + "/" + sibling
}

@_cdecl("kk_file_resolveSibling_file")
public func kk_file_resolveSibling_file(_ fileRaw: Int, _ relativeRaw: Int) -> Int {
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_resolveSibling_file received invalid File handle")
    }
    guard let relative = runtimeFileBox(from: relativeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_resolveSibling_file received invalid relative File handle")
    }
    let resultPath = fileResolveSiblingPath(base: file.path, sibling: relative.path)
    return registerRuntimeObject(RuntimeFileBox(resultPath))
}

@_cdecl("kk_file_resolveSibling_string")
public func kk_file_resolveSibling_string(_ fileRaw: Int, _ relativeRaw: Int) -> Int {
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_resolveSibling_string received invalid File handle")
    }
    guard let ptr = UnsafeMutableRawPointer(bitPattern: relativeRaw),
          let relativeString = extractString(from: ptr) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_resolveSibling_string received invalid relative string")
    }
    let resultPath = fileResolveSiblingPath(base: file.path, sibling: relativeString)
    return registerRuntimeObject(RuntimeFileBox(resultPath))
}

// MARK: - STDLIB-IO-FN-037: File.startsWith

/// Split a path string into name components, dropping empty separators.
/// Matches the implementation used by `kk_path_startsWith_path` and friends.
private func fileStartsWithPathComponents(_ pathString: String) -> [String] {
    pathString.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
}

/// Returns true if `path` starts with `other` on a component-by-component basis.
/// Both paths must agree on absoluteness (leading "/") and `other` must be a
/// prefix of the receiver's components, mirroring kotlin.io.File.startsWith.
private func fileStartsWithComponents(path: String, other: String) -> Bool {
    let pathParts = fileStartsWithPathComponents(path)
    let otherParts = fileStartsWithPathComponents(other)
    let pathIsAbsolute = path.hasPrefix("/")
    let otherIsAbsolute = other.hasPrefix("/")
    guard pathIsAbsolute == otherIsAbsolute, otherParts.count <= pathParts.count else {
        return false
    }
    for index in 0 ..< otherParts.count where pathParts[index] != otherParts[index] {
        return false
    }
    return true
}

@_cdecl("kk_file_startsWith_file")
public func kk_file_startsWith_file(_ fileRaw: Int, _ otherRaw: Int) -> Int {
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_startsWith_file received invalid File handle")
    }
    guard let other = runtimeFileBox(from: otherRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_startsWith_file received invalid other File handle")
    }
    return kk_box_bool(fileStartsWithComponents(path: file.path, other: other.path) ? 1 : 0)
}

@_cdecl("kk_file_startsWith_string")
public func kk_file_startsWith_string(_ fileRaw: Int, _ otherRaw: Int) -> Int {
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_startsWith_string received invalid File handle")
    }
    guard let ptr = UnsafeMutableRawPointer(bitPattern: otherRaw),
          let otherString = extractString(from: ptr) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_startsWith_string received invalid other string")
    }
    return kk_box_bool(fileStartsWithComponents(path: file.path, other: otherString) ? 1 : 0)
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
@_cdecl("kk_file_copyTo")
public func kk_file_copyTo(
    _ fileRaw: Int,
    _ targetRaw: Int,
    _ overwriteRaw: Int,
    _ bufferSizeRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let source = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_copyTo received invalid source File handle")
    }
    guard let target = runtimeFileBox(from: targetRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_copyTo received invalid target File handle")
    }
    let overwrite = kk_unbox_bool(overwriteRaw) != 0
    let bufferSize = max(1, kk_unbox_int(bufferSizeRaw))

    let fm = FileManager.default
    var sourceIsDir: ObjCBool = false
    guard fm.fileExists(atPath: source.path, isDirectory: &sourceIsDir) else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "NoSuchFileException: \(source.path) (The source file doesn't exist.)"
        )
        return targetRaw
    }

    var targetIsDir: ObjCBool = false
    let targetExists = fm.fileExists(atPath: target.path, isDirectory: &targetIsDir)
    if targetExists {
        if !overwrite {
            outThrown?.pointee = runtimeAllocateThrowable(
                message: "FileAlreadyExistsException: \(target.path) (The destination file already exists.)"
            )
            return targetRaw
        }
        if targetIsDir.boolValue,
           let contents = try? fm.contentsOfDirectory(atPath: target.path),
           !contents.isEmpty {
            outThrown?.pointee = runtimeAllocateThrowable(
                message: "FileAlreadyExistsException: \(target.path) (The destination file already exists.)"
            )
            return targetRaw
        }
        do {
            try fm.removeItem(atPath: target.path)
        } catch {
            outThrown?.pointee = runtimeAllocateThrowable(
                message: "IOException: \(error.localizedDescription)"
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
            outThrown?.pointee = runtimeAllocateThrowable(
                message: "IOException: \(error.localizedDescription)"
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
            outThrown?.pointee = runtimeAllocateThrowable(
                message: "IOException: \(error.localizedDescription)"
            )
        }
        return targetRaw
    }

    do {
        let sourceURL = URL(fileURLWithPath: source.path)
        let readHandle = try FileHandle(forReadingFrom: sourceURL)
        defer { try? readHandle.close() }

        guard fm.createFile(atPath: target.path, contents: nil) else {
            outThrown?.pointee = runtimeAllocateThrowable(
                message: "IOException: Failed to create target file \(target.path)"
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
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "IOException: \(error.localizedDescription)"
        )
    }
    return targetRaw
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
@_cdecl("kk_buffered_reader_iterator")
public func kk_buffered_reader_iterator(_ readerRaw: Int) -> Int {
    guard let reader = runtimeBufferedReaderBox(from: readerRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_buffered_reader_iterator received invalid BufferedReader handle")
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
// `kk_file_useLines`), invokes the supplied lambda once via the collection HOF
// closure ABI, and closes the underlying buffered reader after the block runs —
// mirroring the JVM contract where the reader is closed even when the lambda
// returns or throws.
@_cdecl("kk_buffered_reader_useLines")
public func kk_buffered_reader_useLines(_ readerRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let reader = runtimeBufferedReaderBox(from: readerRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_buffered_reader_useLines received invalid BufferedReader handle")
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
        _ = FileManager.default.createFile(atPath: file.path, contents: Data())
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

@_cdecl("kk_bytearrayinputstream_new")
public func kk_bytearrayinputstream_new(_ bufferRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let bytes = runtimeByteArrayBytes(from: bufferRaw) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IllegalArgumentException: expected ByteArray/List<Int> buffer")
        return 0
    }
    return registerRuntimeObject(RuntimeInputStreamBox(data: Data(bytes)))
}

// STDLIB-IO-FN-020: ByteArray.inputStream() — wraps the entire byte array as a
// ByteArrayInputStream. Mirrors the Kotlin stdlib `public fun ByteArray.inputStream()`.
@_cdecl("kk_bytearray_inputStream")
public func kk_bytearray_inputStream(_ arrayRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let bytes = runtimeByteArrayBytes(from: arrayRaw) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IllegalArgumentException: expected ByteArray handle")
        return 0
    }
    return registerRuntimeObject(RuntimeInputStreamBox(data: Data(bytes)))
}

// STDLIB-IO-FN-021: ByteArray.inputStream(offset: Int, length: Int) — wraps a
// subrange of the byte array as a ByteArrayInputStream. Mirrors the Kotlin stdlib
// `public fun ByteArray.inputStream(offset: Int, length: Int)`.
@_cdecl("kk_bytearray_inputStream_range")
public func kk_bytearray_inputStream_range(
    _ arrayRaw: Int,
    _ offsetRaw: Int,
    _ lengthRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let bytes = runtimeByteArrayBytes(from: arrayRaw) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IllegalArgumentException: expected ByteArray handle")
        return 0
    }
    let offset = offsetRaw
    let length = lengthRaw
    guard offset >= 0, length >= 0, offset + length <= bytes.count else {
        outThrown?.pointee = runtimeAllocateThrowable(
            message: "IndexOutOfBoundsException: offset=\(offset) length=\(length) size=\(bytes.count)"
        )
        return 0
    }
    let slice = Array(bytes[offset ..< offset + length])
    return registerRuntimeObject(RuntimeInputStreamBox(data: Data(slice)))
}

// STDLIB-IO-FN-011: String.byteInputStream() — encodes the receiver as UTF-8 and
// returns a ByteArrayInputStream over the resulting bytes. Default charset overload
// mirrors `String.toByteArray()` semantics for behavioral consistency.
@_cdecl("kk_string_byteInputStream")
public func kk_string_byteInputStream(_ strRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let bytes = source.utf8.map { UInt8($0) }
    return registerRuntimeObject(RuntimeInputStreamBox(data: Data(bytes)))
}

// STDLIB-IO-FN-011: String.byteInputStream(charset: Charset) — charset-aware
// overload. Delegates the encoding step to kk_string_toByteArray_charset so the
// charset table remains a single source of truth.
@_cdecl("kk_string_byteInputStream_charset")
public func kk_string_byteInputStream_charset(_ strRaw: Int, _ charsetTag: Int) -> Int {
    let bytesRaw = kk_string_toByteArray_charset(strRaw, charsetTag)
    guard let bytes = runtimeByteArrayBytes(from: bytesRaw) else {
        // Fall back to UTF-8 if the encoded bytes cannot be retrieved (should not happen)
        let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
        return registerRuntimeObject(RuntimeInputStreamBox(data: Data(source.utf8.map { UInt8($0) })))
    }
    let unsignedBytes = bytes.map { UInt8(truncatingIfNeeded: $0) }
    return registerRuntimeObject(RuntimeInputStreamBox(data: Data(unsignedBytes)))
}

@_cdecl("kk_file_outputStream")
public func kk_file_outputStream(_ fileRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_outputStream received invalid File handle")
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

@_cdecl("kk_input_stream_mark")
public func kk_input_stream_mark(_ streamRaw: Int, _ readLimitRaw: Int) -> Int {
    guard let stream = runtimeInputStreamBox(from: streamRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_input_stream_mark received invalid InputStream handle")
    }
    stream.mark(readLimit: readLimitRaw)
    return 0
}

@_cdecl("kk_input_stream_reset")
public func kk_input_stream_reset(_ streamRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let stream = runtimeInputStreamBox(from: streamRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_input_stream_reset received invalid InputStream handle")
    }
    if !stream.reset() {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: mark/reset not supported")
    }
    return 0
}

@_cdecl("kk_input_stream_mark_supported")
public func kk_input_stream_mark_supported(_ streamRaw: Int) -> Int {
    guard let stream = runtimeInputStreamBox(from: streamRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_input_stream_mark_supported received invalid InputStream handle")
    }
    return kk_box_bool(stream.markSupported() ? 1 : 0)
}

@_cdecl("kk_input_stream_close")
public func kk_input_stream_close(_ streamRaw: Int) -> Int {
    guard let stream = runtimeInputStreamBox(from: streamRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_input_stream_close received invalid InputStream handle")
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
@_cdecl("kk_input_stream_copyTo")
public func kk_input_stream_copyTo(
    _ streamRaw: Int,
    _ outStreamRaw: Int,
    _ bufferSizeRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let inputStream = runtimeInputStreamBox(from: streamRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_input_stream_copyTo received invalid InputStream handle")
    }
    guard let outputStream = runtimeOutputStreamBox(from: outStreamRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_input_stream_copyTo received invalid OutputStream handle")
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
@_cdecl("kk_input_stream_buffered_default")
public func kk_input_stream_buffered_default(_ streamRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard runtimeInputStreamBox(from: streamRaw) != nil else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_input_stream_buffered_default received invalid InputStream handle")
    }
    // The underlying RuntimeInputStreamBox already buffers via Data, so we
    // can hand out the same handle re-typed.  Returning the same raw value
    // keeps reference counting consistent.
    return streamRaw
}

@_cdecl("kk_input_stream_buffered")
public func kk_input_stream_buffered(_ streamRaw: Int, _ bufferSizeRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard runtimeInputStreamBox(from: streamRaw) != nil else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_input_stream_buffered received invalid InputStream handle")
    }
    // Kotlin's reference implementation throws IllegalArgumentException for
    // non-positive buffer sizes (BufferedInputStream's underlying JVM type
    // does the same).  Surface that diagnostic via the standard outThrown
    // channel rather than returning a sentinel.
    if bufferSizeRaw <= 0 {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IllegalArgumentException: Buffer size <= 0")
        return 0
    }
    return streamRaw
}

// MARK: - SequenceInputStream (STDLIB-IO-092)

private func runtimeSequenceInputStreamBox(from raw: Int) -> RuntimeSequenceInputStreamBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeSequenceInputStreamBox.self)
}

@_cdecl("kk_sequence_input_stream_new")
public func kk_sequence_input_stream_new(_ firstRaw: Int, _ secondRaw: Int) -> Int {
    guard let first = runtimeInputStreamBox(from: firstRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_sequence_input_stream_new: invalid first InputStream handle")
    }
    guard let second = runtimeInputStreamBox(from: secondRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_sequence_input_stream_new: invalid second InputStream handle")
    }
    return registerRuntimeObject(RuntimeSequenceInputStreamBox(first: first, second: second))
}

@_cdecl("kk_sequence_input_stream_read")
public func kk_sequence_input_stream_read(_ streamRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let stream = runtimeSequenceInputStreamBox(from: streamRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_sequence_input_stream_read received invalid SequenceInputStream handle")
    }
    return stream.readByte()
}

@_cdecl("kk_sequence_input_stream_available")
public func kk_sequence_input_stream_available(_ streamRaw: Int) -> Int {
    guard let stream = runtimeSequenceInputStreamBox(from: streamRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_sequence_input_stream_available received invalid SequenceInputStream handle")
    }
    return stream.available()
}

@_cdecl("kk_sequence_input_stream_close")
public func kk_sequence_input_stream_close(_ streamRaw: Int) -> Int {
    guard let stream = runtimeSequenceInputStreamBox(from: streamRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_sequence_input_stream_close received invalid SequenceInputStream handle")
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
@_cdecl("kk_output_stream_bufferedWriter")
public func kk_output_stream_bufferedWriter(_ streamRaw: Int, _ charsetRaw: Int) -> Int {
    guard let stream = runtimeOutputStreamBox(from: streamRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_output_stream_bufferedWriter received invalid OutputStream handle")
    }
    let encoding = outputStreamEncoding(for: charsetRaw)
    return registerRuntimeObject(stream.makeBufferedWriter(encoding: encoding))
}

/// Charset-less default overload — `kotlin.io.bufferedWriter()` with no
/// argument should use `Charsets.UTF_8`.  STDLIB-IO-FN-009.
@_cdecl("kk_output_stream_bufferedWriter_default")
public func kk_output_stream_bufferedWriter_default(_ streamRaw: Int) -> Int {
    kk_output_stream_bufferedWriter(streamRaw, 0)
}

// MARK: - STDLIB-IO-090: Files utility (java.nio.file.Files)

private func runtimePathBox(from raw: Int) -> RuntimePathBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimePathBox.self)
}

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

private func runtimeFileIOStringArgument(_ raw: Int, caller: StaticString) -> String {
    if let string = extractString(from: UnsafeMutableRawPointer(bitPattern: raw)) {
        return string
    }
    if let ptr = UnsafePointer<CChar>(bitPattern: raw),
       let string = String(validatingCString: ptr)
    {
        return string
    }
    fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: \(caller) received invalid string handle")
}

/// Files.createFile(path) — creates a new empty file, returns the path.
@_cdecl("kk_files_createFile")
public func kk_files_createFile(_ filesRaw: Int, _ pathRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    _ = filesRaw
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_files_createFile received invalid Path handle")
    }
    if FileManager.default.fileExists(atPath: path.pathString) {
        outThrown?.pointee = runtimeAllocateThrowable(message: "FileAlreadyExistsException: \(path.pathString)")
        return pathRaw
    }
    let created = FileManager.default.createFile(atPath: path.pathString, contents: nil)
    if !created {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: Failed to create file \(path.pathString)")
    }
    return pathRaw
}

/// Files.delete(path) — deletes a file or empty directory.
@_cdecl("kk_files_delete")
public func kk_files_delete(_ filesRaw: Int, _ pathRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    _ = filesRaw
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_files_delete received invalid Path handle")
    }
    guard FileManager.default.fileExists(atPath: path.pathString) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "NoSuchFileException: \(path.pathString)")
        return 0
    }
    do {
        try FileManager.default.removeItem(atPath: path.pathString)
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
    }
    return 0
}

/// Files.copy(source, target) — copies a file, returns the target path.
@_cdecl("kk_files_copy")
public func kk_files_copy(_ filesRaw: Int, _ sourceRaw: Int, _ targetRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    _ = filesRaw
    guard let source = runtimePathBox(from: sourceRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_files_copy received invalid source Path handle")
    }
    guard let target = runtimePathBox(from: targetRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_files_copy received invalid target Path handle")
    }
    do {
        try FileManager.default.copyItem(atPath: source.pathString, toPath: target.pathString)
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
    }
    return targetRaw
}

/// Files.move(source, target) — moves/renames a file, returns the target path.
@_cdecl("kk_files_move")
public func kk_files_move(_ filesRaw: Int, _ sourceRaw: Int, _ targetRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    _ = filesRaw
    guard let source = runtimePathBox(from: sourceRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_files_move received invalid source Path handle")
    }
    guard let target = runtimePathBox(from: targetRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_files_move received invalid target Path handle")
    }
    do {
        try FileManager.default.moveItem(atPath: source.pathString, toPath: target.pathString)
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
    }
    return targetRaw
}

/// Files.createDirectory(path) — creates a single directory, returns the path.
@_cdecl("kk_files_createDirectory")
public func kk_files_createDirectory(_ filesRaw: Int, _ pathRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    _ = filesRaw
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_files_createDirectory received invalid Path handle")
    }
    do {
        _ = try FileManager.default.createDirectory(atPath: path.pathString, withIntermediateDirectories: false)
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
    }
    return pathRaw
}

/// Files.createDirectories(path) — creates directory tree, returns the path.
@_cdecl("kk_files_createDirectories")
public func kk_files_createDirectories(_ filesRaw: Int, _ pathRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    _ = filesRaw
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_files_createDirectories received invalid Path handle")
    }
    do {
        _ = try FileManager.default.createDirectory(atPath: path.pathString, withIntermediateDirectories: true)
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
    }
    return pathRaw
}

/// Files.size(path) — returns file size in bytes.
@_cdecl("kk_files_size")
public func kk_files_size(_ filesRaw: Int, _ pathRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    _ = filesRaw
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_files_size received invalid Path handle")
    }
    do {
        let attrs = try FileManager.default.attributesOfItem(atPath: path.pathString)
        return (attrs[.size] as? Int) ?? 0
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
        return 0
    }
}

/// Files.getLastModifiedTime(path) — returns the modification time as a FileTime.
@_cdecl("kk_files_getLastModifiedTime")
public func kk_files_getLastModifiedTime(_ filesRaw: Int, _ pathRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    _ = filesRaw
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_files_getLastModifiedTime received invalid Path handle")
    }
    do {
        let attrs = try FileManager.default.attributesOfItem(atPath: path.pathString)
        guard let modDate = attrs[.modificationDate] as? Date else {
            return registerRuntimeObject(RuntimeFileTimeBox(milliseconds: 0))
        }
        return registerRuntimeObject(RuntimeFileTimeBox(milliseconds: Int(modDate.timeIntervalSince1970 * 1000)))
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
        return registerRuntimeObject(RuntimeFileTimeBox(milliseconds: 0))
    }
}

/// FileTime.toMillis() — returns the stored epoch millis.
@_cdecl("kk_fileTime_toMillis")
public func kk_fileTime_toMillis(_ fileTimeRaw: Int) -> Int {
    guard let fileTime = runtimeFileTimeBox(from: fileTimeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_fileTime_toMillis received invalid FileTime handle")
    }
    return fileTime.milliseconds
}

/// Files.isRegularFile(path) — returns true if the path is a regular file.
@_cdecl("kk_files_isRegularFile")
public func kk_files_isRegularFile(_ filesRaw: Int, _ pathRaw: Int) -> Int {
    _ = filesRaw
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_files_isRegularFile received invalid Path handle")
    }
    var isDir: ObjCBool = false
    let exists = FileManager.default.fileExists(atPath: path.pathString, isDirectory: &isDir)
    return kk_box_bool(exists && !isDir.boolValue ? 1 : 0)
}

/// Files.isDirectory(path) — returns true if the path is a directory.
@_cdecl("kk_files_isDirectory")
public func kk_files_isDirectory(_ filesRaw: Int, _ pathRaw: Int) -> Int {
    _ = filesRaw
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_files_isDirectory received invalid Path handle")
    }
    var isDir: ObjCBool = false
    let exists = FileManager.default.fileExists(atPath: path.pathString, isDirectory: &isDir)
    return kk_box_bool(exists && isDir.boolValue ? 1 : 0)
}

/// Files.exists(path) — returns true if the path exists.
@_cdecl("kk_files_exists")
public func kk_files_exists(_ filesRaw: Int, _ pathRaw: Int) -> Int {
    _ = filesRaw
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_files_exists received invalid Path handle")
    }
    return kk_box_bool(FileManager.default.fileExists(atPath: path.pathString) ? 1 : 0)
}

/// Files.walk(path) — recursively walks the directory tree, returns List<Path>.
@_cdecl("kk_files_walk")
public func kk_files_walk(_ filesRaw: Int, _ pathRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    _ = filesRaw
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_files_walk received invalid Path handle")
    }
    // Include root as first element, matching Kotlin Files.walk() behaviour
    var paths: [Int] = [registerRuntimeObject(RuntimePathBox(path.pathString))]
    if let enumerator = FileManager.default.enumerator(atPath: path.pathString) {
        while let relativePath = enumerator.nextObject() as? String {
            let fullPath = (path.pathString as NSString).appendingPathComponent(relativePath)
            paths.append(registerRuntimeObject(RuntimePathBox(fullPath)))
        }
    }
    return registerRuntimeObject(RuntimeListBox(elements: paths))
}

/// Files.list(path) — lists direct children of a directory, returns List<Path>.
@_cdecl("kk_files_list")
public func kk_files_list(_ filesRaw: Int, _ pathRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    _ = filesRaw
    guard let path = runtimePathBox(from: pathRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_files_list received invalid Path handle")
    }
    do {
        let entries = try FileManager.default.contentsOfDirectory(atPath: path.pathString)
        let elements = entries.map { entry -> Int in
            let childPath = (path.pathString as NSString).appendingPathComponent(entry)
            return registerRuntimeObject(RuntimePathBox(childPath))
        }
        return registerRuntimeObject(RuntimeListBox(elements: elements))
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
        return registerRuntimeObject(RuntimeListBox(elements: []))
    }
}

/// Files.newDirectoryStream(path) — alias for list(), returns List<Path>.
@_cdecl("kk_files_newDirectoryStream")
public func kk_files_newDirectoryStream(_ filesRaw: Int, _ pathRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    kk_files_list(filesRaw, pathRaw, outThrown)
}

/// Files.createTempFile(prefix, suffix) — creates a temporary file, returns Path.
@_cdecl("kk_files_createTempFile")
public func kk_files_createTempFile(_ filesRaw: Int, _ prefixRaw: Int, _ suffixRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    _ = filesRaw
    let prefix = runtimeFileIOStringArgument(prefixRaw, caller: #function)
    let suffix = runtimeFileIOStringArgument(suffixRaw, caller: #function)
    let tmpDir = NSTemporaryDirectory()
    let fileName = "\(prefix)\(UUID().uuidString)\(suffix)"
    let fullPath = (tmpDir as NSString).appendingPathComponent(fileName)
    let created = FileManager.default.createFile(atPath: fullPath, contents: nil)
    if !created {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: Failed to create temp file \(fullPath)")
        return registerRuntimeObject(RuntimePathBox(fullPath))
    }
    return registerRuntimeObject(RuntimePathBox(fullPath))
}

/// Files.createTempDirectory(prefix) — creates a temporary directory, returns Path.
@_cdecl("kk_files_createTempDirectory")
public func kk_files_createTempDirectory(_ filesRaw: Int, _ prefixRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    _ = filesRaw
    let prefix = runtimeFileIOStringArgument(prefixRaw, caller: #function)
    let tmpDir = NSTemporaryDirectory()
    let dirName = "\(prefix)\(UUID().uuidString)"
    let fullPath = (tmpDir as NSString).appendingPathComponent(dirName)
    do {
        _ = try FileManager.default.createDirectory(atPath: fullPath, withIntermediateDirectories: true)
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
    }
    return registerRuntimeObject(RuntimePathBox(fullPath))
}

@_cdecl("kk_io_createTempDir_default")
public func kk_io_createTempDir_default(_ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeCreateDeprecatedTempDirectory(
        prefixRaw: runtimeNullSentinelInt,
        suffixRaw: runtimeNullSentinelInt,
        directoryRaw: runtimeNullSentinelInt,
        outThrown: outThrown
    )
}

@_cdecl("kk_io_createTempDir_prefix")
public func kk_io_createTempDir_prefix(_ prefixRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeCreateDeprecatedTempDirectory(
        prefixRaw: prefixRaw,
        suffixRaw: runtimeNullSentinelInt,
        directoryRaw: runtimeNullSentinelInt,
        outThrown: outThrown
    )
}

@_cdecl("kk_io_createTempDir_prefix_suffix")
public func kk_io_createTempDir_prefix_suffix(_ prefixRaw: Int, _ suffixRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeCreateDeprecatedTempDirectory(
        prefixRaw: prefixRaw,
        suffixRaw: suffixRaw,
        directoryRaw: runtimeNullSentinelInt,
        outThrown: outThrown
    )
}

@_cdecl("kk_io_createTempDir")
public func kk_io_createTempDir(_ prefixRaw: Int, _ suffixRaw: Int, _ directoryRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeCreateDeprecatedTempDirectory(
        prefixRaw: prefixRaw,
        suffixRaw: suffixRaw,
        directoryRaw: directoryRaw,
        outThrown: outThrown
    )
}

@_cdecl("kk_io_createTempFile_default")
public func kk_io_createTempFile_default(_ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeCreateDeprecatedTempFile(
        prefixRaw: runtimeNullSentinelInt,
        suffixRaw: runtimeNullSentinelInt,
        directoryRaw: runtimeNullSentinelInt,
        outThrown: outThrown
    )
}

@_cdecl("kk_io_createTempFile_prefix")
public func kk_io_createTempFile_prefix(_ prefixRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeCreateDeprecatedTempFile(
        prefixRaw: prefixRaw,
        suffixRaw: runtimeNullSentinelInt,
        directoryRaw: runtimeNullSentinelInt,
        outThrown: outThrown
    )
}

@_cdecl("kk_io_createTempFile_prefix_suffix")
public func kk_io_createTempFile_prefix_suffix(_ prefixRaw: Int, _ suffixRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeCreateDeprecatedTempFile(
        prefixRaw: prefixRaw,
        suffixRaw: suffixRaw,
        directoryRaw: runtimeNullSentinelInt,
        outThrown: outThrown
    )
}

@_cdecl("kk_io_createTempFile")
public func kk_io_createTempFile(_ prefixRaw: Int, _ suffixRaw: Int, _ directoryRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    runtimeCreateDeprecatedTempFile(
        prefixRaw: prefixRaw,
        suffixRaw: suffixRaw,
        directoryRaw: directoryRaw,
        outThrown: outThrown
    )
}
