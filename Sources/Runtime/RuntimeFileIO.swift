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

private func runtimeFileRootLength(_ path: String) -> Int {
    let normalized = path.replacingOccurrences(of: "\\", with: "/")
    guard !normalized.isEmpty else { return 0 }

    if normalized.hasPrefix("//") {
        let hostStart = normalized.index(normalized.startIndex, offsetBy: 2)
        guard let hostEnd = normalized[hostStart...].firstIndex(of: "/") else {
            return normalized.count
        }
        let shareStart = normalized.index(after: hostEnd)
        guard shareStart < normalized.endIndex else {
            return normalized.count
        }
        guard let shareEnd = normalized[shareStart...].firstIndex(of: "/") else {
            return normalized.count
        }
        return normalized.distance(from: normalized.startIndex, to: normalized.index(after: shareEnd))
    }

    if normalized.hasPrefix("/") {
        return 1
    }

    guard normalized.count >= 2 else { return 0 }
    let driveEnd = normalized.index(after: normalized.startIndex)
    guard normalized[driveEnd] == ":" else { return 0 }
    let afterDrive = normalized.index(after: driveEnd)
    if afterDrive == normalized.endIndex {
        return normalized.count
    }
    return normalized[afterDrive] == "/" ? 3 : 0
}

private func runtimeNormalizeFilePath(_ path: String) -> String {
    let normalizedSeparators = path.replacingOccurrences(of: "\\", with: "/")
    let rootLength = runtimeFileRootLength(normalizedSeparators)
    let rootEnd = normalizedSeparators.index(normalizedSeparators.startIndex, offsetBy: rootLength)
    let root = String(normalizedSeparators[..<rootEnd])
    let rest = String(normalizedSeparators[rootEnd...])

    var components: [String] = []
    for part in rest.split(separator: "/", omittingEmptySubsequences: true) {
        let component = String(part)
        if component == "." {
            continue
        }
        if component == ".." {
            if !components.isEmpty && components.last != ".." {
                components.removeLast()
            } else if rootLength == 0 {
                components.append(component)
            }
            continue
        }
        components.append(component)
    }

    let joined = components.joined(separator: "/")
    if root.isEmpty {
        return joined.isEmpty ? "." : joined
    }
    if joined.isEmpty {
        return root
    }
    return root.hasSuffix("/") ? "\(root)\(joined)" : "\(root)/\(joined)"
}

private func runtimeResolveSiblingPath(basePath: String, relativePath: String) -> String {
    if runtimeFileRootLength(relativePath) > 0 {
        return relativePath
    }
    let parent = (basePath as NSString).deletingLastPathComponent
    if parent.isEmpty || parent == basePath {
        return relativePath
    }
    return (parent as NSString).appendingPathComponent(relativePath)
}

private func runtimeFilePathRootAndComponents(_ path: String) -> (root: String, components: [String]) {
    let normalized = runtimeNormalizeFilePath(path)
    let rootLength = runtimeFileRootLength(normalized)
    let rootEnd = normalized.index(normalized.startIndex, offsetBy: rootLength)
    let root = String(normalized[..<rootEnd])
    let rest = String(normalized[rootEnd...])
    let components = rest.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
    return (root, components)
}

private func runtimeFileStartsWith(basePath: String, otherPath: String) -> Bool {
    let base = runtimeFilePathRootAndComponents(basePath)
    let other = runtimeFilePathRootAndComponents(otherPath)
    guard base.root == other.root,
          base.components.count >= other.components.count
    else {
        return false
    }
    return zip(base.components, other.components).allSatisfy { $0 == $1 }
}

private func runtimeFileRelativeString(path: String, basePath: String) -> String {
    let target = runtimeFilePathRootAndComponents(path)
    let base = runtimeFilePathRootAndComponents(basePath)
    guard target.root == base.root else {
        return runtimeNormalizeFilePath(path)
    }

    var commonLength = 0
    while commonLength < target.components.count && commonLength < base.components.count
        && target.components[commonLength] == base.components[commonLength] {
        commonLength += 1
    }

    let ups = Array(repeating: "..", count: base.components.count - commonLength)
    let remainder = Array(target.components[commonLength...])
    let relative = (ups + remainder).joined(separator: "/")
    return relative.isEmpty ? "." : relative
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

@_cdecl("kk_file_appendBytes")
public func kk_file_appendBytes(_ fileRaw: Int, _ arrayRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_appendBytes received invalid File handle")
    }
    guard let bytes = runtimeByteArrayBytes(from: arrayRaw) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IllegalArgumentException: expected ByteArray/List<Int> buffer")
        return 0
    }
    do {
        let data = Data(bytes)
        let url = URL(fileURLWithPath: file.path)
        if FileManager.default.fileExists(atPath: file.path) {
            let handle = try FileHandle(forWritingTo: url)
            defer { try? handle.close() }
            try handle.seekToEnd()
            try handle.write(contentsOf: data)
        } else {
            try data.write(to: url)
        }
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
    }
    return 0
}

