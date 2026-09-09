// RF-FIXTURE-014: File.walk() returns the recursive file listing type
// (List<out File> in this stdlib model). Traversal behavior is executed by
// Scripts/diff_cases/file_walk.kt.
import java.io.File

fun walkTree(dir: File) {
    val walked = dir.walk()
    val checked: List<out File> = walked
}
