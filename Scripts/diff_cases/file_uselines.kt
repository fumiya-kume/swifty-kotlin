import java.io.File

fun main() {
    val f = File("/tmp/kswiftk_uselines_" + System.currentTimeMillis() + ".txt")
    try {
        f.writeText("one\ntwo\nthree")
        val result = f.useLines { lines ->
            lines.count()
        }
        println("count: $result")
    } finally {
        f.delete()
    }
}
