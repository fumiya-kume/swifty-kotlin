// RF-FIXTURE-014: File.mkdirs() and File.delete() return Boolean.
// Actual filesystem creation and deletion are executed by
// Scripts/diff_cases/file_mkdirs.kt.
import java.io.File

fun makeDirectories(dir: File) {
    val result = dir.mkdirs()
    val checked: Boolean = result
}

fun deleteFile(file: File) {
    val result = file.delete()
    val checked: Boolean = result
}
