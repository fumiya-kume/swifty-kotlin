import java.io.File

fun main() {
    val f = File("/tmp/kswiftk_bufferedreader_" + System.currentTimeMillis() + ".txt")
    try {
        f.writeText("line1\nline2\nline3")
        val reader = f.bufferedReader()
        val first = reader.readLine()
        println("first: $first")
        val remaining = reader.readLines()
        println("remaining: $remaining")
        reader.close()
    } finally {
        f.delete()
    }
}