@_cdecl("kk_file_forEachBlock_default")
public func kk_file_forEachBlock_default(
    _ fileRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    kk_file_forEachBlock(fileRaw, 4096, fnPtr, closureRaw, outThrown)
}

@_cdecl("kk_file_forEachBlock")
public func kk_file_forEachBlock(
    _ fileRaw: Int,
    _ blockSizeRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard blockSizeRaw > 0 else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IllegalArgumentException: blockSize must be positive")
        return 0
    }
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_forEachBlock received invalid File handle")
    }
    do {
        let data = try Data(contentsOf: URL(fileURLWithPath: file.path))
        var offset = 0
        while offset < data.count {
            let end = min(offset + blockSizeRaw, data.count)
            let chunk = data[offset ..< end].map { Int(Int8(bitPattern: $0)) }
            let chunkRaw = registerRuntimeObject(RuntimeListBox(elements: chunk))
            var thrown = 0
            _ = runtimeInvokeCollectionLambda2(
                fnPtr: fnPtr,
                closureRaw: closureRaw,
                lhs: chunkRaw,
                rhs: end - offset,
                outThrown: &thrown
            )
            if thrown != 0 {
                outThrown?.pointee = thrown
                return 0
            }
            offset = end
        }
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
    }
    return 0
}

@_cdecl("kk_file_copyTo_default")
public func kk_file_copyTo_default(_ sourceRaw: Int, _ targetRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    kk_file_copyTo(sourceRaw, targetRaw, kk_box_bool(0), 8192, outThrown)
}

@_cdecl("kk_file_copyTo_overwrite")
public func kk_file_copyTo_overwrite(
    _ sourceRaw: Int,
    _ targetRaw: Int,
    _ overwriteRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    kk_file_copyTo(sourceRaw, targetRaw, overwriteRaw, 8192, outThrown)
}

@_cdecl("kk_file_copyTo")
public func kk_file_copyTo(
    _ sourceRaw: Int,
    _ targetRaw: Int,
    _ overwriteRaw: Int,
    _ bufferSizeRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard bufferSizeRaw > 0 else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IllegalArgumentException: bufferSize must be positive")
        return targetRaw
    }
    guard let source = runtimeFileBox(from: sourceRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_copyTo received invalid source File handle")
    }
    guard let target = runtimeFileBox(from: targetRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_copyTo received invalid target File handle")
    }
    do {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: target.path) {
            guard kk_unbox_bool(overwriteRaw) != 0 else {
                outThrown?.pointee = runtimeAllocateThrowable(message: "FileAlreadyExistsException: \(target.path)")
                return targetRaw
            }
            try fileManager.removeItem(atPath: target.path)
        }
        try fileManager.copyItem(atPath: source.path, toPath: target.path)
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
    }
    return targetRaw
}

@_cdecl("kk_file_copyRecursively_default")
public func kk_file_copyRecursively_default(_ sourceRaw: Int, _ targetRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    kk_file_copyRecursively_overwrite(sourceRaw, targetRaw, kk_box_bool(0), outThrown)
}

