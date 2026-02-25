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
