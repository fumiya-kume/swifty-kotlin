import java.io.File

fun main() {
    val f = File("test.txt")
    f.writeText("hello world")
    val content = f.readText()
    println(content)
    val lines = f.readLines()
    println(lines.size)
}
