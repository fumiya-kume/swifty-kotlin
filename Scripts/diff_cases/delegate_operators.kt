import kotlin.properties.ReadWriteProperty
import kotlin.reflect.KProperty

// Demonstrates all three delegate operators: getValue, setValue, provideDelegate.
class ValidatedDelegate(private var value: String) : ReadWriteProperty<Any?, String> {
    override operator fun getValue(thisRef: Any?, property: KProperty<*>): String = value
    override operator fun setValue(thisRef: Any?, property: KProperty<*>, value: String) {
        this.value = value.trim()
    }
}

class DelegateFactory {
    operator fun provideDelegate(thisRef: Any?, prop: KProperty<*>): ValidatedDelegate {
        println("Creating delegate for ${prop.name}")
        return ValidatedDelegate("")
    }
}

var name: String by DelegateFactory()

fun main() {
    name = "  Alice  "
    // Expected output:
    // Creating delegate for name
    // Alice
    println(name)
}
