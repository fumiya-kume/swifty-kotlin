public extension RuntimeABISpec {
    static let networkFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(name: "kk_http_client_new", parameters: [], returnType: .intptr, section: "Network"),
        RuntimeABIFunctionSpec(
            name: "kk_http_client_setConnectTimeoutMillis",
            parameters: [
                RuntimeABIParameter(name: "clientRaw", type: .intptr),
                RuntimeABIParameter(name: "timeoutMillis", type: .intptr),
            ],
            returnType: .intptr,
            section: "Network"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_http_client_setReadTimeoutMillis",
            parameters: [
                RuntimeABIParameter(name: "clientRaw", type: .intptr),
                RuntimeABIParameter(name: "timeoutMillis", type: .intptr),
            ],
            returnType: .intptr,
            section: "Network"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_http_client_setFollowRedirects",
            parameters: [
                RuntimeABIParameter(name: "clientRaw", type: .intptr),
                RuntimeABIParameter(name: "enabled", type: .intptr),
            ],
            returnType: .intptr,
            section: "Network"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_http_client_setDefaultHeader",
            parameters: [
                RuntimeABIParameter(name: "clientRaw", type: .intptr),
                RuntimeABIParameter(name: "nameRaw", type: .intptr),
                RuntimeABIParameter(name: "valueRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Network"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_http_client_setBasicAuth",
            parameters: [
                RuntimeABIParameter(name: "clientRaw", type: .intptr),
                RuntimeABIParameter(name: "usernameRaw", type: .intptr),
                RuntimeABIParameter(name: "passwordRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Network"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_http_client_setBearerToken",
            parameters: [
                RuntimeABIParameter(name: "clientRaw", type: .intptr),
                RuntimeABIParameter(name: "tokenRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Network"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_http_client_clearAuthentication",
            parameters: [RuntimeABIParameter(name: "clientRaw", type: .intptr)],
            returnType: .intptr,
            section: "Network"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_http_client_get",
            parameters: [
                RuntimeABIParameter(name: "clientRaw", type: .intptr),
                RuntimeABIParameter(name: "urlRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Network"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_http_client_post",
            parameters: [
                RuntimeABIParameter(name: "clientRaw", type: .intptr),
                RuntimeABIParameter(name: "urlRaw", type: .intptr),
                RuntimeABIParameter(name: "bodyRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Network"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_http_client_get_async",
            parameters: [
                RuntimeABIParameter(name: "clientRaw", type: .intptr),
                RuntimeABIParameter(name: "urlRaw", type: .intptr),
                RuntimeABIParameter(name: "continuation", type: .intptr),
            ],
            returnType: .intptr,
            section: "Network"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_http_client_post_async",
            parameters: [
                RuntimeABIParameter(name: "clientRaw", type: .intptr),
                RuntimeABIParameter(name: "urlRaw", type: .intptr),
                RuntimeABIParameter(name: "bodyRaw", type: .intptr),
                RuntimeABIParameter(name: "continuation", type: .intptr),
            ],
            returnType: .intptr,
            section: "Network"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_http_response_statusCode",
            parameters: [RuntimeABIParameter(name: "responseRaw", type: .intptr)],
            returnType: .intptr,
            section: "Network"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_http_response_body",
            parameters: [RuntimeABIParameter(name: "responseRaw", type: .intptr)],
            returnType: .intptr,
            section: "Network"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_http_response_url",
            parameters: [RuntimeABIParameter(name: "responseRaw", type: .intptr)],
            returnType: .intptr,
            section: "Network"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_http_response_contentType",
            parameters: [RuntimeABIParameter(name: "responseRaw", type: .intptr)],
            returnType: .intptr,
            section: "Network"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_http_response_errorMessage",
            parameters: [RuntimeABIParameter(name: "responseRaw", type: .intptr)],
            returnType: .intptr,
            section: "Network"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_http_response_timedOut",
            parameters: [RuntimeABIParameter(name: "responseRaw", type: .intptr)],
            returnType: .intptr,
            section: "Network"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_http_response_isSuccessful",
            parameters: [RuntimeABIParameter(name: "responseRaw", type: .intptr)],
            returnType: .intptr,
            section: "Network"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_http_response_header",
            parameters: [
                RuntimeABIParameter(name: "responseRaw", type: .intptr),
                RuntimeABIParameter(name: "nameRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Network"
        ),
    ]
}
