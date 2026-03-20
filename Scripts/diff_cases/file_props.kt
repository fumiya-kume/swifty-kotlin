import java.io.File

fun main() {
    val f = File("/tmp/test_props.txt")
    println(f.name)        // "test_props.txt"
    println(f.path)        // "/tmp/test_props.txt"
    println(f.exists())    // false
    println(f.isFile)      // false
    println(f.isDirectory) // false

    val d = File("/tmp")
    println(d.name)        // "tmp"
    println(d.path)        // "/tmp"
    println(d.exists())    // true
    println(d.isDirectory) // true
    println(d.isFile)      // false
}
