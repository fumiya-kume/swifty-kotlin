import java.io.File

fun main() {
    val f = File("/tmp/kswiftk_readbytes_" + System.currentTimeMillis() + ".txt")
    try {
        f.writeText("ABC")
        val bytes = f.readBytes()
        println(bytes.size)
        println(bytes[0])
        println(bytes[1])
        println(bytes[2])

        // empty file
        f.writeText("")
        val empty = f.readBytes()
        println(empty.size)
    } finally {
        f.delete()
    }
}
