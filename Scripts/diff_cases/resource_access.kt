import java.io.File

fun main() {
    val f = File("/tmp/kswiftk_resource_access_test.txt")
    try {
        f.writeText("hello\nworld\nfoo")

        // BufferedReader.use {} - auto-close on exit, returns non-null value
        val lines = f.bufferedReader().use { reader ->
            reader.readLines()
        }
        println("lines: $lines")

        // BufferedWriter.use {} - auto-close on exit
        f.bufferedWriter().use { writer ->
            writer.write("updated")
            writer.newLine()
            writer.write("content")
        }
        println("written: ${f.readText()}")
    } finally {
        f.delete()
    }
}
