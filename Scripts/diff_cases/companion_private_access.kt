// Runtime coverage for companion private access that
// companion_receiver_extension_function.kt does not reach: private
// constructors invoked from companion factories, companion <-> instance
// private member access in both directions, data-class private ctor, and
// companion extension properties.

class User private constructor(private val name: String, private val age: Int) {
    companion object {
        fun createAdult(name: String): User = User(name, 18)
        fun createChild(name: String): User = User(name, 0)
        fun fromNameAndAge(name: String, age: Int): User = User(name, age)
    }

    fun getInfo(): String = "$name ($age)"
}

class Database {
    private val connection: String = "jdbc:default"
    private val maxConnections: Int = 10

    companion object {
        fun getConnection(db: Database): String = db.connection
        fun getMaxConnections(db: Database): Int = db.maxConnections
    }
}

class Calculator {
    private fun validateInput(x: Int): Boolean = x > 0
    private fun square(x: Int): Int = x * x

    companion object {
        fun safeSquare(calculator: Calculator, x: Int): Int {
            if (calculator.validateInput(x)) {
                return calculator.square(x)
            }
            return 0
        }
    }
}

class Logger {
    companion object {
        private val tag: String = "AppLogger"
        private val level: String = "INFO"
        private fun format(message: String): String = "[$level] $message"
    }

    fun log(message: String): String {
        return Companion.format(message)
    }

    fun getTag(): String {
        return Companion.tag
    }
}

data class Product private constructor(
    private val id: String,
    private val name: String,
    private val price: Double
) {
    companion object {
        fun createBasicProduct(name: String): Product = Product("basic-$name", name, 0.0)
        fun createPremiumProduct(name: String, price: Double): Product = Product("premium-$name", name, price)
    }

    fun getDescription(): String = "$name (${'$'}$price) - ID: $id"
}

class EmailAddress private constructor(private val address: String) {
    companion object {
        fun create(address: String): EmailAddress? {
            if (isValidEmail(address)) {
                return EmailAddress(address)
            }
            return null
        }

        private fun isValidEmail(address: String): Boolean {
            return address.contains("@") && address.contains(".")
        }
    }

    override fun toString(): String = address
}

class OuterClass {
    private val outerSecret: String = "outer"

    companion object {
        private val companionSecret: String = "companion"

        fun getOuterSecret(outer: OuterClass): String = outer.outerSecret
        fun getCompanionSecret(): String = companionSecret
    }

    fun getCompanionSecretFromOuter(): String = Companion.companionSecret
}

class NetworkClient {
    companion object
}

val NetworkClient.Companion.defaultTimeout: Int get() = 30000

class FileManager {
    companion object Factory
}

val FileManager.Factory.maxFiles: Int get() = 1000

fun main() {
    println(User.createAdult("Alice").getInfo())
    println(User.createChild("Bob").getInfo())
    println(User.fromNameAndAge("Charlie", 25).getInfo())

    val db = Database()
    println(Database.getConnection(db))
    println(Database.getMaxConnections(db))

    val calc = Calculator()
    println(Calculator.safeSquare(calc, 5))
    println(Calculator.safeSquare(calc, -1))

    val logger = Logger()
    println(logger.log("Test message"))
    println(logger.getTag())

    println(Product.createBasicProduct("Widget").getDescription())
    println(Product.createPremiumProduct("Gadget", 99.99).getDescription())

    println(EmailAddress.create("test@example.com")?.toString())
    println(EmailAddress.create("invalid-email")?.toString())

    val outer = OuterClass()
    println(OuterClass.getOuterSecret(outer))
    println(OuterClass.getCompanionSecret())
    println(outer.getCompanionSecretFromOuter())

    println("Default timeout: ${NetworkClient.defaultTimeout}")
    println("Max files: ${FileManager.maxFiles}")
}
