import java.io.File

fun main() {
    // Create nested directory structure
    val baseDir = File("/tmp/advanced_test")
    val subDir = File("/tmp/advanced_test/subdir")
    val nestedDir = File("/tmp/advanced_test/subdir/nested")
    
    // Test mkdirs on nested path
    val mkdirsResult = nestedDir.mkdirs()
    println("mkdirs nested: $mkdirsResult")
    
    // Test walk to traverse directory tree
    val walkedFiles = baseDir.walk()
    println("walk count: ${walkedFiles.toList().size}")
    
    // Test listFiles on specific directory
    val baseFiles = baseDir.listFiles()
    println("baseDir listFiles count: ${baseFiles?.toList()?.size}")
    
    val subFiles = subDir.listFiles()
    println("subDir listFiles count: ${subFiles?.toList()?.size}")
    
    // Test delete operations
    val deleteBaseResult = baseDir.delete()
    println("delete base (should be false due to contents): $deleteBaseResult")
    
    // Clean up manually
    File("/tmp/advanced_test/file1.txt").delete()
    File("/tmp/advanced_test/subdir/file2.txt").delete()
    subDir.delete()
    val finalDeleteResult = baseDir.delete()
    println("final delete result: $finalDeleteResult")
}
