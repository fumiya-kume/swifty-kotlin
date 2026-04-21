fun main() {
    val s = sequenceOf(1, 2, 3, 4, 5)

    // any() — short-circuits at first element (non-empty)
    val hasAny: Boolean = s.any()

    // any(predicate) — short-circuits at first match
    val hasEven: Boolean = s.any { it % 2 == 0 }

    // all(predicate) — short-circuits at first non-match
    val allPositive: Boolean = s.all { it > 0 }

    // none() — short-circuits at first element (empty check)
    val hasNone: Boolean = s.none()

    // none(predicate) — short-circuits at first match
    val noneNegative: Boolean = s.none { it < 0 }

    // find(predicate) — short-circuits at first match
    val firstEven: Int? = s.find { it % 2 == 0 }

    // findLast(predicate) — traverses all, returns last match
    val lastEven: Int? = s.findLast { it % 2 == 0 }

    println(hasAny)
    println(hasEven)
    println(allPositive)
    println(hasNone)
    println(noneNegative)
    println(firstEven)
    println(lastEven)
}
