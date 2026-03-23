import java.io.File

fun main() {
    val f = File("/tmp/kswiftk_foreachline_" + System.currentTimeMillis() + ".txt")
    try {
        f.writeText("alpha\nbeta\ngamma")
        f.forEachLine { line -> println(line) }
        println("done")
    } finally {
        f.delete()
    }
}