@_cdecl("kk_file_copyRecursively_overwrite")
public func kk_file_copyRecursively_overwrite(
    _ sourceRaw: Int,
    _ targetRaw: Int,
    _ overwriteRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let source = runtimeFileBox(from: sourceRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_copyRecursively_overwrite received invalid source File handle")
    }
    guard let target = runtimeFileBox(from: targetRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_copyRecursively_overwrite received invalid target File handle")
    }
    do {
        let fileManager = FileManager.default
        if fileManager.fileExists(atPath: target.path) {
            guard kk_unbox_bool(overwriteRaw) != 0 else {
                outThrown?.pointee = runtimeAllocateThrowable(message: "FileAlreadyExistsException: \(target.path)")
                return kk_box_bool(0)
            }
            try fileManager.removeItem(atPath: target.path)
        }
        try fileManager.copyItem(atPath: source.path, toPath: target.path)
        return kk_box_bool(1)
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
        return kk_box_bool(0)
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

@_cdecl("kk_file_extension")
public func kk_file_extension(_ fileRaw: Int) -> Int {
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_extension received invalid File handle")
    }
    let name = (file.path as NSString).lastPathComponent
    guard let dotIndex = name.lastIndex(of: ".") else {
        return fileMakeStringRaw("")
    }
    return fileMakeStringRaw(String(name[name.index(after: dotIndex)...]))
}

@_cdecl("kk_file_invariantSeparatorsPath")
public func kk_file_invariantSeparatorsPath(_ fileRaw: Int) -> Int {
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_invariantSeparatorsPath received invalid File handle")
    }
    return fileMakeStringRaw(file.path.replacingOccurrences(of: "\\", with: "/"))
}

@_cdecl("kk_file_isRooted")
public func kk_file_isRooted(_ fileRaw: Int) -> Int {
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_isRooted received invalid File handle")
    }
    return kk_box_bool(runtimeFileRootLength(file.path) > 0 ? 1 : 0)
}

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

@_cdecl("kk_file_normalize")
public func kk_file_normalize(_ fileRaw: Int) -> Int {
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_normalize received invalid File handle")
    }
    return registerRuntimeObject(RuntimeFileBox(runtimeNormalizeFilePath(file.path)))
}

@_cdecl("kk_file_resolveSibling_file")
public func kk_file_resolveSibling_file(_ fileRaw: Int, _ relativeRaw: Int) -> Int {
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_resolveSibling_file received invalid File handle")
    }
    guard let relative = runtimeFileBox(from: relativeRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_resolveSibling_file received invalid relative File handle")
    }
    return registerRuntimeObject(RuntimeFileBox(
        runtimeResolveSiblingPath(basePath: file.path, relativePath: relative.path)
    ))
}

@_cdecl("kk_file_resolveSibling_string")
public func kk_file_resolveSibling_string(_ fileRaw: Int, _ relativeRaw: Int) -> Int {
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_resolveSibling_string received invalid File handle")
    }
    guard let ptr = UnsafeMutableRawPointer(bitPattern: relativeRaw),
          let relative = extractString(from: ptr)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_resolveSibling_string received invalid relative path")
    }
    return registerRuntimeObject(RuntimeFileBox(
        runtimeResolveSiblingPath(basePath: file.path, relativePath: relative)
    ))
}

@_cdecl("kk_file_startsWith_file")
public func kk_file_startsWith_file(_ fileRaw: Int, _ otherRaw: Int) -> Int {
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_startsWith_file received invalid File handle")
    }
    guard let other = runtimeFileBox(from: otherRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_startsWith_file received invalid other File handle")
    }
    return kk_box_bool(runtimeFileStartsWith(basePath: file.path, otherPath: other.path) ? 1 : 0)
}

@_cdecl("kk_file_startsWith_string")
public func kk_file_startsWith_string(_ fileRaw: Int, _ otherRaw: Int) -> Int {
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_startsWith_string received invalid File handle")
    }
    guard let ptr = UnsafeMutableRawPointer(bitPattern: otherRaw),
          let other = extractString(from: ptr)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_startsWith_string received invalid other path")
    }
    return kk_box_bool(runtimeFileStartsWith(basePath: file.path, otherPath: other) ? 1 : 0)
}

@_cdecl("kk_file_toRelativeString")
public func kk_file_toRelativeString(_ fileRaw: Int, _ baseRaw: Int) -> Int {
    guard let file = runtimeFileBox(from: fileRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_toRelativeString received invalid File handle")
    }
    guard let base = runtimeFileBox(from: baseRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_file_toRelativeString received invalid base File handle")
    }
    return fileMakeStringRaw(runtimeFileRelativeString(path: file.path, basePath: base.path))
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

private func runtimeByteArrayBytes(from raw: Int) -> [UInt8]? {
    if let array = runtimeArrayBox(from: raw) {
        return array.elements.map { UInt8(truncatingIfNeeded: $0) }
    }
    if let list = runtimeListBox(from: raw) {
        return list.elements.map { UInt8(truncatingIfNeeded: $0) }
    }
    return nil
}

private func runtimeByteArraySliceBytes(from raw: Int, offset: Int, length: Int) -> [UInt8]? {
    guard let bytes = runtimeByteArrayBytes(from: raw),
          offset >= 0,
          length >= 0,
          offset <= bytes.count,
          length <= bytes.count - offset
    else {
        return nil
    }
    return Array(bytes[offset ..< offset + length])
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

@_cdecl("kk_reader_buffered_default")
public func kk_reader_buffered_default(_ readerRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    kk_reader_buffered(readerRaw, 8192, outThrown)
}

@_cdecl("kk_reader_buffered")
public func kk_reader_buffered(_ readerRaw: Int, _ bufferSizeRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard bufferSizeRaw > 0 else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IllegalArgumentException: bufferSize must be positive")
        return 0
    }
    guard runtimeBufferedReaderBox(from: readerRaw) != nil else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_reader_buffered received invalid Reader handle")
    }
    return readerRaw
}

