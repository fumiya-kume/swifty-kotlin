import Foundation

// MARK: - Transaction Management Runtime (STDLIB-DB-141)

/// Isolation level constants matching java.sql.Connection constants.
enum TransactionIsolationLevel: Int {
    case readUncommitted = 1
    case readCommitted = 2
    case repeatableRead = 4
    case serializable = 8
}

/// Represents a database transaction scope backed by a JDBC connection box.
///
/// This class wraps a `RuntimeJDBCConnectionBox` and provides
/// structured begin/commit/rollback semantics matching Kotlin's
/// transaction management API surface.
final class RuntimeTransactionBox {
    private let connection: RuntimeJDBCConnectionBox

    var isActive: Bool {
        !connection.autoCommit && !connection.closed
    }

    init(connection: RuntimeJDBCConnectionBox) {
        self.connection = connection
    }

    func begin() throws {
        try connection.setAutoCommit(false)
    }

    func commit() throws {
        try connection.commit()
    }

    func rollback() throws {
        try connection.rollback()
    }

    func setSavepoint(name: String? = nil) throws -> RuntimeJDBCSavepointBox {
        try connection.createSavepoint(name: name)
    }

    func rollbackToSavepoint(_ savepoint: RuntimeJDBCSavepointBox) throws {
        try connection.rollback(to: savepoint)
    }

    func releaseSavepoint(_ savepoint: RuntimeJDBCSavepointBox) throws {
        try connection.releaseSavepoint(savepoint)
    }

    func setIsolationLevel(_ level: TransactionIsolationLevel) throws {
        guard !connection.closed else {
            throw RuntimeTransactionError.connectionClosed
        }
        connection.transactionIsolation = level.rawValue
    }

    func isolationLevel() throws -> TransactionIsolationLevel {
        guard !connection.closed else {
            throw RuntimeTransactionError.connectionClosed
        }
        guard let level = TransactionIsolationLevel(rawValue: connection.transactionIsolation) else {
            throw RuntimeTransactionError.unsupportedIsolationLevel(connection.transactionIsolation)
        }
        return level
    }
}

enum RuntimeTransactionError: Error {
    case connectionClosed
    case notInTransaction
    case unsupportedIsolationLevel(Int)
}

/// Executes `body` within a transaction on the given connection handle.
///
/// If `body` throws, the transaction is rolled back. Otherwise it is committed.
/// The connection's autoCommit state is restored after the block.
private func withTransactionImpl(
    connectionRaw: Int,
    outThrown: UnsafeMutablePointer<Int>?,
    body: () throws -> Void
) {
    outThrown?.pointee = 0
    guard let ptr = UnsafeMutableRawPointer(bitPattern: connectionRaw),
          let connection = tryCast(ptr, to: RuntimeJDBCConnectionBox.self)
    else {
        outThrown?.pointee = runtimeAllocateThrowable(message: "withTransaction: invalid Connection handle")
        return
    }
    let previousAutoCommit = connection.autoCommit
    do {
        try connection.setAutoCommit(false)
        try body()
        try connection.commit()
        if previousAutoCommit {
            try connection.setAutoCommit(true)
        }
    } catch {
        do {
            try connection.rollback()
        } catch {
            // Best-effort rollback; swallow secondary failure
        }
        if previousAutoCommit {
            try? connection.setAutoCommit(true)
        }
        outThrown?.pointee = runtimeAllocateThrowable(message: "\(error)")
    }
}

// MARK: - Exported C entry points

@_cdecl("kk_transaction_begin")
public func kk_transaction_begin(_ connectionRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    do {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: connectionRaw),
              let connection = tryCast(ptr, to: RuntimeJDBCConnectionBox.self)
        else {
            throw RuntimeTransactionError.connectionClosed
        }
        let txn = RuntimeTransactionBox(connection: connection)
        try txn.begin()
        return registerRuntimeObject(txn)
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "kk_transaction_begin: \(error)")
        return 0
    }
}

@_cdecl("kk_transaction_commit")
public func kk_transaction_commit(_ txnRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    do {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: txnRaw),
              let txn = tryCast(ptr, to: RuntimeTransactionBox.self)
        else {
            throw RuntimeTransactionError.notInTransaction
        }
        try txn.commit()
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "kk_transaction_commit: \(error)")
    }
    return 0
}

@_cdecl("kk_transaction_rollback")
public func kk_transaction_rollback(_ txnRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    do {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: txnRaw),
              let txn = tryCast(ptr, to: RuntimeTransactionBox.self)
        else {
            throw RuntimeTransactionError.notInTransaction
        }
        try txn.rollback()
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "kk_transaction_rollback: \(error)")
    }
    return 0
}

@_cdecl("kk_transaction_setSavepoint")
public func kk_transaction_setSavepoint(_ txnRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    do {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: txnRaw),
              let txn = tryCast(ptr, to: RuntimeTransactionBox.self)
        else {
            throw RuntimeTransactionError.notInTransaction
        }
        let savepoint = try txn.setSavepoint()
        return registerRuntimeObject(savepoint)
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "kk_transaction_setSavepoint: \(error)")
        return 0
    }
}

@_cdecl("kk_transaction_rollbackToSavepoint")
public func kk_transaction_rollbackToSavepoint(_ txnRaw: Int, _ savepointRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    do {
        guard let txnPtr = UnsafeMutableRawPointer(bitPattern: txnRaw),
              let txn = tryCast(txnPtr, to: RuntimeTransactionBox.self)
        else {
            throw RuntimeTransactionError.notInTransaction
        }
        guard let spPtr = UnsafeMutableRawPointer(bitPattern: savepointRaw),
              let savepoint = tryCast(spPtr, to: RuntimeJDBCSavepointBox.self)
        else {
            throw RuntimeTransactionError.notInTransaction
        }
        try txn.rollbackToSavepoint(savepoint)
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "kk_transaction_rollbackToSavepoint: \(error)")
    }
    return 0
}

@_cdecl("kk_transaction_releaseSavepoint")
public func kk_transaction_releaseSavepoint(_ txnRaw: Int, _ savepointRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    do {
        guard let txnPtr = UnsafeMutableRawPointer(bitPattern: txnRaw),
              let txn = tryCast(txnPtr, to: RuntimeTransactionBox.self)
        else {
            throw RuntimeTransactionError.notInTransaction
        }
        guard let spPtr = UnsafeMutableRawPointer(bitPattern: savepointRaw),
              let savepoint = tryCast(spPtr, to: RuntimeJDBCSavepointBox.self)
        else {
            throw RuntimeTransactionError.notInTransaction
        }
        try txn.releaseSavepoint(savepoint)
    } catch {
        outThrown?.pointee = runtimeAllocateThrowable(message: "kk_transaction_releaseSavepoint: \(error)")
    }
    return 0
}

@_cdecl("kk_transaction_isActive")
public func kk_transaction_isActive(_ txnRaw: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: txnRaw),
          let txn = tryCast(ptr, to: RuntimeTransactionBox.self)
    else {
        return kk_box_bool(0)
    }
    return kk_box_bool(txn.isActive ? 1 : 0)
}
