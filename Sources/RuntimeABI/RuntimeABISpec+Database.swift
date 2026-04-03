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
        RuntimeABIFunctionSpec(
            name: "kk_driver_manager_getConnection",
            parameters: [
                RuntimeABIParameter(name: "urlRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Database"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_connection_getAutoCommit",
            parameters: [
                RuntimeABIParameter(name: "connectionRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Database"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_connection_setAutoCommit",
            parameters: [
                RuntimeABIParameter(name: "connectionRaw", type: .intptr),
                RuntimeABIParameter(name: "valueRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Database"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_connection_commit",
            parameters: [
                RuntimeABIParameter(name: "connectionRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Database"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_connection_rollback",
            parameters: [
                RuntimeABIParameter(name: "connectionRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Database"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_connection_setSavepoint",
            parameters: [
                RuntimeABIParameter(name: "connectionRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Database"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_connection_setSavepoint_named",
            parameters: [
                RuntimeABIParameter(name: "connectionRaw", type: .intptr),
                RuntimeABIParameter(name: "nameRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Database"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_connection_rollback_to_savepoint",
            parameters: [
                RuntimeABIParameter(name: "connectionRaw", type: .intptr),
                RuntimeABIParameter(name: "savepointRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Database"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_connection_releaseSavepoint",
            parameters: [
                RuntimeABIParameter(name: "connectionRaw", type: .intptr),
                RuntimeABIParameter(name: "savepointRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Database"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_connection_getTransactionIsolation",
            parameters: [
                RuntimeABIParameter(name: "connectionRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Database"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_connection_setTransactionIsolation",
            parameters: [
                RuntimeABIParameter(name: "connectionRaw", type: .intptr),
                RuntimeABIParameter(name: "levelRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Database"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_connection_close",
            parameters: [
                RuntimeABIParameter(name: "connectionRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Database"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_connection_isClosed",
            parameters: [
                RuntimeABIParameter(name: "connectionRaw", type: .intptr),
            ],
            returnType: .intptr,
            section: "Database"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_savepoint_getSavepointId",
            parameters: [
                RuntimeABIParameter(name: "savepointRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Database"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_savepoint_getSavepointName",
            parameters: [
                RuntimeABIParameter(name: "savepointRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Database"
        ),
    ]
}
