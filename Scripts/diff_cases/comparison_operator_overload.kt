// STDLIB-OP-031: Comparison operator overloading for custom classes

class Temperature(val degrees: Double) : Comparable<Temperature> {
    override fun compareTo(other: Temperature): Int = when {
        this.degrees < other.degrees -> -1
        this.degrees > other.degrees -> 1
        else -> 0
    }

    override fun equals(other: Any?): Boolean {
        if (other !is Temperature) return false
        val rhs = other as Temperature
        return this.degrees == rhs.degrees
    }

    override fun hashCode(): Int = degrees.hashCode()

    override fun toString(): String = "${degrees}C"
}

data class Point(val x: Int, val y: Int) : Comparable<Point> {
    override fun compareTo(other: Point): Int {
        return when {
            this.x < other.x -> -1
            this.x > other.x -> 1
            this.y < other.y -> -1
            this.y > other.y -> 1
            else -> 0
        }
    }
}

fun main() {
    // 1. Custom class with Comparable: compareTo-based operators
    val cold = Temperature(0.0)
    val warm = Temperature(25.0)
    val hot = Temperature(35.0)
    val sameCold = Temperature(0.0)

    println(cold < warm)
    println(hot > warm)
    println(cold <= sameCold)
    println(cold >= sameCold)
    println(warm < cold)
    println(cold > warm)

    // 2. equals/hashCode on custom class
    println(cold == sameCold)
    println(cold != warm)
    println(cold == warm)
    println(cold != sameCold)

    // 3. Data class with Comparable
    val p1 = Point(1, 2)
    val p2 = Point(3, 4)
    val p3 = Point(1, 2)
    val p4 = Point(1, 5)

    println(p1 < p2)
    println(p2 > p1)
    println(p1 <= p3)
    println(p1 >= p3)
    println(p1 < p4)
    println(p4 > p1)

    // 4. Null-safe comparison
    val maybeTemp: Temperature? = Temperature(20.0)
    val nullTemp: Temperature? = null
    println(maybeTemp == null)
    println(nullTemp == null)
    println(maybeTemp != null)
    println(nullTemp != null)

    // 5. compareTo chaining via &&
    println(cold < warm && warm < hot)
    println(hot < warm && warm < cold)
}
