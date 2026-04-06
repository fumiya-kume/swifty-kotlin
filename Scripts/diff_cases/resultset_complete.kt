// SKIP-DIFF: Uses the custom jdbc:kswiftk driver provided by this runtime.
// kotlinc does not ship that driver, so the reference run fails by design.
import java.sql.Connection
import java.sql.DriverManager
import java.sql.ResultSet
import java.sql.ResultSetMetaData
import java.sql.Statement

fun main() {
    val connection = DriverManager.getConnection("jdbc:kswiftk:memory")
    
    // Create test table with various data types
    val statement = connection.createStatement()
    statement.executeUpdate("""
        create table test_types (
            id integer primary key,
            name text,
            age integer,
            score real,
            active integer,
            created_at text
        )
    """)
    
    // Insert test data including NULL values
    val insert = connection.prepareStatement("insert into test_types values (?, ?, ?, ?, ?, ?)")
    insert.setInt(1, 1)
    insert.setString(2, "Alice")
    insert.setInt(3, 25)
    insert.setDouble(4, 95.5)
    insert.setBoolean(5, true)
    insert.setString(6, "2023-01-01")
    insert.executeUpdate()
    
    // Insert row with NULL values
    insert.setNull(1, 4) // INTEGER
    insert.setNull(2, 12) // VARCHAR
    insert.setNull(3, 4) // INTEGER
    insert.setNull(4, 8) // DOUBLE
    insert.setNull(5, 16) // BOOLEAN
    insert.setNull(6, 12) // VARCHAR
    insert.executeUpdate()
    
    // Test ResultSet basic navigation
    val resultSet = statement.executeQuery("select * from test_types order by id")
    println(resultSet.next()) // true
    println(resultSet.next()) // true  
    println(resultSet.next()) // false
    
    // Reset cursor to beginning
    resultSet.beforeFirst()
    println(resultSet.next()) // true
    
    // Test all getXXX methods
    val id = resultSet.getInt(1)
    val name = resultSet.getString(2)
    val age = resultSet.getInt(3)
    val score = resultSet.getDouble(4)
    val active = resultSet.getBoolean(5)
    val createdAt = resultSet.getString(6)
    
    println(id == 1)
    println(name == "Alice")
    println(age == 25)
    println(score == 95.5)
    println(active)
    println(createdAt == "2023-01-01")
    
    // Test wasNull() with non-null values
    println(resultSet.wasNull()) // false
    
    // Move to second row with NULL values
    resultSet.next()
    
    // Test wasNull() with NULL values
    val nullId = resultSet.getInt("id")
    println(resultSet.wasNull()) // true
    
    val nullName = resultSet.getString("name")
    println(resultSet.wasNull()) // true
    
    val nullAge = resultSet.getInt("age")
    println(resultSet.wasNull()) // true
    
    val nullScore = resultSet.getDouble("score")
    println(resultSet.wasNull()) // true
    
    val nullActive = resultSet.getBoolean("active")
    println(resultSet.wasNull()) // true
    
    val nullCreatedAt = resultSet.getString("created_at")
    println(resultSet.wasNull()) // true
    
    // Test ResultSetMetaData
    val metaData = resultSet.getMetaData()
    val columnCount = metaData.getColumnCount()
    println(columnCount == 6)
    
    // Test column names and labels
    println(metaData.getColumnName(1) == "id")
    println(metaData.getColumnLabel(2) == "name")
    println(metaData.getColumnName(3) == "age")
    println(metaData.getColumnLabel(4) == "score")
    println(metaData.getColumnName(5) == "active")
    println(metaData.getColumnLabel(6) == "created_at")
    
    // Test column types
    println(metaData.getColumnType(1) == 4) // INTEGER
    println(metaData.getColumnType(2) == 12) // TEXT
    println(metaData.getColumnType(3) == 4) // INTEGER
    println(metaData.getColumnType(4) == 8) // FLOAT/DOUBLE
    println(metaData.getColumnType(5) == 4) // INTEGER (boolean stored as integer)
    println(metaData.getColumnType(6) == 12) // TEXT
    
    // Test column type names
    println(metaData.getColumnTypeName(1) == "INTEGER")
    println(metaData.getColumnTypeName(2) == "TEXT")
    println(metaData.getColumnTypeName(3) == "INTEGER")
    println(metaData.getColumnTypeName(4) == "FLOAT")
    println(metaData.getColumnTypeName(5) == "INTEGER")
    println(metaData.getColumnTypeName(6) == "TEXT")
    
    // Test column properties
    println(metaData.isNullable(1) == 1) // columnNullable
    println(metaData.isNullable(2) == 1) // columnNullable
    println(!metaData.isAutoIncrement(1)) // false for our implementation
    println(metaData.isReadOnly(1)) // true for our implementation
    println(metaData.isSearchable(1)) // true for our implementation
    
    // Test different numeric types
    resultSet.beforeFirst()
    resultSet.next()
    
    val intId = resultSet.getInt("id")
    val longId = resultSet.getLong("id")
    val floatScore = resultSet.getFloat("score")
    val doubleScore = resultSet.getDouble("score")
    
    println(intId == 1)
    println(longId == 1L)
    println(floatScore == 95.5f)
    println(doubleScore == 95.5)
    
    // Test boolean conversion
    val boolActive = resultSet.getBoolean("active")
    val intActive = resultSet.getInt("active")
    println(boolActive)
    println(intActive == 1)
    
    // Test error handling for invalid column indices
    var exceptionCaught = false
    try {
        resultSet.getInt(999)
    } catch (_: Throwable) {
        exceptionCaught = true
    }
    println(exceptionCaught)
    
    // Test error handling for invalid column names
    exceptionCaught = false
    try {
        resultSet.getString("nonexistent_column")
    } catch (_: Throwable) {
        exceptionCaught = true
    }
    println(exceptionCaught)
    
    // Clean up
    resultSet.close()
    statement.close()
    connection.close()
    
    // Test closed ResultSet operations
    exceptionCaught = false
    try {
        resultSet.getInt(1)
    } catch (_: Throwable) {
        exceptionCaught = true
    }
    println(exceptionCaught)
    
    println("All ResultSet tests completed successfully!")
}
