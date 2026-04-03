import kotlinx.serialization.Decoder
import kotlinx.serialization.Encoder
import kotlinx.serialization.KSerializer
import kotlinx.serialization.json.Json

class Person(val name: String, val age: Int)

object PersonSerializer : KSerializer {
    override fun serialize(encoder: Encoder, value: Any) {
        val person = value as Person
        if (person.age < 0) {
            throw IllegalArgumentException("age must be non-negative")
        }
        if (encoder.context.serializerFor(Person::class) == null) {
            throw IllegalStateException("serializer context missing")
        }
        encoder.encodeString("${person.name}:${person.age}")
    }

    override fun deserialize(decoder: Decoder): Any {
        val raw = decoder.decodeString()
        val parts = raw.split(":")
        return Person(parts[0], parts[1].toInt())
    }
}

fun main() {
    val json = Json.Default.registerSerializer(Person::class, PersonSerializer)
    val source = Person("Ada", 37)

    println(json.serializerFor(Person::class) != null)
    println(json.encodeToString(PersonSerializer, source))
    println(json.encodeToString(source))

    val decoded = json.decodeFromString(PersonSerializer, "\"Grace:44\"") as Person
    println("${decoded.name}:${decoded.age}")
}
