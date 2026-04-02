import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

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

private final class RuntimeHTTPResponseBox {
    let statusCode: Int
    let body: String
    let url: String
    let headers: [String: String]
    let contentType: String?
    let errorMessage: String?
    let timedOut: Bool

    init(
        statusCode: Int,
        body: String,
        url: String,
        headers: [String: String],
        contentType: String?,
        errorMessage: String?,
        timedOut: Bool
    ) {
        self.statusCode = statusCode
        self.body = body
        self.url = url
        self.headers = headers
        self.contentType = contentType
        self.errorMessage = errorMessage
        self.timedOut = timedOut
    }

    var isSuccessful: Bool {
        errorMessage == nil && (200 ... 299).contains(statusCode)
    }
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

private func runtimeHTTPClientBox(from raw: Int) -> RuntimeHTTPClientBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeHTTPClientBox.self)
}

private func runtimeHTTPResponseBox(from raw: Int) -> RuntimeHTTPResponseBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeHTTPResponseBox.self)
}

private func networkMakeStringRaw(_ value: String) -> Int {
    Int(bitPattern: value.withCString { cstr in
        cstr.withMemoryRebound(to: UInt8.self, capacity: value.utf8.count) { pointer in
            kk_string_from_utf8(pointer, Int32(value.utf8.count))
        }
    })
}

private func networkString(from raw: Int, caller: StaticString) -> String {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw),
          let str = extractString(from: ptr)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: \(caller) received invalid string handle")
    }
    return str
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
    registerRuntimeObject(
        RuntimeHTTPResponseBox(
            statusCode: statusCode,
            body: body,
            url: url,
            headers: headers,
            contentType: contentType,
            errorMessage: errorMessage,
            timedOut: timedOut
        )
    )
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
    guard let url = URL(string: urlString) else {
        return nil
    }
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

@_cdecl("kk_http_response_statusCode")
public func kk_http_response_statusCode(_ responseRaw: Int) -> Int {
    guard let response = runtimeHTTPResponseBox(from: responseRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_http_response_statusCode received invalid response handle")
    }
    return response.statusCode
}

@_cdecl("kk_http_response_body")
public func kk_http_response_body(_ responseRaw: Int) -> Int {
    guard let response = runtimeHTTPResponseBox(from: responseRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_http_response_body received invalid response handle")
    }
    return networkMakeStringRaw(response.body)
}

@_cdecl("kk_http_response_url")
public func kk_http_response_url(_ responseRaw: Int) -> Int {
    guard let response = runtimeHTTPResponseBox(from: responseRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_http_response_url received invalid response handle")
    }
    return networkMakeStringRaw(response.url)
}

@_cdecl("kk_http_response_contentType")
public func kk_http_response_contentType(_ responseRaw: Int) -> Int {
    guard let response = runtimeHTTPResponseBox(from: responseRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_http_response_contentType received invalid response handle")
    }
    guard let contentType = response.contentType else { return runtimeNullSentinelInt }
    return networkMakeStringRaw(contentType)
}

@_cdecl("kk_http_response_errorMessage")
public func kk_http_response_errorMessage(_ responseRaw: Int) -> Int {
    guard let response = runtimeHTTPResponseBox(from: responseRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_http_response_errorMessage received invalid response handle")
    }
    guard let errorMessage = response.errorMessage else { return runtimeNullSentinelInt }
    return networkMakeStringRaw(errorMessage)
}

@_cdecl("kk_http_response_timedOut")
public func kk_http_response_timedOut(_ responseRaw: Int) -> Int {
    guard let response = runtimeHTTPResponseBox(from: responseRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_http_response_timedOut received invalid response handle")
    }
    return response.timedOut ? 1 : 0
}

@_cdecl("kk_http_response_isSuccessful")
public func kk_http_response_isSuccessful(_ responseRaw: Int) -> Int {
    guard let response = runtimeHTTPResponseBox(from: responseRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_http_response_isSuccessful received invalid response handle")
    }
    return response.isSuccessful ? 1 : 0
}

@_cdecl("kk_http_response_header")
public func kk_http_response_header(_ responseRaw: Int, _ nameRaw: Int) -> Int {
    guard let response = runtimeHTTPResponseBox(from: responseRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_http_response_header received invalid response handle")
    }
    let key = networkString(from: nameRaw, caller: #function).lowercased()
    guard let value = response.headers[key] else { return runtimeNullSentinelInt }
    return networkMakeStringRaw(value)
}
