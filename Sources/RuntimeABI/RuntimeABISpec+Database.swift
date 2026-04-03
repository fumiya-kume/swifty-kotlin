// Database connection pool ABI specs (STDLIB-DB-142)

public extension RuntimeABISpec {
    static let databaseFunctions: [RuntimeABIFunctionSpec] = [
        RuntimeABIFunctionSpec(
            name: "kk_db_pool_new",
            parameters: [
                RuntimeABIParameter(name: "maxConnections", type: .intptr),
                RuntimeABIParameter(name: "timeoutMillis", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Database"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_db_pool_acquire",
            parameters: [
                RuntimeABIParameter(name: "poolRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Database"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_db_pool_release",
            parameters: [
                RuntimeABIParameter(name: "poolRaw", type: .intptr),
                RuntimeABIParameter(name: "connectionRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Database"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_db_pool_active_count",
            parameters: [
                RuntimeABIParameter(name: "poolRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Database"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_db_pool_idle_count",
            parameters: [
                RuntimeABIParameter(name: "poolRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Database"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_db_pool_waiting_count",
            parameters: [
                RuntimeABIParameter(name: "poolRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Database"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_db_pool_total_count",
            parameters: [
                RuntimeABIParameter(name: "poolRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Database"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_db_pool_max_connections",
            parameters: [
                RuntimeABIParameter(name: "poolRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Database"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_db_pool_timeout_millis",
            parameters: [
                RuntimeABIParameter(name: "poolRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Database"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_db_connection_id",
            parameters: [
                RuntimeABIParameter(name: "connectionRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Database"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_db_connection_in_use",
            parameters: [
                RuntimeABIParameter(name: "connectionRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Database"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_db_connection_is_open",
            parameters: [
                RuntimeABIParameter(name: "connectionRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Database"
        ),
    ]
}
