package golden.sema

interface A {
    fun a(): String
}

interface B {
    fun b(): Int
}

fun intersect(x: Any): String {
    if (x is A && x is B) {
        return x.a() + x.b().toString()
    }
    return "unknown"
}

fun Any.idTag(): Int = 7

fun <T : Any?> directValue(x: T & Any): Int = x.idTag()
fun <T : Any?> safeValue(x: T & Any): Int? = x?.idTag()
