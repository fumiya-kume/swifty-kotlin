import java.io.File

fun main() {
    // Test File.mkdirs()
    val testDir = File("/tmp/test_mkdirs")
    val mkdirsResult = testDir.mkdirs()
    println("mkdirs result: $mkdirsResult")
    
    // Test File.exists()
    val existsResult = testDir.exists()
    println("exists result: $existsResult")
    
    // Test File.isDirectory()
    val isDirResult = testDir.isDirectory()
    println("isDirectory result: $isDirResult")
    
    // Test File.listFiles()
    val files = testDir.listFiles()
    println("listFiles result: $files")
    
    // Test File.walk()
    val walkResult = testDir.walk()
    println("walk result: $walkResult")
    
    // Test File.delete()
    val deleteResult = testDir.delete()
    println("delete result: $deleteResult")
}
