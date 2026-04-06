import Foundation
import CSQLite

// MARK: - JDBC Supplemental Runtime (STDLIB-DB-140)
//
// Extends the JDBC implementation in RuntimeDatabase.swift with additional
// API surface:
//   - Connection.isClosed()
//   - Connection.isValid(timeout)
//   - Connection.isReadOnly()
//   - Connection.getAutoCommit() / setAutoCommit()
//   - Connection.getTransactionIsolation() / setTransactionIsolation()
//   - Connection.commit() / rollback()
//   - Connection.setSavepoint() / releaseSavepoint() / rollback(Savepoint)
//   - Savepoint.getSavepointId() / getSavepointName()
//   - Statement.execute(sql) — boolean form
//   - Statement.isClosed()
//   - Statement.getUpdateCount()
//   - PreparedStatement.execute() — boolean form
//   - PreparedStatement.isClosed()
//   - ResultSet.isClosed()
//   - ResultSet.getRow()

// MARK: - Connection helpers

@_cdecl("kk_jdbc_connection_isClosed")
public func kk_jdbc_connection_isClosed(_ connectionRaw: Int) -> Int {
    guard let connection = jdbcConnectionBox(from: connectionRaw) else {
        return kk_box_bool(1)
    }
    return kk_box_bool(connection.closed ? 1 : 0)
}

@_cdecl("kk_jdbc_connection_isValid")
public func kk_jdbc_connection_isValid(_ connectionRaw: Int, _ timeoutSeconds: Int) -> Int {
    guard let connection = jdbcConnectionBox(from: connectionRaw),
          !connection.closed else {
        return kk_box_bool(0)
    }
    guard let db = try? connection.requireDB() else {
        return kk_box_bool(0)
    }
    var stmt: OpaquePointer?
    let rc = sqlite3_prepare_v2(db, "SELECT 1", -1, &stmt, nil)
    defer { sqlite3_finalize(stmt) }
    return kk_box_bool(rc == SQLITE_OK ? 1 : 0)
}

@_cdecl("kk_jdbc_connection_isReadOnly")
public func kk_jdbc_connection_isReadOnly(_ connectionRaw: Int) -> Int {
    // KSwiftK SQLite-backed connections are read-write by design.
    guard jdbcConnectionBox(from: connectionRaw) != nil else {
        return kk_box_bool(0)
    }
    return kk_box_bool(0)
}

@_cdecl("kk_jdbc_connection_getAutoCommit")
public func kk_jdbc_connection_getAutoCommit(_ connectionRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let connection = jdbcConnectionBox(from: connectionRaw) else {
        outThrown?.pointee = jdbcErrorThrowable(RuntimeJDBCError.invalidHandle("connection"))
        return kk_box_bool(1)
    }
    return kk_box_bool(connection.autoCommit ? 1 : 0)
}

@_cdecl("kk_jdbc_connection_setAutoCommit")
public func kk_jdbc_connection_setAutoCommit(_ connectionRaw: Int, _ valueRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    do {
        guard let connection = jdbcConnectionBox(from: connectionRaw) else {
            throw RuntimeJDBCError.invalidHandle("connection")
        }
        try connection.setAutoCommit(valueRaw != 0)
    } catch {
        outThrown?.pointee = jdbcErrorThrowable(error)
    }
    return 0
}

@_cdecl("kk_jdbc_connection_getTransactionIsolation")
public func kk_jdbc_connection_getTransactionIsolation(_ connectionRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let connection = jdbcConnectionBox(from: connectionRaw) else {
        outThrown?.pointee = jdbcErrorThrowable(RuntimeJDBCError.invalidHandle("connection"))
        return 2 // TRANSACTION_READ_COMMITTED default
    }
    return connection.transactionIsolation
}

@_cdecl("kk_jdbc_connection_setTransactionIsolation")
public func kk_jdbc_connection_setTransactionIsolation(_ connectionRaw: Int, _ levelRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    do {
        guard let connection = jdbcConnectionBox(from: connectionRaw) else {
            throw RuntimeJDBCError.invalidHandle("connection")
        }
        guard !connection.closed else {
            throw RuntimeJDBCError.connectionClosed
        }
        let validLevels = [1, 2, 4, 8]
        guard validLevels.contains(levelRaw) else {
            throw RuntimeJDBCError.sqlite("Unsupported transaction isolation level: \(levelRaw)")
        }
        connection.transactionIsolation = levelRaw
    } catch {
        outThrown?.pointee = jdbcErrorThrowable(error)
    }
    return 0
}

