val result = listOf(1, 2, 3, 4, 5)
    .map { it * 2 }
    .filter { it > 4 }
    .sum()
println(result)

val text = """
    Hello
    World
""".trimIndent()
println(text)

val total = (1..10)
    .filter { it % 2 == 0 }
    .fold(0) { acc, n -> acc + n }
println(total)
