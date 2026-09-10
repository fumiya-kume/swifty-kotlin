// RF-FIXTURE-014: File.listFiles() returns a nullable listing
// (List<out File>? in this stdlib model). Actual directory listing is
// executed by Scripts/diff_cases/file_listfiles.kt.
import java.io.File

fun listChildren(dir: File) {
    val children = dir.listFiles()
    val checked: List<out File>? = children
}
