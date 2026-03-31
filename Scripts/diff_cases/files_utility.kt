import java.nio.file.Files

fun main() {
    // --- createTempDirectory / exists / isDirectory ---
    val tempDirPrefix = "kswiftk_files_test_" + System.currentTimeMillis()
    val tmpDir = Files.createTempDirectory(tempDirPrefix)
    println(Files.exists(tmpDir))        // true
    println(Files.isDirectory(tmpDir))   // true
    println(Files.isRegularFile(tmpDir)) // false

    // --- createFile / isRegularFile ---
    val filePath = tmpDir.resolve("test.txt")
    Files.createFile(filePath)
    println(Files.exists(filePath))        // true
    println(Files.isRegularFile(filePath)) // true
    println(Files.isDirectory(filePath))   // false

    // --- size / getLastModifiedTime ---
    println(Files.size(filePath))              // 0
    println(Files.getLastModifiedTime(filePath).toMillis() > 0) // true

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
    println(entries.toList().size > 0) // true

    // --- walk (recursive) ---
    val walked = Files.walk(tmpDir)
    println(walked.toList().size > 0) // true

    // --- newDirectoryStream ---
    val stream = Files.newDirectoryStream(tmpDir)
    println(stream.toList().size > 0) // true

    // --- createTempFile ---
    val tempFilePrefix = "kswiftk_" + System.currentTimeMillis()
    val tempFileSuffix = "." + "tmp"
    val tempFile = Files.createTempFile(tempFilePrefix, tempFileSuffix)
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
