fun main() {
    // STDLIB-REGEX-095: MatchResult完全実装

    // value and range
    val regex = Regex("(\\w+)@(\\w+)\\.com")
    val match = regex.find("contact: user@example.com today")
    if (match != null) {
        println(match.value)

        // range property
        val r = match.range
        println(r.first)
        println(r.last)

        // groupValues
        println(match.groupValues.size)
        println(match.groupValues[0])
        println(match.groupValues[1])
        println(match.groupValues[2])

        // component1(), component2() destructuring
        val (whole, user) = match
        println(whole)
        println(user)
    }

    // MatchGroupCollection index access
    val dateRegex = Regex("(\\d{4})-(\\d{2})-(\\d{2})")
    val dateMatch = dateRegex.find("Today is 2024-03-15.")
    if (dateMatch != null) {
        val groups = dateMatch.groups
        println(groups[0]?.value)
        println(groups[1]?.value)
        println(groups[2]?.value)
        println(groups[3]?.value)
    }

    // next() iteration
    val numRegex = Regex("\\d+")
    var current = numRegex.find("a1b22c333")
    while (current != null) {
        println(current.value)
        current = current.next()
    }
}
