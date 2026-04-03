import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

final class RuntimeHttpClientBox {}

private final class RuntimeHTTPClientBox {
    private let lock = NSLock()
    private var connectTimeoutMillis: Int = 30_000
    private var readTimeoutMillis: Int = 30_000
    private var followRedirects = true
    private var defaultHeaders: [String: String] = [:]
    private var authHeader: String?

    struct Snapshot {
        let connectTimeoutMillis: Int
        let readTimeoutMillis: Int
        let followRedirects: Bool
        let defaultHeaders: [String: String]
        let authHeader: String?
    }

    func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return Snapshot(
            connectTimeoutMillis: connectTimeoutMillis,
            readTimeoutMillis: readTimeoutMillis,
            followRedirects: followRedirects,
            defaultHeaders: defaultHeaders,
            authHeader: authHeader
        )
    }

    func setConnectTimeoutMillis(_ value: Int) {
        lock.lock()
        connectTimeoutMillis = max(0, value)
        lock.unlock()
    }

    func setReadTimeoutMillis(_ value: Int) {
        lock.lock()
        readTimeoutMillis = max(0, value)
        lock.unlock()
    }

    func setFollowRedirects(_ value: Bool) {
        lock.lock()
        followRedirects = value
        lock.unlock()
    }

    func setDefaultHeader(name: String, value: String) {
        lock.lock()
        defaultHeaders[name] = value
        lock.unlock()
    }

    func setBasicAuth(username: String, password: String) {
        let token = Data("\(username):\(password)".utf8).base64EncodedString()
        lock.lock()
        authHeader = "Basic \(token)"
        lock.unlock()
    }

    func setBearerToken(_ token: String) {
        lock.lock()
        authHeader = "Bearer \(token)"
        lock.unlock()
    }

    func clearAuthentication() {
        lock.lock()
        authHeader = nil
        lock.unlock()
    }
}

final class RuntimeHttpRequestBuilderBox {
    var url: URL?
    var method: String
    var headers: [(String, String)]
    var body: Data?

    init(url: URL? = nil, method: String = "GET", headers: [(String, String)] = [], body: Data? = nil) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
    }
}

final class RuntimeHttpRequestBox {
    let url: URL
    let method: String
    let headers: [(String, String)]
    let body: Data?

    init(url: URL, method: String, headers: [(String, String)], body: Data?) {
        self.url = url
        self.method = method
        self.headers = headers
        self.body = body
    }
}

final class RuntimeHttpBodyPublisherBox {
    let data: Data?

    init(data: Data?) {
        self.data = data
    }
}

final class RuntimeHttpBodyHandlerBox {
    let kind: String

    init(kind: String) {
        self.kind = kind
    }
}

final class RuntimeHttpResponseBox {
    let statusCode: Int
    let headers: [(String, [String])]
    let body: String
    let url: String
    let contentType: String?
    let errorMessage: String?
    let timedOut: Bool

    init(
        statusCode: Int,
        headers: [(String, [String])],
        body: String,
        url: String = "",
        contentType: String? = nil,
        errorMessage: String? = nil,
        timedOut: Bool = false
    ) {
        self.statusCode = statusCode
        self.headers = headers
        self.body = body
        self.url = url
        self.contentType = contentType
        self.errorMessage = errorMessage
        self.timedOut = timedOut
    }

    var isSuccessful: Bool {
        errorMessage == nil && (200 ... 299).contains(statusCode)
    }
}

final class RuntimeHttpHeadersBox {
    let headers: [(String, [String])]

    init(headers: [(String, [String])]) {
        self.headers = headers
    }
}

private final class RuntimeHTTPTaskResultBox: @unchecked Sendable {
    var data = Data()
    var response: URLResponse?
    var error: Error?
}

private func runtimeHttpClientBox(from raw: Int) -> RuntimeHttpClientBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeHttpClientBox.self)
}

private func runtimeHttpRequestBuilderBox(from raw: Int) -> RuntimeHttpRequestBuilderBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeHttpRequestBuilderBox.self)
}

private func runtimeHttpRequestBox(from raw: Int) -> RuntimeHttpRequestBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeHttpRequestBox.self)
}

private func runtimeHttpBodyPublisherBox(from raw: Int) -> RuntimeHttpBodyPublisherBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeHttpBodyPublisherBox.self)
}

private func runtimeHttpBodyHandlerBox(from raw: Int) -> RuntimeHttpBodyHandlerBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeHttpBodyHandlerBox.self)
}

private func runtimeHttpResponseBox(from raw: Int) -> RuntimeHttpResponseBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeHttpResponseBox.self)
}

