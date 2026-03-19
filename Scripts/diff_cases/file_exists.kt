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
    } finally {
        file.delete()
        dir.delete()
    }
}
