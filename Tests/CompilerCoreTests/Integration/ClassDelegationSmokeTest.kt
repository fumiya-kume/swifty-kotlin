// CLASS-008: Basic class delegation smoke test with per-instance delegates
// class Logger(impl: Printer) : Printer by impl

interface Printer {
    fun print()
}

class FirstPrinter : Printer {
    override fun print() {
        println("first")
    }
}

class SecondPrinter : Printer {
    override fun print() {
        println("second")
    }
}

class Logger(impl: Printer) : Printer by impl

fun main() {
    val first = Logger(FirstPrinter())
    val second = Logger(SecondPrinter())
    first.print()
    second.print()
    first.print()
}
