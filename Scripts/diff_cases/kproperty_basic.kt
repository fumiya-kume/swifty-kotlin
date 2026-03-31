import kotlin.reflect.KProperty

class Person(val name: String, var age: Int)

fun printPropertyInfo(prop: KProperty<*>) {
    println("property captured")
}

fun main() {
    val kprop: KProperty<*> = Person::name
    val another: KProperty<*> = Person::age
    printPropertyInfo(kprop)
    printPropertyInfo(another)
}
