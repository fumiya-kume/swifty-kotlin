// SKIP-DIFF: Uses the custom jdbc:kswiftk driver provided by this runtime.
// kotlinc does not ship that driver, so the reference run fails by design.
import java.sql.Connection
import java.sql.DriverManager

fun main() {
    val connection = DriverManager.getConnection("jdbc:kswiftk:memory")

    println(connection.getAutoCommit())
    connection.setAutoCommit(false)
    println(connection.getAutoCommit())

    println(connection.getTransactionIsolation() == 2)
    connection.setTransactionIsolation(8)
    println(connection.getTransactionIsolation() == 8)
    connection.setTransactionIsolation(4)
    println(connection.getTransactionIsolation() == 4)

    val unnamed = connection.setSavepoint()
    println(unnamed.getSavepointId() > 0)

    val named = connection.setSavepoint("beforeCommit")
    println(named.getSavepointName() == "beforeCommit")

    connection.rollback(named)
    connection.releaseSavepoint(named)
    connection.commit()
    println(connection.getAutoCommit() == false)

    connection.setAutoCommit(false)
    val afterRollback = connection.setSavepoint("afterRollback")
    connection.rollback()

    var released = false
    try {
        connection.releaseSavepoint(afterRollback)
    } catch (_: Throwable) {
        released = true
    }
    println(released)

    connection.setAutoCommit(true)
    var commitFailed = false
    try {
        connection.commit()
    } catch (_: Throwable) {
        commitFailed = true
    }
    println(commitFailed)

    connection.close()
    println(connection.isClosed())
}
