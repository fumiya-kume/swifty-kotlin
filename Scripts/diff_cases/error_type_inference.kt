// SKIP-DIFF
// Error cases for type inference failures (KSWIFTK-TYPE-*)

// ERROR: Cannot infer type for lambda with ambiguous overloads
fun process(block: (Int) -> String) = block(1)
fun process(block: (String) -> Int) = block("a")

val result = process { it }  // KSWIFTK-TYPE-0001: ambiguous overload, cannot infer lambda parameter type

// ERROR: Type variable with no constraints cannot be resolved
fun <T> identity(x: T) = x

val unknown = identity(null)  // KSWIFTK-TYPE-0002: cannot infer T from null literal alone

// ERROR: Conflicting type constraints in generic function
fun <T> conflicting(a: T, b: T): T where T : Int, T : String = a  // KSWIFTK-TYPE-0003: Int and String are incompatible upper bounds

// ERROR: Cannot infer type parameter when no argument provided
fun <T> produce(): T = TODO()

val bad: Any = produce()  // KSWIFTK-TYPE-0004: cannot infer T without explicit type argument

// ERROR: Recursive type inference loop
val cyclic: List<*> = listOf(cyclic)  // KSWIFTK-TYPE-0005: recursive initializer reference

fun main() {
    // Intentionally left empty — errors are at top level
}
