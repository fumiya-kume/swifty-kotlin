// DIFF_LINE_PATTERN: kswiftk_exists_[0-9]+
import java.io.File

fun main() {
    val base = "/tmp/kswiftk_exists_" + System.currentTimeMillis()
    val dir = File(base)
    val file = File(base + "/test.txt")
    val missing = File(base + "/nonexistent")
    try {
        dir.mkdirs()
        file.writeText("data")

        println(dir.exists())       // true
        println(dir.isDirectory)    // true
        println(dir.isFile)         // false

        println(file.exists())     // true
        println(file.isFile)       // true
        println(file.isDirectory)  // false

        println(missing.exists())     // false
        println(missing.isFile)       // false
        println(missing.isDirectory)  // false

        // STDLIB-321: name and path properties
        println(dir.name)             // "kswiftk_exists_<timestamp>"
        println(dir.path)             // "/tmp/kswiftk_exists_<timestamp>"
        println(file.name)            // "test.txt"
        println(file.path)            // "/tmp/kswiftk_exists_<timestamp>/test.txt"
        
        // Verify name and path work correctly
        println(file.name == "test.txt")     // true
        println(dir.name.startsWith("kswiftk_exists_"))  // true
        println(file.path.endsWith("/test.txt"))  // true
    } finally {
        file.delete()
        dir.delete()
    }
}
