import java.io.File

fun main() {
    val f = File("/tmp/kswiftk_readtext_" + System.currentTimeMillis() + ".txt")
    try {
        f.writeText("hello\nworld")
        val content = f.readText()
        println(content)
        println(content.length)

        // overwrite
        f.writeText("replaced")
        println(f.readText())

        // append via readText + writeText
        f.writeText(f.readText() + "_tail")
        println(f.readText())
    } finally {
        f.delete()
    }
}
