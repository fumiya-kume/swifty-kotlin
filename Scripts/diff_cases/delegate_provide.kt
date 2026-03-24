import kotlin.properties.ReadOnlyProperty
import kotlin.reflect.KProperty

class ResourceDelegate(val name: String) : ReadOnlyProperty<Any?, String> {
    override fun getValue(thisRef: Any?, property: KProperty<*>) = "Resource[$name]"
}
class ResourceLoader {
    operator fun provideDelegate(thisRef: Any?, prop: KProperty<*>): ResourceDelegate {
        println("provideDelegate for ${prop.name}")
        return ResourceDelegate(prop.name)
    }
}
val resource by ResourceLoader()
fun main() { println(resource) }