private func runtimeHttpHeadersBox(from raw: Int) -> RuntimeHttpHeadersBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeHttpHeadersBox.self)
}

private func networkString(from raw: Int, caller: StaticString) -> String {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw),
          let str = extractString(from: ptr)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: \(caller) received invalid string handle")
    }
    return str
}

private func networkStringRaw(_ value: String) -> Int {
    Int(bitPattern: value.withCString { cstr in
        cstr.withMemoryRebound(to: UInt8.self, capacity: value.utf8.count) { pointer in
            kk_string_from_utf8(pointer, Int32(value.utf8.count))
        }
    })
}

private func runtimeHTTPClientBox(from raw: Int) -> RuntimeHTTPClientBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeHTTPClientBox.self)
}

private final class RuntimeHTTPRedirectDelegate: NSObject, URLSessionTaskDelegate {
    private let followRedirects: Bool

    init(followRedirects: Bool) {
        self.followRedirects = followRedirects
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(followRedirects ? request : nil)
    }
}

private func runtimeHTTPNormalizedHeaders(_ rawHeaders: [AnyHashable: Any]?) -> [String: String] {
    guard let rawHeaders else { return [:] }
    var normalized: [String: String] = [:]
    for (key, value) in rawHeaders {
        let headerName = String(describing: key).lowercased()
        if let values = value as? [String] {
            normalized[headerName] = values.joined(separator: ", ")
        } else {
            normalized[headerName] = String(describing: value)
        }
    }
    return normalized
}

private func runtimeHTTPResponseHandle(
    statusCode: Int,
    body: String,
    url: String,
    headers: [String: String],
    contentType: String?,
    errorMessage: String?,
    timedOut: Bool
) -> Int {
    let headerPairs = headers.sorted { $0.key.localizedCaseInsensitiveCompare($1.key) == .orderedAscending }.map { ($0.key, [$0.value]) }
    return registerRuntimeObject(RuntimeHttpResponseBox(
        statusCode: statusCode,
        headers: headerPairs,
        body: body,
        url: url,
        contentType: contentType,
        errorMessage: errorMessage,
        timedOut: timedOut
    ))
}

private func runtimeHTTPErrorResponse(message: String, url: String = "", timedOut: Bool = false) -> Int {
    runtimeHTTPResponseHandle(
        statusCode: 0,
        body: "",
        url: url,
        headers: [:],
        contentType: nil,
        errorMessage: message,
        timedOut: timedOut
    )
}

private func runtimeHTTPPrepareRequest(
    client: RuntimeHTTPClientBox,
    method: String,
    urlString: String,
    body: String?
) -> (URLRequest, RuntimeHTTPClientBox.Snapshot)? {
    guard let url = URL(string: urlString) else { return nil }
    let snapshot = client.snapshot()
    var request = URLRequest(url: url)
    request.httpMethod = method
    if let body {
        request.httpBody = Data(body.utf8)
    }
    if snapshot.connectTimeoutMillis > 0 {
        request.timeoutInterval = TimeInterval(snapshot.connectTimeoutMillis) / 1000.0
    }
    for (name, value) in snapshot.defaultHeaders {
        request.setValue(value, forHTTPHeaderField: name)
    }
    if let authHeader = snapshot.authHeader {
        request.setValue(authHeader, forHTTPHeaderField: "Authorization")
    }
    if body != nil, request.value(forHTTPHeaderField: "Content-Type") == nil {
        request.setValue("text/plain; charset=utf-8", forHTTPHeaderField: "Content-Type")
    }
    return (request, snapshot)
}

private func runtimeHTTPMakeSession(
    snapshot: RuntimeHTTPClientBox.Snapshot
) -> (URLSession, RuntimeHTTPRedirectDelegate) {
    let configuration = URLSessionConfiguration.ephemeral
    if snapshot.connectTimeoutMillis > 0 {
        configuration.timeoutIntervalForRequest = TimeInterval(snapshot.connectTimeoutMillis) / 1000.0
    }
    if snapshot.readTimeoutMillis > 0 {
        configuration.timeoutIntervalForResource = TimeInterval(snapshot.readTimeoutMillis) / 1000.0
    }
    if let protocolClassName = ProcessInfo.processInfo.environment["KSWIFTK_HTTP_PROTOCOL_CLASS"],
       let protocolClass = NSClassFromString(protocolClassName) as? URLProtocol.Type
    {
        configuration.protocolClasses = [protocolClass]
    }
    let delegate = RuntimeHTTPRedirectDelegate(followRedirects: snapshot.followRedirects)
    let session = URLSession(configuration: configuration, delegate: delegate, delegateQueue: nil)
    return (session, delegate)
}

