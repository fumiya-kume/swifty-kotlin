import kotlin.io.path.Path

fun main() {
    val tmpDir = "/tmp/kswiftk_path_test_" + System.currentTimeMillis()
    val dir = Path(tmpDir)
    dir.createDirectories()
    println(dir.exists())       // true
    println(dir.isDirectory())  // true

    val file = dir.resolve("hello.txt")
    file.writeText("hello\nworld")
    println(file.exists())        // true
    println(file.isRegularFile()) // true
    println(file.name)            // hello.txt

    val content = file.readText()
    println(content)

    val lines = file.readLines()
    println(lines.size)  // 2
    for (line in lines) {
        println(line)
    }

    println(file.toString())

    val parent = file.parent
    if (parent != null) {
        println(parent.toString() == tmpDir)  // true
    }

    val resolved = dir.resolve(Path("sub"))
    println(resolved.toString())

    // cleanup
    file.deleteIfExists()
    println(file.exists())  // false
    dir.deleteIfExists()
}