@_cdecl("kk_reader_readText")
public func kk_reader_readText(_ readerRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let reader = runtimeBufferedReaderBox(from: readerRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_reader_readText received invalid Reader handle")
    }
    return fileMakeStringRaw(reader.readText())
}

@_cdecl("kk_reader_forEachLine")
public func kk_reader_forEachLine(
    _ readerRaw: Int,
    _ fnPtr: Int,
    _ closureRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let reader = runtimeBufferedReaderBox(from: readerRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_reader_forEachLine received invalid Reader handle")
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

@_cdecl("kk_reader_useLines")
public func kk_reader_useLines(_ readerRaw: Int, _ fnPtr: Int, _ closureRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let reader = runtimeBufferedReaderBox(from: readerRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_reader_useLines received invalid Reader handle")
    }
    defer { reader.close() }
    let lines = reader.readLines()
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

// MARK: - STDLIB-IO-091: BufferedWriter

private func runtimeBufferedWriterBox(from raw: Int) -> RuntimeBufferedWriterBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeBufferedWriterBox.self)
}

@_cdecl("kk_reader_copyTo_default")
public func kk_reader_copyTo_default(
    _ readerRaw: Int,
    _ writerRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    kk_reader_copyTo(readerRaw, writerRaw, 8192, outThrown)
}

@_cdecl("kk_reader_copyTo")
public func kk_reader_copyTo(
    _ readerRaw: Int,
    _ writerRaw: Int,
    _ bufferSizeRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard bufferSizeRaw > 0 else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IllegalArgumentException: bufferSize must be positive")
        return 0
    }
    guard let reader = runtimeBufferedReaderBox(from: readerRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_reader_copyTo received invalid Reader handle")
    }
    guard let writer = runtimeBufferedWriterBox(from: writerRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_reader_copyTo received invalid Writer handle")
    }
    let text = reader.readText()
    do {
        try writer.write(text)
        return text.utf8.count
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
        return 0
    }
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

@_cdecl("kk_writer_buffered_default")
public func kk_writer_buffered_default(_ writerRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    kk_writer_buffered(writerRaw, 8192, outThrown)
}

@_cdecl("kk_writer_buffered")
public func kk_writer_buffered(_ writerRaw: Int, _ bufferSizeRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard bufferSizeRaw > 0 else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IllegalArgumentException: bufferSize must be positive")
        return 0
    }
    guard runtimeBufferedWriterBox(from: writerRaw) != nil else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_writer_buffered received invalid Writer handle")
    }
    return writerRaw
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

@_cdecl("kk_bytearray_inputStream")
public func kk_bytearray_inputStream(_ arrayRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    kk_bytearrayinputstream_new(arrayRaw, outThrown)
}

@_cdecl("kk_bytearray_inputStream_range")
public func kk_bytearray_inputStream_range(
    _ arrayRaw: Int,
    _ offsetRaw: Int,
    _ lengthRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let bytes = runtimeByteArraySliceBytes(from: arrayRaw, offset: offsetRaw, length: lengthRaw) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IllegalArgumentException: invalid ByteArray inputStream range")
        return 0
    }
    return registerRuntimeObject(RuntimeInputStreamBox(data: Data(bytes)))
}

@_cdecl("kk_string_byteInputStream_default")
public func kk_string_byteInputStream_default(_ stringRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    kk_string_byteInputStream(stringRaw, kk_charset_utf_8(), outThrown)
}

