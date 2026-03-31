class Counter(var value: Int) {
    operator fun unaryPlus(): Counter = Counter(value)
    operator fun unaryMinus(): Counter = Counter(-value)
    operator fun plus(other: Counter): Counter = Counter(value + other.value)
    operator fun minus(other: Counter): Counter = Counter(value - other.value)
    operator fun times(other: Counter): Counter = Counter(value * other.value)
    operator fun div(other: Counter): Counter = Counter(value / other.value)
    operator fun rem(other: Counter): Counter = Counter(value % other.value)
}

class MutableCounter(var value: Int) {
    operator fun plusAssign(other: Counter) {
        value = value + other.value
    }

    operator fun minusAssign(other: Counter) {
        value = value - other.value
    }

    operator fun timesAssign(other: Counter) {
        value = value * other.value
    }

    operator fun divAssign(other: Counter) {
        value = value / other.value
    }

    operator fun remAssign(other: Counter) {
        value = value % other.value
    }
}

class Toggle(private val enabled: Boolean) {
    operator fun not(): Toggle = Toggle(!enabled)
    fun value(): Boolean = enabled
}

fun main() {
    val base = Counter(10)
    val add = Counter(3)
    val scale = Counter(4)
    val dec = Counter(8)
    val div = Counter(2)

    println((+base).value)
    println((-base).value)
    println((base + add).value)
    println((base - add).value)
    println((base * add).value)
    println((base / div).value)
    println((base % add).value)

    val precedence = base + add * scale - dec / div
    println(precedence.value)

    var assigned = MutableCounter(20)
    assigned += Counter(5)
    assigned -= Counter(3)
    assigned *= Counter(2)
    assigned /= Counter(11)
    assigned %= Counter(3)
    println(assigned.value)

    val toggle = Toggle(false)
    println((!toggle).value())
}
