// KSP-1432: named-group lookup preserves the Kotlin contract for matched,
// optional, and undefined named groups.

fun main() {
    val optional = Regex("(?<name>a)?").find("")
    println(optional?.groups?.get("name")?.value ?: "null")

    val matched = Regex("(?<name>a)").find("a")
    println(matched?.groups?.get("name")?.value ?: "null")

    try {
        matched?.groups?.get("missing")
        println("no-error")
    } catch (e: IllegalArgumentException) {
        println("invalid-name")
    }
}