@_cdecl("kk_jdbc_connection_commit")
public func kk_jdbc_connection_commit(_ connectionRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    do {
        guard let connection = jdbcConnectionBox(from: connectionRaw) else {
            throw RuntimeJDBCError.invalidHandle("connection")
        }
        try connection.commit()
    } catch {
        outThrown?.pointee = jdbcErrorThrowable(error)
    }
    return 0
}

@_cdecl("kk_jdbc_connection_rollback")
public func kk_jdbc_connection_rollback(_ connectionRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    do {
        guard let connection = jdbcConnectionBox(from: connectionRaw) else {
            throw RuntimeJDBCError.invalidHandle("connection")
        }
        try connection.rollback()
    } catch {
        outThrown?.pointee = jdbcErrorThrowable(error)
    }
    return 0
}

@_cdecl("kk_jdbc_connection_setSavepoint")
public func kk_jdbc_connection_setSavepoint(_ connectionRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    do {
        guard let connection = jdbcConnectionBox(from: connectionRaw) else {
            throw RuntimeJDBCError.invalidHandle("connection")
        }
        let savepoint = try connection.createSavepoint(name: nil)
        return registerRuntimeObject(savepoint)
    } catch {
        outThrown?.pointee = jdbcErrorThrowable(error)
        return 0
    }
}

@_cdecl("kk_jdbc_connection_setSavepointNamed")
public func kk_jdbc_connection_setSavepointNamed(_ connectionRaw: Int, _ nameRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    do {
        guard let connection = jdbcConnectionBox(from: connectionRaw) else {
            throw RuntimeJDBCError.invalidHandle("connection")
        }
        let name = try jdbcExtractString(nameRaw)
        let savepoint = try connection.createSavepoint(name: name)
        return registerRuntimeObject(savepoint)
    } catch {
        outThrown?.pointee = jdbcErrorThrowable(error)
        return 0
    }
}

@_cdecl("kk_jdbc_connection_releaseSavepoint")
public func kk_jdbc_connection_releaseSavepoint(_ connectionRaw: Int, _ savepointRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    do {
        guard let connection = jdbcConnectionBox(from: connectionRaw) else {
            throw RuntimeJDBCError.invalidHandle("connection")
        }
        guard let savepoint = jdbcSavepointBox(from: savepointRaw) else {
            throw RuntimeJDBCError.invalidHandle("savepoint")
        }
        try connection.releaseSavepoint(savepoint)
    } catch {
        outThrown?.pointee = jdbcErrorThrowable(error)
    }
    return 0
}

@_cdecl("kk_jdbc_connection_rollback_savepoint")
public func kk_jdbc_connection_rollback_savepoint(_ connectionRaw: Int, _ savepointRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    do {
        guard let connection = jdbcConnectionBox(from: connectionRaw) else {
            throw RuntimeJDBCError.invalidHandle("connection")
        }
        guard let savepoint = jdbcSavepointBox(from: savepointRaw) else {
            throw RuntimeJDBCError.invalidHandle("savepoint")
        }
        try connection.rollback(to: savepoint)
    } catch {
        outThrown?.pointee = jdbcErrorThrowable(error)
    }
    return 0
}

// MARK: - Savepoint helpers

@_cdecl("kk_jdbc_savepoint_getSavepointId")
public func kk_jdbc_savepoint_getSavepointId(_ savepointRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    do {
        guard let savepoint = jdbcSavepointBox(from: savepointRaw) else {
            throw RuntimeJDBCError.invalidHandle("savepoint")
        }
        guard savepoint.name == nil else {
            throw RuntimeJDBCError.sqlite("Named savepoints do not expose an integer identifier")
        }
        return savepoint.identifier
    } catch {
        outThrown?.pointee = jdbcErrorThrowable(error)
        return 0
    }
}

@_cdecl("kk_jdbc_savepoint_getSavepointName")
public func kk_jdbc_savepoint_getSavepointName(_ savepointRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    do {
        guard let savepoint = jdbcSavepointBox(from: savepointRaw) else {
            throw RuntimeJDBCError.invalidHandle("savepoint")
        }
        guard let name = savepoint.name else {
            throw RuntimeJDBCError.sqlite("Unnamed savepoints do not expose a name")
        }
        return jdbcStringRaw(name)
    } catch {
        outThrown?.pointee = jdbcErrorThrowable(error)
        return 0
    }
}

// MARK: - Statement helpers

