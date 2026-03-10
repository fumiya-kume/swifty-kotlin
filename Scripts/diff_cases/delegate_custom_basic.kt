var backing: String = "init"

fun assignNext(value: String) {
    backing = value
}

class StringDelegate {
    operator fun getValue(thisRef: Any?, property: Any?): String = backing

    operator fun setValue(thisRef: Any?, property: Any?, value: String) {
        assignNext(value)
    }
}

var message: String by StringDelegate()

fun main() {
    println(message)
    message = "next"
    println(message)
}
