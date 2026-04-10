// SKIP-DIFF
data class Entry(val group: Int, val score: Int)

fun main() {
    val values = listOf(
        Entry(1, 30),
        Entry(1, 20),
        Entry(2, 10),
        Entry(2, 40),
    )

    val chained = compareBy<Entry> { it.group }
        .thenBy { -it.score }
    println(values.sortedWith(chained).map { "${it.group}:${it.score}" })

    println(values.sortedWith(chained.reversed()).map { "${it.group}:${it.score}" })

    val words = listOf("pear", "fig", "apple")
    println(words.sortedWith(reverseOrder()))
}
