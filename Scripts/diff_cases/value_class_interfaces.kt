interface Printable {
    fun print()
}

interface Describable {
    fun describe(): String
}

@JvmInline
value class Celsius(val degrees: Double) : Printable, Describable {
    override fun print() {
        println("${degrees}°C")
    }

    override fun describe(): String = "Celsius($degrees)"
}

@JvmInline
value class Fahrenheit(val degrees: Double) : Printable {
    override fun print() {
        println("${degrees}°F")
    }
}

fun printTemperature(p: Printable) {
    p.print()
}

fun describeItem(d: Describable): String = d.describe()

fun main() {
    val c = Celsius(100.0)
    c.print()
    println(c.describe())
    println(describeItem(c))

    val f = Fahrenheit(212.0)
    f.print()

    printTemperature(c)
    printTemperature(f)
}
