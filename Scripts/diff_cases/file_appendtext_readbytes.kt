import java.io.File

fun main() {
    val f = File("/tmp/kswiftk_appendtext_readbytes_" + System.currentTimeMillis() + ".txt")
    try {
        // appendText creates the file if it doesn't exist
        f.appendText("hello")
        println(f.readText())

        // appendText appends to existing content
        f.appendText(" world")
        println(f.readText())

        // readBytes returns byte values
        val bytes = f.readBytes()
        println(bytes.size)
        println(bytes[0])  // 'h' = 104
        println(bytes[1])  // 'e' = 101

        // empty file
        f.writeText("")
        val empty = f.readBytes()
        println(empty.size)
    } finally {
        f.delete()
    }
}
