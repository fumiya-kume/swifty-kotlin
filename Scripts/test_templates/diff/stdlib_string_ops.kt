fun main() {
    println("  hello  ".trim())
    println("1,2,3".split(","))
    println("42".toInt())

    println("banana".replace("na", "NA"))
    println(if ("Kotlin".startsWith("Ko")) "true" else "false")
    println(if ("Kotlin".endsWith("in")) "true" else "false")
    println(if ("Kotlin".contains("otl")) "true" else "false")

    println(" 3.14 ".toDouble())
}
