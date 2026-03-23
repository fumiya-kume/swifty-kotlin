interface Logger {
    fun log(msg: String)
}
object ConsoleLogger : Logger {
    override fun log(msg: String) = println("LOG: $msg")
}
fun doWork(logger: Logger) {
    logger.log("working")
}
fun main() {
    doWork(ConsoleLogger)
    doWork(ConsoleLogger)
    ConsoleLogger.log("direct")
}
