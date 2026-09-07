import kotlin.math.PI

fun main() {
    val copied = PI
    println(PI.toRawBits() == 0x400921fb54442d18L)
    println(copied.toRawBits() == 0x400921fb54442d18L)
}