private func runtimeHTTPResponseHandle(
    data: Data?,
    response: URLResponse?,
    error: Error?
) -> Int {
    let httpResponse = response as? HTTPURLResponse
    let headers = runtimeHTTPNormalizedHeaders(httpResponse?.allHeaderFields)
    let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? data.map { String(decoding: $0, as: UTF8.self) } ?? ""
    let url = response?.url?.absoluteString ?? ""
    let errorMessage = error?.localizedDescription
    let timedOut = (error as? URLError)?.code == .timedOut
    return runtimeHTTPResponseHandle(
        statusCode: httpResponse?.statusCode ?? 0,
        body: body,
        url: url,
        headers: headers,
        contentType: headers["content-type"],
        errorMessage: errorMessage,
        timedOut: timedOut
    )
}

private func runtimeHTTPPerformRequest(
    clientRaw: Int,
    method: String,
    urlString: String,
    body: String?,
    completion: @escaping @Sendable (Int) -> Void
) {
    guard let client = runtimeHTTPClientBox(from: clientRaw) else {
        completion(runtimeHTTPErrorResponse(message: "Invalid HttpClient handle"))
        return
    }
    guard let (request, snapshot) = runtimeHTTPPrepareRequest(
        client: client,
        method: method,
        urlString: urlString,
        body: body
    ) else {
        completion(runtimeHTTPErrorResponse(message: "Invalid URL: \(urlString)", url: urlString))
        return
    }

    final class RequestPerformerBox: @unchecked Sendable {
        var body: (@Sendable (URLRequest, Int) -> Void)?
    }
    let performer = RequestPerformerBox()
    performer.body = { currentRequest, redirectCount in
        let (session, _) = runtimeHTTPMakeSession(snapshot: snapshot)
        let task = session.dataTask(with: currentRequest) { data, response, error in
            if snapshot.followRedirects,
               redirectCount < 10,
               let httpResponse = response as? HTTPURLResponse,
               (300 ... 399).contains(httpResponse.statusCode),
               let location = httpResponse.value(forHTTPHeaderField: "Location"),
               let baseURL = currentRequest.url,
               let redirectedURL = URL(string: location, relativeTo: baseURL)?.absoluteURL
            {
                session.finishTasksAndInvalidate()
                var redirectedRequest = currentRequest
                redirectedRequest.url = redirectedURL
                performer.body?(redirectedRequest, redirectCount + 1)
                return
            }

            let responseHandle = runtimeHTTPResponseHandle(data: data, response: response, error: error)
            session.finishTasksAndInvalidate()
            performer.body = nil
            completion(responseHandle)
        }
        task.resume()
    }

    performer.body?(request, 0)
}

private func runtimeHTTPPerformBlockingRequest(
    clientRaw: Int,
    method: String,
    urlString: String,
    body: String?
) -> Int {
    final class ResponseBox: @unchecked Sendable {
        var value: Int
        init(value: Int) { self.value = value }
    }
    let semaphore = DispatchSemaphore(value: 0)
    let responseHandle = ResponseBox(value: runtimeHTTPErrorResponse(message: "Request did not complete", url: urlString))
    runtimeHTTPPerformRequest(clientRaw: clientRaw, method: method, urlString: urlString, body: body) { handle in
        responseHandle.value = handle
        semaphore.signal()
    }
    semaphore.wait()
    return responseHandle.value
}

private func runtimeHTTPSuspendRequest(
    clientRaw: Int,
    method: String,
    urlRaw: Int,
    bodyRaw: Int?,
    continuation: Int
) -> Int {
    guard let state = runtimeContinuationState(from: continuation) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: HTTP async request received invalid continuation handle")
    }
    let urlString = networkString(from: urlRaw, caller: #function)
    let bodyString = bodyRaw.map { networkString(from: $0, caller: #function) }
    state.thrownException = 0
    state.completion = 0
    runtimeHTTPPerformRequest(clientRaw: clientRaw, method: method, urlString: urlString, body: bodyString) { handle in
        if let resumedState = runtimeContinuationState(from: continuation) {
            resumedState.completion = Int64(handle)
            resumedState.thrownException = 0
            resumedState.signalResume()
        }
    }
    return Int(bitPattern: kk_coroutine_suspended())
}

final class RuntimeURLBox {
    let url: URL
    let components: URLComponents

    init(url: URL, components: URLComponents) {
        self.url = url
        self.components = components
    }
}

private func runtimeURLBox(from raw: Int) -> RuntimeURLBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeURLBox.self)
}

