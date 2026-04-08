import java.io.File

fun main() {
    val legacyChar = 65.toChar()
    println(legacyChar)

    val legacySlice = "kotlin".subSequence(1, 4)
    println(legacySlice)

    val tempDir = File("/tmp/kswiftk-deprecated-test-dir")
    tempDir.mkdirs()
    println(tempDir.exists())
    println(tempDir.isDirectory)

    val tempFile = File("/tmp/kswiftk-deprecated-test-dir/kswiftk-deprecated.tmp")
    tempFile.createNewFile()
    println(tempFile.exists())
    println(tempFile.isFile)

    tempFile.delete()
    tempDir.delete()
}
