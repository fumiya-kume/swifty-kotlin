class WrappedDelegate(private val inner: String) {
    operator fun getValue(thisRef: Any?, property: Any?): String = inner
}

class DelegateProvider(private val value: String) {
    operator fun provideDelegate(thisRef: Any?, property: Any?): WrappedDelegate {
        println("provideDelegate called for $property")
        return WrappedDelegate(value)
    }
}

val message: String by DelegateProvider("hello")

fun main() {
    println(message)
}
