import kotlin.reflect.KProperty

class Person(val name: String, var age: Int)

fun printPropertyInfo(prop: KProperty<*>) {
    println("name: ${prop.name}")
}

fun main() {
    // Basic KProperty name access via delegate
    val p = Person("Alice", 30)

    // Access KProperty via provideDelegate pattern
    val kprop: KProperty<*> = Person::name
    println("KProperty name: ${kprop.name}")
    println("KProperty returnType: ${kprop.returnType}")

    // Using KProperty in delegate context
    printPropertyInfo(Person::name)
    printPropertyInfo(Person::age)
}
