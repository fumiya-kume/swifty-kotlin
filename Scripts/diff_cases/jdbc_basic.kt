// SKIP-DIFF
import java.sql.DriverManager
import java.sql.SQLException

fun main() {
    // Open an in-memory SQLite database via JDBC.
    val conn = DriverManager.getConnection("jdbc:sqlite::memory:")

    // Connection should be open.
    println(conn.isClosed)  // false

    // Create a table and insert rows using Statement.
    val stmt = conn.createStatement()
    println(stmt.isClosed)  // false

    stmt.executeUpdate("CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, score REAL)")
    stmt.executeUpdate("INSERT INTO users VALUES (1, 'Alice', 9.5)")
    stmt.executeUpdate("INSERT INTO users VALUES (2, 'Bob', 7.0)")
    stmt.executeUpdate("INSERT INTO users VALUES (3, 'Carol', 8.25)")

    // Query via Statement.executeQuery.
    val rs = stmt.executeQuery("SELECT id, name, score FROM users ORDER BY id")
    while (rs.next()) {
        val id = rs.getInt(1)
        val name = rs.getString(2)
        val score = rs.getDouble(3)
        println("$id $name $score")
    }
    rs.close()
    println(rs.isClosed)  // true

    stmt.close()
    println(stmt.isClosed)  // true

    // PreparedStatement with parameter binding.
    val ps = conn.prepareStatement("SELECT name FROM users WHERE score > ?")
    ps.setDouble(1, 8.0)
    val rs2 = ps.executeQuery()
    val names = mutableListOf<String>()
    while (rs2.next()) {
        names.add(rs2.getString(1))
    }
    rs2.close()
    ps.close()
    // Alice (9.5) and Carol (8.25) have score > 8.0
    println(names.sorted().joinToString(","))  // Alice,Carol

    // PreparedStatement — executeUpdate.
    val update = conn.prepareStatement("UPDATE users SET score = ? WHERE id = ?")
    update.setDouble(1, 10.0)
    update.setInt(2, 1)
    val affected = update.executeUpdate()
    println(affected)  // 1
    update.close()

    // Verify update took effect.
    val check = conn.createStatement()
    val rs3 = check.executeQuery("SELECT score FROM users WHERE id = 1")
    if (rs3.next()) {
        println(rs3.getDouble(1))  // 10.0
    }
    rs3.close()
    check.close()

    // SQLException is thrown for bad SQL.
    try {
        conn.createStatement().executeQuery("SELECT * FROM nonexistent_table")
        println("should not reach here")
    } catch (e: SQLException) {
        println("caught SQLException")  // caught SQLException
    }

    conn.close()
    println(conn.isClosed)  // true
}
