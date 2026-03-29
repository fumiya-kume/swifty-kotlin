import java.io.File

fun main() {
    val f = File("/tmp/kswiftk_buffered_io_test.txt")
    try {
        // BufferedWriter: write, newLine, flush, close
        val writer = f.bufferedWriter()
        writer.write("Hello, BufferedWriter!")
        writer.newLine()
        writer.write("Second line")
        writer.flush()
        writer.close()

        // BufferedReader: readLine, read, ready, close
        val reader = f.bufferedReader()
        println("ready: ${reader.ready()}")
        val line1 = reader.readLine()
        println("line1: $line1")
        val line2 = reader.readLine()
        println("line2: $line2")
        val eof = reader.readLine()
        println("eof: $eof")
        reader.close()
    } finally {
        f.delete()
    }
}
