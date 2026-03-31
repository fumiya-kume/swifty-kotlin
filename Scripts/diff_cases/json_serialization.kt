import kotlinx.serialization.json.Json

fun main() {
    val json = Json.Default

    // Encode a simple map to JSON string
    val map = mapOf("name" to "Alice", "age" to "30", "active" to "true")
    val encoded = json.encodeToString(map)
    println("encoded is string: ${encoded is String}")
    println("encoded not empty: ${encoded.isNotEmpty()}")

    // Decode a JSON object back
    val jsonStr = "{\"greeting\":\"hello\",\"count\":\"42\"}"
    val decoded = json.decodeFromString(jsonStr)
    println("decoded not null: ${decoded != null}")

    // Encode a list
    val list = listOf("a", "b", "c")
    val listEncoded = json.encodeToString(list)
    println("list encoded is string: ${listEncoded is String}")
    println("list encoded not empty: ${listEncoded.isNotEmpty()}")

    // Encode nested map
    val nested = mapOf("outer" to "value")
    val nestedEncoded = json.encodeToString(nested)
    println("nested encoded is string: ${nestedEncoded is String}")

    println("OK")
}
