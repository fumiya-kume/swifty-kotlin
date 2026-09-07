package golden.sema

import kotlin.time.Duration.Companion.seconds
import kotlin.time.TimedValue

fun exerciseTimedValueMembers(): TimedValue<String> {
    val tv = TimedValue("hello", 5.seconds)
    val (v, d) = tv
    val copied = tv.copy()
    val valueChanged = tv.copy(value = "world")
    val durationChanged = tv.copy(duration = 10.seconds)
    val bothChanged = tv.copy("changed", 1.seconds)

    println(tv.value)
    println(tv.duration)
    println(tv.component1())
    println(tv.component2())
    println(tv.toString())
    println(v)
    println(d)
    println(tv.equals(copied))
    println(copied == tv)
    println(copied.hashCode() == tv.hashCode())
    println(valueChanged)
    println(valueChanged == tv)
    println(durationChanged)
    return bothChanged
}
