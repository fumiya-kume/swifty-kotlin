import java.io.File

fun main() {
    val f = File("test.bin")
    val bytes = byteArrayOf(1, 2, 3)
    f.appendBytes(bytes)
}
