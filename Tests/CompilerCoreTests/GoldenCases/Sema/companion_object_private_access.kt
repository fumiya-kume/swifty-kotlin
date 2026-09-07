package golden.sema

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
        fun fromCatalog(id: String, name: String, price: Double): Product = Product(id, name, price)
    }

    fun getDescription(): String = "$name ($$price) - ID: $id"
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

fun NetworkClient.Companion.createDefault(): NetworkClient = NetworkClient()
fun NetworkClient.Companion.createWithTimeout(timeout: Int): NetworkClient = NetworkClient()

class FileManager {
    companion object Factory
}

fun FileManager.Factory.createFile(): FileManager = FileManager()
fun FileManager.Factory.createReadOnly(): FileManager = FileManager()

val NetworkClient.Companion.defaultTimeout: Int get() = 30000
val FileManager.Factory.maxFiles: Int get() = 1000

fun main() {
    val adult = User.createAdult("Alice")
    val child = User.createChild("Bob")
    val custom = User.fromNameAndAge("Charlie", 25)

    println(adult.getInfo())
    println(child.getInfo())
    println(custom.getInfo())

    val db = Database()
    println(Database.getConnection(db))
    println(Database.getMaxConnections(db))

    val calc = Calculator()
    println(Calculator.safeSquare(calc, 5))
    println(Calculator.safeSquare(calc, -1))

    val logger = Logger()
    println(logger.log("Test message"))
    println(logger.getTag())

    val basic = Product.createBasicProduct("Widget")
    val premium = Product.createPremiumProduct("Gadget", 99.99)
    val catalog = Product.fromCatalog("P123", "Thingamajig", 49.95)

    println(basic.getDescription())
    println(premium.getDescription())
    println(catalog.getDescription())

    val validEmail = EmailAddress.create("test@example.com")
    val invalidEmail = EmailAddress.create("invalid-email")

    println(validEmail?.toString())
    println(invalidEmail?.toString())

    val outer = OuterClass()
    println(OuterClass.getOuterSecret(outer))
    println(OuterClass.getCompanionSecret())
    println(outer.getCompanionSecretFromOuter())

    val client1 = NetworkClient.createDefault()
    val client2 = NetworkClient.createWithTimeout(5000)

    println("Default timeout: ${NetworkClient.defaultTimeout}")

    val file1 = FileManager.createFile()
    val file2 = FileManager.createReadOnly()

    println("Max files: ${FileManager.maxFiles}")
}
