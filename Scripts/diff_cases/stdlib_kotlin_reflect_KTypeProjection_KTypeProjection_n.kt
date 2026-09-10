import kotlin.reflect.KTypeProjection
import kotlin.reflect.KVariance
import kotlin.reflect.typeOf

fun main() {
    val star = typeOf<List<*>>().arguments[0]
    val invariant = typeOf<List<String>>().arguments[0]
    val input = typeOf<MutableList<in Int>>().arguments[0]
    val output = typeOf<MutableList<out Long>>().arguments[0]

    println(star.component1())
    println(star.component2())
    println(star.toString())
    println(invariant.component1() == KVariance.INVARIANT)
    println(invariant.component2())
    println(invariant.toString())
    println(input.component2())
    println(input.toString())
    println(output.component2())
    println(output.toString())
    println(input.copy() == input)
    println(input.hashCode() == input.copy().hashCode())
    println(input.equals(output))
    println(input.equals(null))
}
