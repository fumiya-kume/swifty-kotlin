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

    // STDLIB-IO-089: Path complete implementation

    // root property
    val absPath = Path("/home/user/docs")
    val rootPath = absPath.root
    println(rootPath?.toString() == "/")   // true

    val relPath = Path("a/b/c")
    println(relPath.root == null)          // true

    // nameCount property
    println(absPath.nameCount)             // 3
    println(relPath.nameCount)             // 3

    // fileName property
    println(file.fileName?.toString() == "hello.txt")  // true

    // relativize
    val base = Path("/home/user")
    val target = Path("/home/user/docs/file.txt")
    val relative = base.relativize(target)
    println(relative.toString())           // docs/file.txt

    // normalize
    val messy = Path("/home/user/../user/./docs")
    val clean = messy.normalize()
    println(clean.toString())              // /home/user/docs

    // isAbsolute
    println(absPath.isAbsolute)            // true
    println(relPath.isAbsolute)            // false

    // startsWith
    println(absPath.startsWith(Path("/home/user")))  // true
    println(absPath.startsWith("/home/user"))         // true
    println(absPath.startsWith(Path("/other")))       // false

    // endsWith
    println(absPath.endsWith(Path("user/docs")))  // true
    println(absPath.endsWith("user/docs"))         // true
    println(absPath.endsWith(Path("other")))       // false

    // getName
    println(absPath.getName(0).toString())  // home
    println(absPath.getName(2).toString())  // docs

    // toAbsolutePath on absolute path is identity
    println(absPath.toAbsolutePath().toString() == "/home/user/docs")  // true

    // cleanup
    file.deleteIfExists()
    println(file.exists())  // false
    dir.deleteIfExists()
}
