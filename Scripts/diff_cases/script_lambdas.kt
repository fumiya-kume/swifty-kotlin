val double = { x: Int -> x * 2 }
val add = { a: Int, b: Int -> a + b }
val isEven = { n: Int -> n % 2 == 0 }

println(double(5))
println(add(3, 7))
println(isEven(4))
println(isEven(7))

val numbers = listOf(1, 2, 3, 4, 5)
val doubled = numbers.map(double)
println(doubled)
val evens = numbers.filter(isEven)
println(evens)