private func boxURL(_ url: URL) -> Int {
    let resolvedURL = url.absoluteURL
    let components = URLComponents(url: resolvedURL, resolvingAgainstBaseURL: true)
        ?? URLComponents(string: resolvedURL.absoluteString)
        ?? URLComponents()
    return registerRuntimeObject(RuntimeURLBox(url: resolvedURL, components: components))
}

private func runtimeURL(from spec: String) -> URL? {
    URL(string: spec)
}

private func runtimeURLRelative(baseRaw: Int, relativeRaw: Int) -> URL? {
    guard let base = runtimeURLBox(from: baseRaw) else { return nil }
    let relative = networkString(from: relativeRaw, caller: #function)
    return URL(string: relative, relativeTo: base.url)?.absoluteURL
}

private func runtimeURLComponents(from raw: Int, caller: StaticString) -> RuntimeURLBox {
    guard let box = runtimeURLBox(from: raw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: \(caller) received invalid URL handle")
    }
    return box
}

private func runtimeURLPort(_ box: RuntimeURLBox) -> Int {
    box.components.port ?? -1
}

private func runtimeURLPath(_ box: RuntimeURLBox) -> String {
    let path = box.components.percentEncodedPath.isEmpty ? box.url.path : box.components.path
    return path.isEmpty ? "/" : path
}

private func runtimeURLHost(_ box: RuntimeURLBox) -> String {
    box.components.host ?? ""
}

private func runtimeURLProtocol(_ box: RuntimeURLBox) -> String {
    box.components.scheme ?? ""
}

private func runtimeURLExternalForm(_ box: RuntimeURLBox) -> String {
    box.url.absoluteString
}

private func runtimeURLCanonicalEqualityKey(_ box: RuntimeURLBox) -> String {
    let scheme = runtimeURLProtocol(box).lowercased()
    let host = runtimeURLHost(box).lowercased()
    let port = runtimeURLPort(box)
    let path = runtimeURLPath(box)
    let query = box.components.percentEncodedQuery ?? ""
    let fragment = box.components.percentEncodedFragment ?? ""
    return "\(scheme)|\(host)|\(port)|\(path)|\(query)|\(fragment)"
}

private func runtimeURLSameFileKey(_ box: RuntimeURLBox) -> String {
    let scheme = runtimeURLProtocol(box).lowercased()
    let host = runtimeURLHost(box).lowercased()
    let port = runtimeURLPort(box)
    let path = runtimeURLPath(box)
    let query = box.components.percentEncodedQuery ?? ""
    return "\(scheme)|\(host)|\(port)|\(path)|\(query)"
}

private func runtimeURLHash(_ text: String) -> Int {
    var hasher = Hasher()
    hasher.combine(text)
    return hasher.finalize()
}

private func runtimePercentEncode(_ text: String) -> String {
    var allowed = CharacterSet.urlQueryAllowed
    allowed.remove(charactersIn: "+&=?")
    return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
}

private func runtimePercentDecode(_ text: String) -> String {
    text.removingPercentEncoding ?? text
}

@_cdecl("kk_url_new")
public func kk_url_new(_ specRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let spec = networkString(from: specRaw, caller: #function)
    guard let url = runtimeURL(from: spec) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "MalformedURLException: \(spec)")
        return 0
    }
    return boxURL(url)
}

@_cdecl("kk_url_new_relative")
public func kk_url_new_relative(_ baseRaw: Int, _ relativeRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard runtimeURLBox(from: baseRaw) != nil else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_url_new_relative received invalid base URL handle")
    }
    let relative = networkString(from: relativeRaw, caller: #function)
    guard let url = runtimeURLRelative(baseRaw: baseRaw, relativeRaw: relativeRaw) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "MalformedURLException: \(relative)")
        return 0
    }
    return boxURL(url)
}

