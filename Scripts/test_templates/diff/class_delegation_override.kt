// CLASS-008: Class delegation with override — override takes precedence over delegation

interface Printer {
    fun print()
}

class PrinterImpl : Printer {
    override fun print() {
        println("PrinterImpl")
    }
}

class Logger(impl: Printer) : Printer by impl {
    override fun print() {
        println("Logger")
    }
}

fun main() {
    val impl = PrinterImpl()
    val logger = Logger(impl)
    println("before")
    logger.print()
    println("after")
}
