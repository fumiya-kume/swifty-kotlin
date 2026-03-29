import Foundation

final class RuntimeURIBox {
    let components: URLComponents

    init(components: URLComponents) {
        self.components = components
    }
}

private func runtimeURIBox(from raw: Int) -> RuntimeURIBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeURIBox.self)
}

private func uriMakeStringRaw(_ value: String) -> Int {
    Int(bitPattern: value.withCString { cstr in
        cstr.withMemoryRebound(to: UInt8.self, capacity: value.utf8.count) { pointer in
            kk_string_from_utf8(pointer, Int32(value.utf8.count))
        }
    })
}

private func uriString(from raw: Int, caller: StaticString) -> String {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw),
          let str = extractString(from: ptr)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: \(caller) received invalid string handle")
    }
    return str
}

private func boxURI(_ components: URLComponents) -> Int {
    registerRuntimeObject(RuntimeURIBox(components: components))
}

@_cdecl("kk_uri_new")
public func kk_uri_new(_ specRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let spec = uriString(from: specRaw, caller: #function)
    guard let components = URLComponents(string: spec) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "URISyntaxException: \(spec)")
        return 0
    }
    return boxURI(components)
}

@_cdecl("kk_uri_toString")
public func kk_uri_toString(_ uriRaw: Int) -> Int {
    guard let box = runtimeURIBox(from: uriRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_uri_toString received invalid URI handle")
    }
    return uriMakeStringRaw(box.components.string ?? "")
}

@_cdecl("kk_uri_scheme")
public func kk_uri_scheme(_ uriRaw: Int) -> Int {
    guard let box = runtimeURIBox(from: uriRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_uri_scheme received invalid URI handle")
    }
    guard let scheme = box.components.scheme else { return runtimeNullSentinelInt }
    return uriMakeStringRaw(scheme)
}

@_cdecl("kk_uri_authority")
public func kk_uri_authority(_ uriRaw: Int) -> Int {
    guard let box = runtimeURIBox(from: uriRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_uri_authority received invalid URI handle")
    }
    guard let host = box.components.host else { return runtimeNullSentinelInt }
    if let port = box.components.port {
        return uriMakeStringRaw("\(host):\(port)")
    }
    return uriMakeStringRaw(host)
}

@_cdecl("kk_uri_path")
public func kk_uri_path(_ uriRaw: Int) -> Int {
    guard let box = runtimeURIBox(from: uriRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_uri_path received invalid URI handle")
    }
    return uriMakeStringRaw(box.components.path)
}

@_cdecl("kk_uri_query")
public func kk_uri_query(_ uriRaw: Int) -> Int {
    guard let box = runtimeURIBox(from: uriRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_uri_query received invalid URI handle")
    }
    guard let query = box.components.query else { return runtimeNullSentinelInt }
    return uriMakeStringRaw(query)
}

@_cdecl("kk_uri_fragment")
public func kk_uri_fragment(_ uriRaw: Int) -> Int {
    guard let box = runtimeURIBox(from: uriRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_uri_fragment received invalid URI handle")
    }
    guard let fragment = box.components.fragment else { return runtimeNullSentinelInt }
    return uriMakeStringRaw(fragment)
}

@_cdecl("kk_uri_normalize")
public func kk_uri_normalize(_ uriRaw: Int) -> Int {
    guard let box = runtimeURIBox(from: uriRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_uri_normalize received invalid URI handle")
    }
    var copy = box.components
    let normalizedPath = NSString(string: copy.path).standardizingPath
    copy.path = normalizedPath == "." ? "" : normalizedPath
    return boxURI(copy)
}

@_cdecl("kk_uri_resolve")
public func kk_uri_resolve(_ baseRaw: Int, _ otherRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let base = runtimeURIBox(from: baseRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_uri_resolve received invalid base URI handle")
    }
    let other = uriString(from: otherRaw, caller: #function)
    guard let baseURL = base.components.url,
          let resolved = URL(string: other, relativeTo: baseURL)?.absoluteURL,
          let components = URLComponents(url: resolved, resolvingAgainstBaseURL: true)
    else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "URISyntaxException: \(other)")
        return 0
    }
    return boxURI(components)
}

@_cdecl("kk_uri_relativize")
public func kk_uri_relativize(_ baseRaw: Int, _ otherRaw: Int) -> Int {
    guard let base = runtimeURIBox(from: baseRaw),
          let other = runtimeURIBox(from: otherRaw)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_uri_relativize received invalid URI handle")
    }
    let basePath = base.components.path
    let otherPath = other.components.path
    if otherPath.hasPrefix(basePath) {
        let suffix = String(otherPath.dropFirst(basePath.count)).trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        var copy = other.components
        copy.scheme = nil
        copy.host = nil
        copy.port = nil
        copy.path = suffix
        return boxURI(copy)
    }
    return boxURI(other.components)
}
