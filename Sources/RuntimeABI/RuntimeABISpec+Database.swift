// Database ABI specs (STDLIB-DB-142 / STDLIB-DB-140)

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
            name: "kk_jdbc_driver_manager_getConnection",
            parameters: [
                RuntimeABIParameter(name: "urlRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Database"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_jdbc_connection_createStatement",
            parameters: [
                RuntimeABIParameter(name: "connectionRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Database"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_jdbc_connection_prepareStatement",
            parameters: [
                RuntimeABIParameter(name: "connectionRaw", type: .intptr),
                RuntimeABIParameter(name: "sqlRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Database"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_jdbc_connection_close",
            parameters: [
                RuntimeABIParameter(name: "connectionRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Database"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_jdbc_statement_executeQuery",
            parameters: [
                RuntimeABIParameter(name: "statementRaw", type: .intptr),
                RuntimeABIParameter(name: "sqlRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Database"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_jdbc_statement_executeUpdate",
            parameters: [
                RuntimeABIParameter(name: "statementRaw", type: .intptr),
                RuntimeABIParameter(name: "sqlRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Database"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_jdbc_statement_close",
            parameters: [
                RuntimeABIParameter(name: "statementRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Database"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_jdbc_prepared_statement_setInt",
            parameters: [
                RuntimeABIParameter(name: "preparedStatementRaw", type: .intptr),
                RuntimeABIParameter(name: "index", type: .intptr),
                RuntimeABIParameter(name: "value", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Database"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_jdbc_prepared_statement_setString",
            parameters: [
                RuntimeABIParameter(name: "preparedStatementRaw", type: .intptr),
                RuntimeABIParameter(name: "index", type: .intptr),
                RuntimeABIParameter(name: "valueRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Database"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_jdbc_prepared_statement_executeQuery",
            parameters: [
                RuntimeABIParameter(name: "preparedStatementRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Database"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_jdbc_prepared_statement_executeUpdate",
            parameters: [
                RuntimeABIParameter(name: "preparedStatementRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Database"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_jdbc_prepared_statement_close",
            parameters: [
                RuntimeABIParameter(name: "preparedStatementRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Database"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_jdbc_result_set_next",
            parameters: [
                RuntimeABIParameter(name: "resultSetRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Database"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_jdbc_result_set_getInt",
            parameters: [
                RuntimeABIParameter(name: "resultSetRaw", type: .intptr),
                RuntimeABIParameter(name: "index", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Database"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_jdbc_result_set_getIntByLabel",
            parameters: [
                RuntimeABIParameter(name: "resultSetRaw", type: .intptr),
                RuntimeABIParameter(name: "labelRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Database"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_jdbc_result_set_getString",
            parameters: [
                RuntimeABIParameter(name: "resultSetRaw", type: .intptr),
                RuntimeABIParameter(name: "index", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Database"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_jdbc_result_set_getStringByLabel",
            parameters: [
                RuntimeABIParameter(name: "resultSetRaw", type: .intptr),
                RuntimeABIParameter(name: "labelRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Database"
        ),
        RuntimeABIFunctionSpec(
            name: "kk_jdbc_result_set_close",
            parameters: [
                RuntimeABIParameter(name: "resultSetRaw", type: .intptr),
                RuntimeABIParameter(name: "outThrown", type: .nullableIntptrPointer),
            ],
            returnType: .intptr,
            section: "Database"
        ),
    ]
}
