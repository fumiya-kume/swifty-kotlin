import kotlin.io.path.Path

fun main() {
    val base = Path("/usr/local")
    val child = Path("/usr/local/bin")

    // normalize
    val unnorm = Path("/foo/bar/../baz")
    val norm = unnorm.normalize()
    println(norm.toString())

    // fileName property (Path? wrapping last component, null for root paths)
    val fn = child.fileName
    if (fn != null) {
        println(fn.toString())
    }

    // root property
    val root = child.root
    if (root != null) {
        println(root.toString())
    }

    // nameCount
    println(child.nameCount)

    // startsWith
    println(child.startsWith(base))
    println(child.startsWith("/usr/local"))

    // endsWith
    println(child.endsWith(Path("local/bin")))
    println(child.endsWith("bin"))

    // relativize
    val rel = base.relativize(child)
    println(rel.toString())

    // relativize reverse (back-tracking)
    val p1 = Path("/a/b")
    val p2 = Path("/a/c/d")
    println(p1.relativize(p2).toString())

    // toFile - just check we can call it without crash
    val javaFile = child.toFile()
    println(javaFile.path)
}
