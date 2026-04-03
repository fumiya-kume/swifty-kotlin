inline fun <reified T> isInstance(value: Any): Boolean = value is T
inline fun <reified T> castOrNull(value: Any): T? = value as? T
inline fun <reified T> castOrThrow(value: Any): T = value as T
inline fun <reified T : Comparable<T>> printBoundedType() = println(T::class.simpleName)
inline fun <reified T> printType() = println(T::class.simpleName)

fun main() {
    println(isInstance<String>("hello"))
    println(isInstance<Int>("hello"))
    println(isInstance<Int>(42))
    println(castOrThrow<String>("world"))
    printType<String>()
    printType<Int>()
    printBoundedType<String>()
    val s = castOrNull<String>("world")
    println(s)
    val n = castOrNull<String>(123)
    println(n)
}