@_cdecl("kk_url_protocol")
public func kk_url_protocol(_ urlRaw: Int) -> Int {
    networkStringRaw(runtimeURLProtocol(runtimeURLComponents(from: urlRaw, caller: #function)))
}

@_cdecl("kk_url_host")
public func kk_url_host(_ urlRaw: Int) -> Int {
    networkStringRaw(runtimeURLHost(runtimeURLComponents(from: urlRaw, caller: #function)))
}

@_cdecl("kk_url_port")
public func kk_url_port(_ urlRaw: Int) -> Int {
    runtimeURLPort(runtimeURLComponents(from: urlRaw, caller: #function))
}

@_cdecl("kk_url_path")
public func kk_url_path(_ urlRaw: Int) -> Int {
    networkStringRaw(runtimeURLPath(runtimeURLComponents(from: urlRaw, caller: #function)))
}

@_cdecl("kk_url_query")
public func kk_url_query(_ urlRaw: Int) -> Int {
    let box = runtimeURLComponents(from: urlRaw, caller: #function)
    guard let query = box.components.percentEncodedQuery else { return runtimeNullSentinelInt }
    return networkStringRaw(runtimePercentDecode(query))
}

@_cdecl("kk_url_fragment")
public func kk_url_fragment(_ urlRaw: Int) -> Int {
    let box = runtimeURLComponents(from: urlRaw, caller: #function)
    guard let fragment = box.components.percentEncodedFragment else { return runtimeNullSentinelInt }
    return networkStringRaw(runtimePercentDecode(fragment))
}

@_cdecl("kk_url_toURI")
public func kk_url_toURI(_ urlRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let box = runtimeURLComponents(from: urlRaw, caller: #function)
    guard let components = URLComponents(url: box.url, resolvingAgainstBaseURL: true) else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "URISyntaxException: \(box.url.absoluteString)")
        return 0
    }
    return registerRuntimeObject(RuntimeURIBox(components: components))
}

@_cdecl("kk_url_toExternalForm")
public func kk_url_toExternalForm(_ urlRaw: Int) -> Int {
    networkStringRaw(runtimeURLExternalForm(runtimeURLComponents(from: urlRaw, caller: #function)))
}

@_cdecl("kk_url_sameFile")
public func kk_url_sameFile(_ lhsRaw: Int, _ rhsRaw: Int) -> Int {
    let lhs = runtimeURLComponents(from: lhsRaw, caller: #function)
    let rhs = runtimeURLComponents(from: rhsRaw, caller: #function)
    return kk_box_bool(runtimeURLSameFileKey(lhs) == runtimeURLSameFileKey(rhs) ? 1 : 0)
}

@_cdecl("kk_url_equals")
public func kk_url_equals(_ lhsRaw: Int, _ rhsRaw: Int) -> Int {
    guard let lhs = runtimeURLBox(from: lhsRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_url_equals received invalid URL handle")
    }
    guard rhsRaw != runtimeNullSentinelInt else {
        return kk_box_bool(0)
    }
    guard let rhs = runtimeURLBox(from: rhsRaw) else {
        return kk_box_bool(0)
    }
    return kk_box_bool(runtimeURLCanonicalEqualityKey(lhs) == runtimeURLCanonicalEqualityKey(rhs) ? 1 : 0)
}

@_cdecl("kk_url_hashCode")
public func kk_url_hashCode(_ urlRaw: Int) -> Int {
    runtimeURLHash(runtimeURLCanonicalEqualityKey(runtimeURLComponents(from: urlRaw, caller: #function)))
}

@_cdecl("kk_url_encode")
public func kk_url_encode(_ valueRaw: Int) -> Int {
    let value = networkString(from: valueRaw, caller: #function)
    return networkStringRaw(runtimePercentEncode(value))
}

@_cdecl("kk_url_decode")
public func kk_url_decode(_ valueRaw: Int) -> Int {
    let value = networkString(from: valueRaw, caller: #function)
    return networkStringRaw(runtimePercentDecode(value))
}

private func networkURL(from uriRaw: Int) -> URL? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: uriRaw),
          let uriBox = tryCast(ptr, to: RuntimeURIBox.self)
    else {
        return nil
    }
    return uriBox.components.url
}

private func networkHeaderPairs(from response: HTTPURLResponse?) -> [(String, [String])] {
    guard let response else { return [] }
    var pairs: [(String, [String])] = []
    for (rawKey, rawValue) in response.allHeaderFields {
        guard let key = rawKey as? String else { continue }
        if let values = rawValue as? [String] {
            pairs.append((key, values))
        } else {
            pairs.append((key, ["\(rawValue)"]))
        }
    }
    pairs.sort { $0.0.localizedCaseInsensitiveCompare($1.0) == .orderedAscending }
    return pairs
}

private func networkHeaderMapRaw(_ headers: [(String, [String])]) -> Int {
    let keys = headers.map { networkStringRaw($0.0) }
    let values = headers.map { header in
        registerRuntimeObject(RuntimeListBox(elements: header.1.map(networkStringRaw)))
    }
    return registerRuntimeObject(RuntimeMapBox(keys: keys, values: values))
}

private func networkHeaderFirstValue(_ headers: [(String, [String])], name: String) -> String? {
    headers.first(where: { $0.0.caseInsensitiveCompare(name) == .orderedSame })?.1.first
}

@_cdecl("kk_http_client_newHttpClient")
public func kk_http_client_newHttpClient() -> Int {
    registerRuntimeObject(RuntimeHttpClientBox())
}

@_cdecl("kk_http_request_newBuilder")
public func kk_http_request_newBuilder() -> Int {
    registerRuntimeObject(RuntimeHttpRequestBuilderBox())
}

@_cdecl("kk_http_request_newBuilder_uri")
public func kk_http_request_newBuilder_uri(_ uriRaw: Int) -> Int {
    registerRuntimeObject(RuntimeHttpRequestBuilderBox(url: networkURL(from: uriRaw)))
}

@_cdecl("kk_http_request_builder_uri")
public func kk_http_request_builder_uri(_ builderRaw: Int, _ uriRaw: Int) -> Int {
    guard let builder = runtimeHttpRequestBuilderBox(from: builderRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_http_request_builder_uri received invalid builder handle")
    }
    builder.url = networkURL(from: uriRaw)
    return builderRaw
}

@_cdecl("kk_http_request_builder_header")
public func kk_http_request_builder_header(_ builderRaw: Int, _ nameRaw: Int, _ valueRaw: Int) -> Int {
    guard let builder = runtimeHttpRequestBuilderBox(from: builderRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_http_request_builder_header received invalid builder handle")
    }
    builder.headers.append((networkString(from: nameRaw, caller: #function), networkString(from: valueRaw, caller: #function)))
    return builderRaw
}

@_cdecl("kk_http_request_builder_GET")
public func kk_http_request_builder_GET(_ builderRaw: Int) -> Int {
    guard let builder = runtimeHttpRequestBuilderBox(from: builderRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_http_request_builder_GET received invalid builder handle")
    }
    builder.method = "GET"
    builder.body = nil
    return builderRaw
}

@_cdecl("kk_http_request_builder_POST")
public func kk_http_request_builder_POST(_ builderRaw: Int, _ publisherRaw: Int) -> Int {
    guard let builder = runtimeHttpRequestBuilderBox(from: builderRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_http_request_builder_POST received invalid builder handle")
    }
    guard let publisher = runtimeHttpBodyPublisherBox(from: publisherRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_http_request_builder_POST received invalid body publisher handle")
    }
    builder.method = "POST"
    builder.body = publisher.data
    return builderRaw
}

@_cdecl("kk_http_request_builder_build")
public func kk_http_request_builder_build(_ builderRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let builder = runtimeHttpRequestBuilderBox(from: builderRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_http_request_builder_build received invalid builder handle")
    }
    guard let url = builder.url else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IllegalStateException: HTTP request URI is not set")
        return 0
    }
    return registerRuntimeObject(RuntimeHttpRequestBox(url: url, method: builder.method, headers: builder.headers, body: builder.body))
}

@_cdecl("kk_http_body_publishers_noBody")
public func kk_http_body_publishers_noBody(_ bodyPublishersRaw: Int) -> Int {
    _ = bodyPublishersRaw
    return registerRuntimeObject(RuntimeHttpBodyPublisherBox(data: nil))
}

@_cdecl("kk_http_body_publishers_ofString")
public func kk_http_body_publishers_ofString(_ bodyPublishersRaw: Int, _ bodyRaw: Int) -> Int {
    _ = bodyPublishersRaw
    let text = networkString(from: bodyRaw, caller: #function)
    return registerRuntimeObject(RuntimeHttpBodyPublisherBox(data: text.data(using: .utf8) ?? Data()))
}

@_cdecl("kk_http_body_handlers_ofString")
public func kk_http_body_handlers_ofString(_ bodyHandlersRaw: Int) -> Int {
    _ = bodyHandlersRaw
    return registerRuntimeObject(RuntimeHttpBodyHandlerBox(kind: "string"))
}

@_cdecl("kk_http_client_send")
public func kk_http_client_send(_ clientRaw: Int, _ requestRaw: Int, _ bodyHandlerRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard runtimeHttpClientBox(from: clientRaw) != nil else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_http_client_send received invalid client handle")
    }
    guard let request = runtimeHttpRequestBox(from: requestRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_http_client_send received invalid request handle")
    }
    guard let bodyHandler = runtimeHttpBodyHandlerBox(from: bodyHandlerRaw), bodyHandler.kind == "string" else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_http_client_send received invalid body handler handle")
    }

    var urlRequest = URLRequest(url: request.url)
    urlRequest.httpMethod = request.method
    urlRequest.httpBody = request.body
    for (name, value) in request.headers {
        urlRequest.addValue(value, forHTTPHeaderField: name)
    }

    let semaphore = DispatchSemaphore(value: 0)
    let result = RuntimeHTTPTaskResultBox()

    URLSession.shared.dataTask(with: urlRequest) { data, response, error in
        result.data = data ?? Data()
        result.response = response
        result.error = error
        semaphore.signal()
    }.resume()
    semaphore.wait()

    if let responseError = result.error {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: \(responseError.localizedDescription)")
        return 0
    }

    guard let httpResponse = result.response as? HTTPURLResponse else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "IOException: Missing HTTP response")
        return 0
    }

    let body = String(data: result.data, encoding: .utf8) ?? String(decoding: result.data, as: UTF8.self)
    let responseBox = RuntimeHttpResponseBox(
        statusCode: httpResponse.statusCode,
        headers: networkHeaderPairs(from: httpResponse),
        body: body
    )
    return registerRuntimeObject(responseBox)
}

@_cdecl("kk_http_response_statusCode")
public func kk_http_response_statusCode(_ responseRaw: Int) -> Int {
    guard let response = runtimeHttpResponseBox(from: responseRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_http_response_statusCode received invalid response handle")
    }
    return response.statusCode
}

@_cdecl("kk_http_response_body")
public func kk_http_response_body(_ responseRaw: Int) -> Int {
    guard let response = runtimeHttpResponseBox(from: responseRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_http_response_body received invalid response handle")
    }
    return networkStringRaw(response.body)
}

@_cdecl("kk_http_response_headers")
public func kk_http_response_headers(_ responseRaw: Int) -> Int {
    guard let response = runtimeHttpResponseBox(from: responseRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_http_response_headers received invalid response handle")
    }
    return registerRuntimeObject(RuntimeHttpHeadersBox(headers: response.headers))
}

@_cdecl("kk_http_headers_map")
public func kk_http_headers_map(_ headersRaw: Int) -> Int {
    guard let headers = runtimeHttpHeadersBox(from: headersRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_http_headers_map received invalid headers handle")
    }
    return networkHeaderMapRaw(headers.headers)
}

@_cdecl("kk_http_headers_firstValue")
public func kk_http_headers_firstValue(_ headersRaw: Int, _ nameRaw: Int) -> Int {
    guard let headers = runtimeHttpHeadersBox(from: headersRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_http_headers_firstValue received invalid headers handle")
    }
    let name = networkString(from: nameRaw, caller: #function)
    guard let value = networkHeaderFirstValue(headers.headers, name: name) else {
        return runtimeNullSentinelInt
    }
    return networkStringRaw(value)
}

@_cdecl("kk_http_client_new")
public func kk_http_client_new() -> Int {
    registerRuntimeObject(RuntimeHTTPClientBox())
}

@_cdecl("kk_http_client_setConnectTimeoutMillis")
public func kk_http_client_setConnectTimeoutMillis(_ clientRaw: Int, _ timeoutMillis: Int) -> Int {
    guard let client = runtimeHTTPClientBox(from: clientRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_http_client_setConnectTimeoutMillis received invalid client handle")
    }
    client.setConnectTimeoutMillis(timeoutMillis)
    return 0
}

@_cdecl("kk_http_client_setReadTimeoutMillis")
public func kk_http_client_setReadTimeoutMillis(_ clientRaw: Int, _ timeoutMillis: Int) -> Int {
    guard let client = runtimeHTTPClientBox(from: clientRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_http_client_setReadTimeoutMillis received invalid client handle")
    }
    client.setReadTimeoutMillis(timeoutMillis)
    return 0
}

@_cdecl("kk_http_client_setFollowRedirects")
public func kk_http_client_setFollowRedirects(_ clientRaw: Int, _ enabled: Int) -> Int {
    guard let client = runtimeHTTPClientBox(from: clientRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_http_client_setFollowRedirects received invalid client handle")
    }
    client.setFollowRedirects(enabled != 0)
    return 0
}

@_cdecl("kk_http_client_setDefaultHeader")
public func kk_http_client_setDefaultHeader(_ clientRaw: Int, _ nameRaw: Int, _ valueRaw: Int) -> Int {
    guard let client = runtimeHTTPClientBox(from: clientRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_http_client_setDefaultHeader received invalid client handle")
    }
    client.setDefaultHeader(
        name: networkString(from: nameRaw, caller: #function),
        value: networkString(from: valueRaw, caller: #function)
    )
    return 0
}

@_cdecl("kk_http_client_setBasicAuth")
public func kk_http_client_setBasicAuth(_ clientRaw: Int, _ usernameRaw: Int, _ passwordRaw: Int) -> Int {
    guard let client = runtimeHTTPClientBox(from: clientRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_http_client_setBasicAuth received invalid client handle")
    }
    client.setBasicAuth(
        username: networkString(from: usernameRaw, caller: #function),
        password: networkString(from: passwordRaw, caller: #function)
    )
    return 0
}

@_cdecl("kk_http_client_setBearerToken")
public func kk_http_client_setBearerToken(_ clientRaw: Int, _ tokenRaw: Int) -> Int {
    guard let client = runtimeHTTPClientBox(from: clientRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_http_client_setBearerToken received invalid client handle")
    }
    client.setBearerToken(networkString(from: tokenRaw, caller: #function))
    return 0
}

@_cdecl("kk_http_client_clearAuthentication")
public func kk_http_client_clearAuthentication(_ clientRaw: Int) -> Int {
    guard let client = runtimeHTTPClientBox(from: clientRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_http_client_clearAuthentication received invalid client handle")
    }
    client.clearAuthentication()
    return 0
}

@_cdecl("kk_http_client_get")
public func kk_http_client_get(_ clientRaw: Int, _ urlRaw: Int) -> Int {
    runtimeHTTPPerformBlockingRequest(
        clientRaw: clientRaw,
        method: "GET",
        urlString: networkString(from: urlRaw, caller: #function),
        body: nil
    )
}

@_cdecl("kk_http_client_post")
public func kk_http_client_post(_ clientRaw: Int, _ urlRaw: Int, _ bodyRaw: Int) -> Int {
    runtimeHTTPPerformBlockingRequest(
        clientRaw: clientRaw,
        method: "POST",
        urlString: networkString(from: urlRaw, caller: #function),
        body: networkString(from: bodyRaw, caller: #function)
    )
}

@_cdecl("kk_http_client_get_async")
public func kk_http_client_get_async(_ clientRaw: Int, _ urlRaw: Int, _ continuation: Int) -> Int {
    runtimeHTTPSuspendRequest(
        clientRaw: clientRaw,
        method: "GET",
        urlRaw: urlRaw,
        bodyRaw: nil,
        continuation: continuation
    )
}

@_cdecl("kk_http_client_post_async")
public func kk_http_client_post_async(_ clientRaw: Int, _ urlRaw: Int, _ bodyRaw: Int, _ continuation: Int) -> Int {
    runtimeHTTPSuspendRequest(
        clientRaw: clientRaw,
        method: "POST",
        urlRaw: urlRaw,
        bodyRaw: bodyRaw,
        continuation: continuation
    )
}

@_cdecl("kk_http_response_url")
public func kk_http_response_url(_ responseRaw: Int) -> Int {
    guard let response = runtimeHttpResponseBox(from: responseRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_http_response_url received invalid response handle")
    }
    return networkStringRaw(response.url)
}

@_cdecl("kk_http_response_contentType")
public func kk_http_response_contentType(_ responseRaw: Int) -> Int {
    guard let response = runtimeHttpResponseBox(from: responseRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_http_response_contentType received invalid response handle")
    }
    guard let contentType = response.contentType else { return runtimeNullSentinelInt }
    return networkStringRaw(contentType)
}

@_cdecl("kk_http_response_errorMessage")
public func kk_http_response_errorMessage(_ responseRaw: Int) -> Int {
    guard let response = runtimeHttpResponseBox(from: responseRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_http_response_errorMessage received invalid response handle")
    }
    guard let errorMessage = response.errorMessage else { return runtimeNullSentinelInt }
    return networkStringRaw(errorMessage)
}

@_cdecl("kk_http_response_timedOut")
public func kk_http_response_timedOut(_ responseRaw: Int) -> Int {
    guard let response = runtimeHttpResponseBox(from: responseRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_http_response_timedOut received invalid response handle")
    }
    return response.timedOut ? 1 : 0
}

@_cdecl("kk_http_response_isSuccessful")
public func kk_http_response_isSuccessful(_ responseRaw: Int) -> Int {
    guard let response = runtimeHttpResponseBox(from: responseRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_http_response_isSuccessful received invalid response handle")
    }
    return response.isSuccessful ? 1 : 0
}

@_cdecl("kk_http_response_header")
public func kk_http_response_header(_ responseRaw: Int, _ nameRaw: Int) -> Int {
    guard let response = runtimeHttpResponseBox(from: responseRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_http_response_header received invalid response handle")
    }
    let name = networkString(from: nameRaw, caller: #function)
    guard let value = networkHeaderFirstValue(response.headers, name: name) else {
        return runtimeNullSentinelInt
    }
    return networkStringRaw(value)
}
