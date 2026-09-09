import kotlin.reflect.typeOf

fun main() {
    val plain = typeOf<String>()
    val nullable = typeOf<String?>()
    println(plain.classifier != null)
    println(plain.arguments.size)
    println(plain.isMarkedNullable)
    println(nullable.isMarkedNullable)
}
