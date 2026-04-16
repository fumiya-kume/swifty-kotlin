fun dumpLines(prefix: String, values: List<String>) {
    println("$prefix:${values.joinToString("|")}")
}

fun main() {
    println("hello".substringBefore("."))
    println("hello.world.kt".substringBefore("."))
    println("hello.world.kt".substringBeforeLast("."))
    println("nodelem".substringBefore(":"))

    println("hello".replaceFirstChar { 'H' })
    println("beta".replaceFirstChar { 'B' })
    println("".replaceFirstChar { 'X' })

    dumpLines("lines-empty", "".lines())
    dumpLines("lines-ascii", "a\nb\n".lines())
    dumpLines("lines-unicode", "こんにちは\n世界".lines())

    dumpLines("seq-empty", "".lineSequence().toList())
    dumpLines("seq-mixed", "a\r\nb\nc".lineSequence().toList())
    dumpLines("seq-head-tail", "\nalpha\n".lineSequence().toList())
}
