import java.nio.file.Files
import kotlin.io.path.Path

fun main() {
    // --- createTempDirectory / exists / isDirectory ---
    val tmpDir = Files.createTempDirectory("kswiftk_files_test_")
    println(Files.exists(tmpDir))        // true
    println(Files.isDirectory(tmpDir))   // true
    println(Files.isRegularFile(tmpDir)) // false

    // --- createFile / isRegularFile ---
    val filePath = tmpDir.resolve("test.txt")
    Files.createFile(filePath)
    println(Files.exists(filePath))        // true
    println(Files.isRegularFile(filePath)) // true
    println(Files.isDirectory(filePath))   // false

    // --- size / lastModifiedTime ---
    println(Files.size(filePath))              // 0
    println(Files.lastModifiedTime(filePath) > 0) // true

    // --- createDirectory ---
    val subDir = tmpDir.resolve("sub")
    Files.createDirectory(subDir)
    println(Files.isDirectory(subDir)) // true

    // --- createDirectories (nested) ---
    val deepDir = tmpDir.resolve("a").resolve("b").resolve("c")
    Files.createDirectories(deepDir)
    println(Files.isDirectory(deepDir)) // true

    // --- copy ---
    val copyTarget = tmpDir.resolve("test_copy.txt")
    Files.copy(filePath, copyTarget)
    println(Files.exists(copyTarget)) // true

    // --- move ---
    val moveTarget = tmpDir.resolve("test_moved.txt")
    Files.move(copyTarget, moveTarget)
    println(Files.exists(moveTarget))  // true
    println(Files.exists(copyTarget))  // false

    // --- list ---
    val entries = Files.list(tmpDir)
    println(entries.size > 0) // true

    // --- walk (recursive) ---
    val walked = Files.walk(tmpDir)
    println(walked.size > 0) // true

    // --- newDirectoryStream ---
    val stream = Files.newDirectoryStream(tmpDir)
    println(stream.size > 0) // true

    // --- createTempFile ---
    val tempFile = Files.createTempFile("kswiftk_", ".tmp")
    println(Files.exists(tempFile))        // true
    println(Files.isRegularFile(tempFile)) // true

    // --- delete ---
    Files.delete(tempFile)
    println(Files.exists(tempFile)) // false

    // clean up
    Files.delete(moveTarget)
    Files.delete(filePath)
    Files.delete(subDir)
    Files.delete(deepDir)
    Files.delete(tmpDir.resolve("a").resolve("b"))
    Files.delete(tmpDir.resolve("a"))
    Files.delete(tmpDir)

    println("done")
}
