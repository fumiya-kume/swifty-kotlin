fun main() {
    println("  hello  ".trim())
    println("1,2,3".split(","))
    println("42".toInt())

    println("banana".replace("na", "NA", true))
    println(if ("Kotlin".startsWith("kot", 0, true)) "true" else "false")
    println(if ("Kotlin".endsWith("LIN", true)) "true" else "false")
    println(if ("Kotlin".contains("OTL", true)) "true" else "false")

    println(" 3.14 ".toDouble())
    println("%s-%04d-%.1f".format("x", 7, 3.5))
}
