// KOTLINC_FLAGS: -Xexplicit-backing-fields
class NameHolder {
    val fullName: String
        field = "hello"
}

fun main() {
    println(42)
}