/// Execute an arbitrary SQL string; returns `true` if result is a `ResultSet`.
@_cdecl("kk_jdbc_statement_execute")
public func kk_jdbc_statement_execute(_ statementRaw: Int, _ sqlRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    do {
        guard let statement = jdbcStatementBox(from: statementRaw) else {
            throw RuntimeJDBCError.invalidHandle("statement")
        }
        let connection = try statement.requireConnection()
        let db = try connection.requireDB()
        let sql = try jdbcExtractString(sqlRaw)

        var stmt: OpaquePointer?
        let rc = sqlite3_prepare_v2(db, sql, -1, &stmt, nil)
        guard rc == SQLITE_OK, let prepared = stmt else {
            if let s = stmt { sqlite3_finalize(s) }
            throw RuntimeJDBCError.sqlite(jdbcLocalSQLiteMessage(from: db))
        }
        let stepRc = sqlite3_step(prepared)
        let hasResultSet = sqlite3_column_count(prepared) > 0
        sqlite3_finalize(prepared)
        guard stepRc == SQLITE_ROW || stepRc == SQLITE_DONE else {
            throw RuntimeJDBCError.sqlite(jdbcLocalSQLiteMessage(from: db))
        }
        return kk_box_bool(hasResultSet ? 1 : 0)
    } catch {
        outThrown?.pointee = jdbcErrorThrowable(error)
        return kk_box_bool(0)
    }
}

@_cdecl("kk_jdbc_statement_isClosed")
public func kk_jdbc_statement_isClosed(_ statementRaw: Int) -> Int {
    guard let statement = jdbcStatementBox(from: statementRaw) else {
        return kk_box_bool(1)
    }
    return kk_box_bool(statement.closed ? 1 : 0)
}

@_cdecl("kk_jdbc_statement_getUpdateCount")
public func kk_jdbc_statement_getUpdateCount(_ statementRaw: Int) -> Int {
    guard let statement = jdbcStatementBox(from: statementRaw),
          !statement.closed,
          let db = try? statement.requireConnection().requireDB() else {
        return -1
    }
    return Int(sqlite3_changes(db))
}

// MARK: - PreparedStatement helpers

/// Execute the PreparedStatement; returns `true` if result is a `ResultSet`.
@_cdecl("kk_jdbc_prepared_statement_execute")
public func kk_jdbc_prepared_statement_execute(_ preparedStatementRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    do {
        guard let ps = jdbcPreparedStatementBox(from: preparedStatementRaw) else {
            throw RuntimeJDBCError.invalidHandle("prepared statement")
        }
        let stmt = try ps.requireStatement()
        let hasResultSet = sqlite3_column_count(stmt) > 0
        sqlite3_reset(stmt)
        let stepRc = sqlite3_step(stmt)
        guard stepRc == SQLITE_ROW || stepRc == SQLITE_DONE else {
            let db = try ps.connection.requireDB()
            throw RuntimeJDBCError.sqlite(jdbcLocalSQLiteMessage(from: db))
        }
        sqlite3_reset(stmt)
        return kk_box_bool(hasResultSet ? 1 : 0)
    } catch {
        outThrown?.pointee = jdbcErrorThrowable(error)
        return kk_box_bool(0)
    }
}

@_cdecl("kk_jdbc_prepared_statement_isClosed")
public func kk_jdbc_prepared_statement_isClosed(_ preparedStatementRaw: Int) -> Int {
    guard let ps = jdbcPreparedStatementBox(from: preparedStatementRaw) else {
        return kk_box_bool(1)
    }
    return kk_box_bool(ps.closed ? 1 : 0)
}

// MARK: - ResultSet helpers

@_cdecl("kk_jdbc_result_set_isClosed")
public func kk_jdbc_result_set_isClosed(_ resultSetRaw: Int) -> Int {
    guard let rs = jdbcResultSetBox(from: resultSetRaw) else {
        return kk_box_bool(1)
    }
    return kk_box_bool(rs.closed ? 1 : 0)
}

/// Returns the current row number (1-based); 0 if before the first row.
@_cdecl("kk_jdbc_result_set_getRow")
public func kk_jdbc_result_set_getRow(_ resultSetRaw: Int) -> Int {
    guard let rs = jdbcResultSetBox(from: resultSetRaw) else {
        return 0
    }
    return rs.currentRow
}

// MARK: - Private helpers

private func jdbcSavepointBox(from raw: Int) -> RuntimeJDBCSavepointBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeJDBCSavepointBox.self)
}

private func jdbcLocalSQLiteMessage(from db: OpaquePointer?) -> String {
    if let db, let cString = sqlite3_errmsg(db) {
        return String(cString: cString)
    }
    return "unknown sqlite error"
}
