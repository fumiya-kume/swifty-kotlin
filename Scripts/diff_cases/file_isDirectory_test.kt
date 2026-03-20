import java.io.File

fun main() {
    // STDLIB-321 completion condition test
    val result = File("/tmp").isDirectory
    println(result)  // should be true
    
    // Test other File properties
    val f = File("/tmp/test.txt")
    println(f.name)     // "test.txt"
    println(f.path)     // "/tmp/test.txt"
    println(f.exists()) // false (file doesn't exist)
    println(f.isFile)    // false
    println(f.isDirectory) // false
}
