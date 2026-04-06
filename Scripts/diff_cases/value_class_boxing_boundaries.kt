@JvmInline
value class Wrapper(val value: Int)

fun identity(w: Wrapper): Wrapper = w

fun box(w: Wrapper): Any = w

fun unbox(a: Any): Wrapper = a as Wrapper

fun nullableWrapper(w: Wrapper?): Int? = w?.value

fun main() {
    val w = Wrapper(10)
    println(identity(w).value)

    val boxed: Any = box(w)
    val unboxed = unbox(boxed)
    println(unboxed.value)

    val nullable: Wrapper? = Wrapper(99)
    println(nullableWrapper(nullable))

    val nullValue: Wrapper? = null
    println(nullableWrapper(nullValue))

    val list: List<Wrapper> = listOf(Wrapper(1), Wrapper(2), Wrapper(3))
    for (item in list) {
        println(item.value)
    }
}
