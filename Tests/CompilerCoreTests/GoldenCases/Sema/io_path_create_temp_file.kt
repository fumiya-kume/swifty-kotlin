import kotlin.io.path.Path
import kotlin.io.path.createTempFile
import kotlin.io.path.pathString

fun createWithPrefixAndSuffix(): String {
    val tmp = createTempFile("kswiftk-", ".data")
    return tmp.pathString
}

fun createWithDirectoryPrefixAndSuffix(dir: Path): String {
    val tmp = createTempFile(dir, "kswiftk-", ".data")
    return tmp.pathString
}
