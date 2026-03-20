import java.io.File

fun main() {
    val f = File("/tmp/golden_test.txt")
    println(f.name)
    println(f.path)
    println(f.exists())
    println(f.isFile)
    println(f.isDirectory)
}
