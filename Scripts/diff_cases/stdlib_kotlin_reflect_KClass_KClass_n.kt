import kotlin.reflect.KClass

class First
class Second

fun compareClasses(left: KClass<*>, right: Any?): Boolean = left.equals(right)

fun hashMatches(left: KClass<*>, right: KClass<*>): Boolean = left.hashCode() == right.hashCode()

fun main() {
    val first: KClass<*> = First::class
    val same: KClass<*> = First::class
    val other: KClass<*> = Second::class

    println(compareClasses(first, same))
    println(compareClasses(first, other))
    println(compareClasses(first, null))
    println(hashMatches(first, same))
    println(first == same)
    println(first != other)
}
