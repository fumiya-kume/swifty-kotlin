import java.io.File

fun main() {
    val f = File("/tmp/kswiftk_appendtext_" + System.currentTimeMillis() + ".txt")
    try {
        f.writeText("hello")
        f.appendText(" world")
        println(f.readText())

        // append to existing content
        f.appendText("!")
        println(f.readText())
    } finally {
        f.delete()
    }
}
