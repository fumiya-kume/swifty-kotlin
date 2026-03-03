package golden.sema

class StringDelegate {
    operator fun getValue(thisRef: Any?, property: Any?): String = "default"
    operator fun setValue(thisRef: Any?, property: Any?, value: String) {}
}

var greeting: String by StringDelegate()

fun main() {
    println(greeting)
}
