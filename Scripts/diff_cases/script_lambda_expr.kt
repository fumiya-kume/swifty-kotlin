val numbers = listOf(1, 2, 3, 4, 5)
val doubled = numbers.map { it * 2 }
val sum = numbers.reduce { acc, n -> acc + n }
val filtered = numbers.filter { it % 2 == 0 }
println("doubled: $doubled, sum: $sum, filtered: $filtered")
