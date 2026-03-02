class StringDelegate {
    private var value: String = "default"
    operator fun getValue(thisRef: Any?, property: Any?): String = value
    operator fun setValue(thisRef: Any?, property: Any?, newValue: String) {
        value = newValue
    }
}

var greeting: String by StringDelegate()

fun main() {
    println(greeting)
}
