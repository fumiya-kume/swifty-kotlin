// SKIP-DIFF: Uses custom jdbc:kswiftk driver provided by this runtime.
// kotlinc does not ship that driver, so the reference run fails by design.
import java.sql.Connection
import java.sql.DriverManager
import java.sql.PreparedStatement
import java.sql.ResultSet

fun main() {
    val connection = DriverManager.getConnection("jdbc:kswiftk:memory")
    
    // Create test table
    val statement = connection.createStatement()
    statement.executeUpdate("""
        create table test_prepared (
            id integer primary key,
            name text,
            age integer,
            score real,
            active integer,
            created_at text
        )
    """)
    
    // Test parameter count
    val insert = connection.prepareStatement("insert into test_prepared values (?, ?, ?, ?, ?, ?)")
    println(insert.getParameterCount() == 6)
    
    // Test all setXXX methods
    insert.setInt(1, 1)
    insert.setString(2, "Alice")
    insert.setInt(3, 25)
    insert.setDouble(4, 95.5)
    insert.setBoolean(5, true)
    insert.setString(6, "2023-01-01")
    
    val updateCount = insert.executeUpdate()
    println(updateCount == 1)
    
    // Test with different data types
    insert.setInt(1, 2)
    insert.setString(2, "Bob")
    insert.setLong(3, 30L.toInt())
    insert.setFloat(4, 88.5f)
    insert.setBoolean(5, false)
    insert.setString(6, "2023-02-01")
    
    insert.executeUpdate()
    
    // Test NULL values
    insert.setNull(1, 4) // INTEGER
    insert.setNull(2, 12) // VARCHAR
    insert.setNull(3, 4) // INTEGER
    insert.setNull(4, 8) // DOUBLE
    insert.setNull(5, 16) // BOOLEAN
    insert.setNull(6, 12) // VARCHAR
    
    insert.executeUpdate()
    
    // Test query with parameters
    val select = connection.prepareStatement("select * from test_prepared where id = ? and active = ?")
    select.setInt(1, 1)
    select.setBoolean(2, true)
    
    val resultSet = select.executeQuery()
    println(resultSet.next())
    println(resultSet.getInt("id") == 1)
    println(resultSet.getString("name") == "Alice")
    println(resultSet.getInt("age") == 25)
    println(resultSet.getDouble("score") == 95.5)
    println(resultSet.getBoolean("active"))
    println(resultSet.getString("created_at") == "2023-01-01")
    resultSet.close()
    
    // Test batch operations
    val batchInsert = connection.prepareStatement("insert into test_prepared values (?, ?, ?, ?, ?, ?)")
    
    // Add multiple batch commands
    batchInsert.setInt(1, 10)
    batchInsert.setString(2, "Batch1")
    batchInsert.setInt(3, 35)
    batchInsert.setDouble(4, 75.0)
    batchInsert.setBoolean(5, true)
    batchInsert.setString(6, "2023-03-01")
    batchInsert.addBatch()
    
    batchInsert.setInt(1, 11)
    batchInsert.setString(2, "Batch2")
    batchInsert.setInt(3, 40)
    batchInsert.setDouble(4, 80.0)
    batchInsert.setBoolean(5, false)
    batchInsert.setString(6, "2023-03-02")
    batchInsert.addBatch()
    
    batchInsert.setInt(1, 12)
    batchInsert.setString(2, "Batch3")
    batchInsert.setNull(3, 4)
    batchInsert.setNull(4, 8)
    batchInsert.setNull(5, 16)
    batchInsert.setString(6, "2023-03-03")
    batchInsert.addBatch()
    
    // Execute batch
    val batchResults = batchInsert.executeBatch()
    println(batchResults.size == 3)
    println(batchResults.all { it == 1 }) // All should return 1 (1 row affected)
    
    // Test clear batch
    batchInsert.clearBatch()
    batchInsert.setInt(1, 13)
    batchInsert.setString(2, "AfterClear")
    batchInsert.addBatch()
    
    val afterClearResults = batchInsert.executeBatch()
    println(afterClearResults.size == 1)
    
    // Test parameter metadata
    val paramCount = batchInsert.getParameterCount()
    println(paramCount == 6)
    
    // Test error handling for invalid parameter index
    var exceptionCaught = false
    try {
        insert.setInt(999, 999)
    } catch (_: Throwable) {
        exceptionCaught = true
    }
    println(exceptionCaught)
    
    // Test error handling for closed statement
    insert.close()
    exceptionCaught = false
    try {
        insert.setInt(1, 1)
    } catch (_: Throwable) {
        exceptionCaught = true
    }
    println(exceptionCaught)
    
    // Test query results after batch operations
    val countQuery = connection.prepareStatement("select count(*) as total from test_prepared")
    val countResult = countQuery.executeQuery()
    countResult.next()
    println(countResult.getInt("total") >= 8) // Should have at least 8 rows
    countResult.close()
    countQuery.close()
    
    // Test prepared statement with different parameter types
    val typeTest = connection.prepareStatement("select * from test_prepared where age > ? and score < ?")
    typeTest.setInt(1, 20)
    typeTest.setDouble(2, 90.0)
    
    val typeResult = typeTest.executeQuery()
    var foundRecords = 0
    while (typeResult.next()) {
        foundRecords++
        val age = typeResult.getInt("age")
        val score = typeResult.getDouble("score")
        println(age > 20 && score < 90.0)
    }
    println(foundRecords > 0)
    typeResult.close()
    typeTest.close()
    
    // Test boolean parameter with different values
    val boolTest = connection.prepareStatement("select * from test_prepared where active = ?")
    
    boolTest.setBoolean(1, true)
    val trueResult = boolTest.executeQuery()
    var trueCount = 0
    while (trueResult.next()) {
        trueCount++
        println(trueResult.getBoolean("active"))
    }
    trueResult.close()
    
    boolTest.setBoolean(1, false)
    val falseResult = boolTest.executeQuery()
    var falseCount = 0
    while (falseResult.next()) {
        falseCount++
        println(!falseResult.getBoolean("active"))
    }
    falseResult.close()
    
    println(trueCount > 0)
    println(falseCount > 0)
    boolTest.close()
    
    // Test long parameter
    val longTest = connection.prepareStatement("insert into test_prepared (id, name) values (?, ?)")
    longTest.setLong(1, 999999999L.toInt())
    longTest.setString(2, "LongTest")
    longTest.executeUpdate()
    longTest.close()
    
    // Verify long value
    val verifyLong = connection.prepareStatement("select id from test_prepared where name = ?")
    verifyLong.setString(1, "LongTest")
    val longResult = verifyLong.executeQuery()
    longResult.next()
    println(longResult.getLong("id") == 999999999L)
    longResult.close()
    verifyLong.close()
    
    // Clean up
    statement.close()
    connection.close()
    
    println("All PreparedStatement tests completed successfully!")
}
