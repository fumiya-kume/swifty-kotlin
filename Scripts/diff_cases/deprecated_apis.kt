import kotlin.io.createTempDir
import kotlin.io.createTempFile

@Suppress("DEPRECATION_ERROR", "KSWIFTK-SEMA-DEPRECATED")
fun main() {
    val legacyChar = 65.toChar()
    println(legacyChar)

    val legacySlice = "kotlin".subSequence(1, 4)
    println(legacySlice)

    val tempDir = createTempDir(prefix = "kswiftk-", suffix = "-dir")
    println(tempDir.exists())
    println(tempDir.isDirectory)

    val tempFile = createTempFile(prefix = "kswiftk-", suffix = ".tmp", directory = tempDir)
    println(tempFile.exists())
    println(tempFile.isFile)

    tempFile.delete()
    tempDir.delete()
}
