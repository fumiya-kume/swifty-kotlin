annotation class Serializable

@Serializable
data class Address(
    val city: String,
    val zip: String? = null
)

@Serializable
data class User(
    val name: String,
    val age: Int = 20,
    val nickname: String? = null,
    val address: Address = Address("unknown")
)

fun main() {
    val json = kotlinx.serialization.json.Json.Default

    val full = User(
        name = "Alice",
        age = 30,
        nickname = "ally",
        address = Address(city = "Tokyo", zip = "100-0001")
    )
    val fullEncoded = json.encodeToString(full)
    println(fullEncoded.contains("\"name\":\"Alice\""))
    println(fullEncoded.contains("\"age\":30"))
    println(fullEncoded.contains("\"nickname\":\"ally\""))
    println(fullEncoded.contains("\"address\":"))
    println(fullEncoded.contains("\"city\":\"Tokyo\""))
    println(fullEncoded.contains("\"zip\":\"100-0001\""))

    val defaults = User(name = "Bob")
    val defaultsEncoded = json.encodeToString(defaults)
    println(defaultsEncoded.contains("\"name\":\"Bob\""))
    println(defaultsEncoded.contains("\"age\":20"))
    println(defaultsEncoded.contains("\"nickname\":null"))
    println(defaultsEncoded.contains("\"city\":\"unknown\""))
    println(defaultsEncoded.contains("\"zip\":null"))
}