@_cdecl("kk_string_byteInputStream")
public func kk_string_byteInputStream(_ stringRaw: Int, _ charsetRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    let bytesRaw = kk_string_toByteArray_charset(stringRaw, charsetRaw)
    return kk_bytearrayinputstream_new(bytesRaw, outThrown)
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

@_cdecl("kk_input_stream_readBytes")
public func kk_input_stream_readBytes(_ streamRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let stream = runtimeInputStreamBox(from: streamRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_input_stream_readBytes received invalid InputStream handle")
    }
    return registerRuntimeObject(RuntimeListBox(elements: stream.readRemainingBytes()))
}

@_cdecl("kk_input_stream_copyTo_default")
public func kk_input_stream_copyTo_default(
    _ inputRaw: Int,
    _ outputRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    kk_input_stream_copyTo(inputRaw, outputRaw, 8192, outThrown)
}

@_cdecl("kk_input_stream_copyTo")
public func kk_input_stream_copyTo(
    _ inputRaw: Int,
    _ outputRaw: Int,
    _ bufferSizeRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard bufferSizeRaw > 0 else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IllegalArgumentException: bufferSize must be positive")
        return 0
    }
    guard let input = runtimeInputStreamBox(from: inputRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_input_stream_copyTo received invalid InputStream handle")
    }
    guard let output = runtimeOutputStreamBox(from: outputRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_input_stream_copyTo received invalid OutputStream handle")
    }
    let bytes = input.readRemainingBytes()
    do {
        try output.writeBytes(bytes)
        return bytes.count
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(error.localizedDescription)")
        return 0
    }
}

@_cdecl("kk_input_stream_buffered_default")
public func kk_input_stream_buffered_default(_ streamRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    kk_input_stream_buffered(streamRaw, 8192, outThrown)
}

@_cdecl("kk_input_stream_buffered")
public func kk_input_stream_buffered(
    _ streamRaw: Int,
    _ bufferSizeRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard bufferSizeRaw > 0 else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IllegalArgumentException: bufferSize must be positive")
        return 0
    }
    guard runtimeInputStreamBox(from: streamRaw) != nil else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_input_stream_buffered received invalid InputStream handle")
    }
    return streamRaw
}

@_cdecl("kk_input_stream_bufferedReader_default")
public func kk_input_stream_bufferedReader_default(_ streamRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    kk_input_stream_bufferedReader(streamRaw, kk_charset_utf_8(), outThrown)
}

@_cdecl("kk_input_stream_bufferedReader")
public func kk_input_stream_bufferedReader(
    _ streamRaw: Int,
    _ charsetRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let stream = runtimeInputStreamBox(from: streamRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_input_stream_bufferedReader received invalid InputStream handle")
    }
    _ = charsetRaw
    let bytes = stream.readRemainingBytes().map { UInt8(truncatingIfNeeded: $0) }
    return registerRuntimeObject(RuntimeBufferedReaderBox(data: Data(bytes)))
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

@_cdecl("kk_output_stream_bufferedWriter_default")
public func kk_output_stream_bufferedWriter_default(_ streamRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    kk_output_stream_bufferedWriter(streamRaw, kk_charset_utf_8(), outThrown)
}

@_cdecl("kk_output_stream_bufferedWriter")
public func kk_output_stream_bufferedWriter(
    _ streamRaw: Int,
    _ charsetRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard let stream = runtimeOutputStreamBox(from: streamRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_output_stream_bufferedWriter received invalid OutputStream handle")
    }
    _ = charsetRaw
    guard let writer = stream.makeBufferedWriter(bufferSize: 8192) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: OutputStream is closed")
        return 0
    }
    return registerRuntimeObject(writer)
}

@_cdecl("kk_output_stream_buffered_default")
public func kk_output_stream_buffered_default(_ streamRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    kk_output_stream_buffered(streamRaw, 8192, outThrown)
}

@_cdecl("kk_output_stream_buffered")
public func kk_output_stream_buffered(
    _ streamRaw: Int,
    _ bufferSizeRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    guard bufferSizeRaw > 0 else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IllegalArgumentException: bufferSize must be positive")
        return 0
    }
    guard runtimeOutputStreamBox(from: streamRaw) != nil else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_output_stream_buffered received invalid OutputStream handle")
    }
    return streamRaw
}

@_cdecl("kk_output_stream_close")
public func kk_output_stream_close(_ streamRaw: Int) -> Int {
    guard let stream = runtimeOutputStreamBox(from: streamRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_output_stream_close received invalid OutputStream handle")
    }
    stream.close()
    return 0
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
