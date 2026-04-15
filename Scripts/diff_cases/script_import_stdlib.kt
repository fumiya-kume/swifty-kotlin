// SKIP-DIFF
import kotlin.math.*
import kotlin.collections.*

val numbers = listOf(1, 2, 3, 4, 5)
val max = max(numbers[0], numbers[4])
val sqrtValue = sqrt(16.0)
val absValue = abs(-5)
val shuffled = numbers.shuffled()

println("max: $max, sqrt: $sqrtValue, abs: $absValue")
println("shuffled: $shuffled")
