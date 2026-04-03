import kotlinx.serialization.json.Json

fun main() {
    val json = Json.Default

    val list = listOf(1, 2, 3)
    println(json.encodeToString(list))

    val map = mapOf(
        "name" to "Alice",
        "count" to 2,
        "enabled" to true
    )
    println(json.encodeToString(map))

    val set = linkedSetOf("red", "green", "blue")
    println(json.encodeToString(set))

    val nested = mapOf(
        "items" to listOf(
            mapOf("id" to 1, "tags" to listOf("a", "b")),
            mapOf("id" to 2, "tags" to emptyList<String>())
        ),
        "flags" to setOf(true, false),
        "matrix" to listOf(listOf(1, 2), listOf(3, 4))
    )
    println(json.encodeToString(nested))

    println("OK")
}
