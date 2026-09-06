import kotlin.reflect.KCallable
import kotlin.reflect.KFunction
import kotlin.reflect.KProperty

class Sample(val value: Int)

fun answer(): String = "answer"

fun read(callable: KCallable<*>): String {
    val name = callable.name
    val type = callable.returnType
    val isString = type.toString().contains("String")
    return name + ":" + isString
}

fun readFunction(function: KFunction<*>): Boolean =
    function.returnType.toString().contains("String")

fun readProperty(property: KProperty<*>): Boolean =
    property.returnType.toString().contains("Int")

fun readNullable(callable: KCallable<*>?): Boolean = callable?.returnType == null

fun main() {
    val function: KFunction<*> = ::answer
    val property: KProperty<*> = Sample::value
    println(read(function))
    println(read(property))
    println(readFunction(function))
    println(readProperty(property))
    println(readNullable(null))
}
