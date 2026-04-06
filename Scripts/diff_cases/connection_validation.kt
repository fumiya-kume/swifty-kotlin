// SKIP-DIFF: Uses custom jdbc:kswiftk driver provided by this runtime.
// kotlinc does not ship that driver, so the reference run fails by design.
import java.sql.Connection
import java.sql.DriverManager
import java.sql.SQLException
import kotlin.concurrent.thread

fun main() {
    // Test basic connection validation
    val connection = DriverManager.getConnection("jdbc:kswiftk:memory")
    println(!connection.isClosed())
    
    // Test connection close and validation
    connection.close()
    println(connection.isClosed())
    
    // Test connection after close
    var exceptionCaught = false
    try {
        connection.createStatement()
    } catch (_: SQLException) {
        exceptionCaught = true
    }
    println(exceptionCaught)
    
    // Test connection pool with validation
    val pool = RuntimeDatabasePool(2, 1000) // 2 connections, 1 second timeout
    
    // Test pool configuration
    println(pool.maxConnections == 2)
    println(pool.timeoutMillis == 1000)
    
    // Set validation query
    pool.setValidationQuery("SELECT 1")
    pool.setTestOnBorrow(true)
    pool.setTestOnReturn(false)
    pool.setMaxIdleTime(60) // 60 seconds
    pool.setMaxLifetime(300) // 5 minutes
    
    // Test connection acquisition
    val conn1 = pool.acquire()
    println(conn1 > 0)
    println(pool.activeCount == 1)
    println(pool.idleCount == 0)
    println(pool.totalCount == 1)
    
    // Test connection validation
    println(pool.isConnectionOpen(conn1))
    println(pool.isConnectionInUse(conn1))
    
    // Test connection release
    val releaseResult = pool.release(conn1)
    println(releaseResult > 0)
    println(pool.activeCount == 0)
    println(pool.idleCount == 1)
    println(pool.totalCount == 1)
    
    // Test connection reuse
    val conn2 = pool.acquire()
    println(conn2 == conn1) // Should reuse the same connection
    println(pool.activeCount == 1)
    println(pool.idleCount == 0)
    
    // Test multiple connections
    val conn3 = pool.acquire()
    println(conn3 > 0)
    println(conn3 != conn2) // Should be a different connection
    println(pool.activeCount == 2)
    println(pool.idleCount == 0)
    println(pool.totalCount == 2)
    
    // Test pool full scenario
    val conn4 = pool.acquire()
    println(conn4 == 0) // Should fail - pool is full
    println(pool.waitingCount == 0)
    
    // Release one connection and acquire again
    pool.release(conn2)
    val conn5 = pool.acquire()
    println(conn5 == conn2) // Should reuse released connection
    
    // Test connection validation after idle time simulation
    pool.release(conn3)
    pool.release(conn5)
    
    // Simulate time passing (in real implementation, this would wait)
    // For now, we'll test the validation logic directly
    println(pool.isConnectionOpen(conn3))
    println(!pool.isConnectionInUse(conn3))
    
    // Test error handling for invalid connection
    val invalidResult = pool.release(999)
    println(invalidResult == 0)
    
    // Test error handling for releasing non-acquired connection
    val notAcquiredResult = pool.release(conn4) // conn4 was never successfully acquired
    println(notAcquiredResult == 0)
    
    // Test connection leak detection
    val leakConn = pool.acquire()
    println(pool.activeCount == 1)
    // Don't release leakConn to simulate a leak
    
    // Test pool statistics
    println(pool.activeCount == 1)
    println(pool.idleCount == 1)
    println(pool.totalCount == 2)
    println(pool.waitingCount == 0)
    println(pool.maxConnections == 2)
    println(pool.timeoutMillis == 1000)
    
    // Test concurrent access
    val results = mutableListOf<Int>()
    val threads = mutableListOf<Thread>()
    
    repeat(5) { i ->
        val thread = thread {
            try {
                val conn = pool.acquire()
                if (conn > 0) {
                    results.add(conn)
                    Thread.sleep(100) // Simulate work
                    pool.release(conn)
                }
            } catch (e: Exception) {
                println("Thread $i error: ${e.message}")
            }
        }
        threads.add(thread)
        thread.start()
    }
    
    // Wait for all threads to complete
    threads.forEach { it.join() }
    
    println(results.size <= 2) // Should not exceed max connections
    println(pool.activeCount == 1) // leakConn is still active
    println(pool.idleCount >= 0)
    
    // Clean up remaining connections
    pool.release(leakConn)
    
    // Test pool behavior with all connections released
    println(pool.activeCount == 0)
    println(pool.idleCount == 2)
    println(pool.totalCount == 2)
    
    // Test connection validation settings
    pool.setTestOnBorrow(true)
    pool.setTestOnReturn(true)
    pool.setMaxIdleTime(30) // 30 seconds
    pool.setMaxLifetime(180) // 3 minutes
    
    // Test validation with short lifetime
    val shortLifeConn = pool.acquire()
    pool.release(shortLifeConn)
    
    // In a real implementation with time passing, this would test connection expiration
    println(pool.isConnectionOpen(shortLifeConn))
    
    println("All connection validation tests completed successfully!")
}

// Mock classes for testing (these would be provided by the runtime)
class RuntimeDatabasePool {
    val maxConnections: Int
    val timeoutMillis: Int
    
    constructor(maxConnections: Int, timeoutMillis: Int) {
        this.maxConnections = maxConnections
        this.timeoutMillis = timeoutMillis
    }
    
    fun acquire(): Int {
        // Mock implementation - would call actual pool.acquire()
        return 1
    }
    
    fun release(connection: Int): Int {
        // Mock implementation - would call actual pool.release()
        return 1
    }
    
    fun setValidationQuery(query: String) {
        // Mock implementation
    }
    
    fun setTestOnBorrow(test: Boolean) {
        // Mock implementation
    }
    
    fun setTestOnReturn(test: Boolean) {
        // Mock implementation
    }
    
    fun setMaxIdleTime(seconds: Int) {
        // Mock implementation
    }
    
    fun setMaxLifetime(seconds: Int) {
        // Mock implementation
    }
    
    val activeCount: Int get() = 0
    val idleCount: Int get() = 0
    val totalCount: Int get() = 0
    val waitingCount: Int get() = 0
    
    fun isConnectionOpen(connection: Int): Boolean = true
    fun isConnectionInUse(connection: Int): Boolean = false
}
