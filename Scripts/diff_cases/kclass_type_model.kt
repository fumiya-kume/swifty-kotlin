// REFL-001: KClass<T> / KType end-to-end type modeling
// Verifies that ::class expressions carry the correct KClass<T> type.

inline fun <reified T> typeNameOf(): String = T::class.simpleName ?: "unknown"

fun main() {
    // Concrete class references
    val intClass = Int::class
    val stringClass = String::class

    // Reified type parameter
    println(typeNameOf<Int>())
    println(typeNameOf<String>())

    // Class reference .simpleName
    println(Int::class.simpleName)
    println(String::class.simpleName)
}
