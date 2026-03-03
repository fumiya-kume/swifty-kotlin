// CLASS-008: Basic class delegation

interface Printer {
    fun print()
}

class PrinterImpl : Printer {
    override fun print() {
        println("PrinterImpl")
    }
}

class Logger(impl: Printer) : Printer by impl

fun main() {
    val impl = PrinterImpl()
    val logger = Logger(impl)
    println("before")
    logger.print()
    println("after")
}
