fun main() {
    // Named capture groups with MatchResult.groups
    val regex = Regex("(?<year>\\d{4})-(?<month>\\d{2})-(?<day>\\d{2})")
    val match = regex.find("Date: 2024-03-15")
    if (match != null) {
        println(match.value)
        val groups = match.groups
        val yearGroup = groups.get("year")
        println(yearGroup?.value)
        val monthGroup = groups.get("month")
        println(monthGroup?.value)
        val dayGroup = groups.get("day")
        println(dayGroup?.value)
    }

    // RegexOption.IGNORE_CASE
    val caseRegex = Regex("[a-z]+", RegexOption.IGNORE_CASE)
    println(caseRegex.containsMatchIn("HELLO"))

    // RegexOption.MULTILINE
    val multilineRegex = Regex("^hello", RegexOption.MULTILINE)
    println(multilineRegex.containsMatchIn("world\nhello"))

    // RegexOption.DOT_MATCHES_ALL
    val dotRegex = Regex("hello.world", RegexOption.DOT_MATCHES_ALL)
    println(dotRegex.containsMatchIn("hello\nworld"))
}
