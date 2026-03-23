// SKIP-DIFF: explicit backing fields require -Xexplicit-backing-fields and are experimental in kotlinc
class NameHolder {
    val fullName: String
        field = ""
        get() = field.uppercase()
}

fun main() {
    println(42)
}
