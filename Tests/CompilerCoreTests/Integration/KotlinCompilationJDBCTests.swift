@testable import CompilerCore
import XCTest

final class KotlinCompilationJDBCTests: XCTestCase {
    func testCompile_jdbc_basicFlow() throws {
        try assertKotlinCompilesToKIR("""
        import java.sql.DriverManager

        fun main() {
            val connection = DriverManager.getConnection("jdbc:sqlite::memory:")
            connection.use { conn ->
                val statement = conn.createStatement()
                statement.executeUpdate("create table users(id integer, name text)")

                val insert = conn.prepareStatement("insert into users(id, name) values (?, ?)")
                insert.setInt(1, 1)
                insert.setString(2, "Ada")
                insert.executeUpdate()
                insert.close()

                val rows = statement.executeQuery("select id, name from users")
                while (rows.next()) {
                    val id = rows.getInt(1)
                    val name = rows.getString("name")
                    println(name + id)
                }
                rows.close()
                statement.close()
            }
        }
        """)
    }
}
