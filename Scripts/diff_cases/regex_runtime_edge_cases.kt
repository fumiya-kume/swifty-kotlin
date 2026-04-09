fun main() {
    val named = Regex("(?<year>\\d{4})-(?<month>\\d{2})")
    val match = named.find("2025-04")
    println(match?.groups?.get("year")?.value)
    println(match?.groups?.get("month")?.value)

    try {
        Regex("(")
        println("unexpected-regex")
    } catch (e: Throwable) {
        println("invalid-pattern")
    }
}
