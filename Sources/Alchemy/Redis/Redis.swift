import NIO
import RediStack

extension Redis: Service {
    /// A single redis connection
    public static func connection(
        _ host: String,
        port: Int = 6379,
        password: String? = nil,
        database: Int? = nil,
        poolSize: RedisConnectionPoolSize = .maximumActiveConnections(1)
    ) -> Redis {
        return .cluster(.ip(host: host, port: port), password: password, database: database, poolSize: poolSize)
    }
    
    /// Convenience initializer for creating a redis client with the
    /// given information.
    ///
    /// - Parameters:
    ///   - socket: The `Socket` to connect to. Can provide multiple
    ///     sockets if using a Redis cluster.
    ///   - password: The password for authenticating connections.
    ///   - database: The database index to connect to. Defaults to
    ///     nil, which uses the default index, 0.
    ///   - poolSize: The connection pool size to use for each
    ///     connection pool. **Note:** There is one connection pool
    ///     per `EventLoop` of your application (meaning 1 per logical
    ///     core on your machine).
    public static func cluster(
        _ sockets: Socket...,
        password: String? = nil,
        database: Int? = nil,
        poolSize: RedisConnectionPoolSize = .maximumActiveConnections(1)
    ) -> Redis {
        return .rawPoolConfiguration(
            RedisConnectionPool.Configuration(
                initialServerConnectionAddresses: sockets.map(\.nio),
                maximumConnectionCount: poolSize,
                connectionFactoryConfiguration: RedisConnectionPool.ConnectionFactoryConfiguration(
                    connectionInitialDatabase: database,
                    connectionPassword: password,
                    connectionDefaultLogger: Log.logger
                )
            )
        )
    }
    
    /// A custom configuration for the Redis instance's connection
    /// pool. Other initializers passthrough to this.
    public static func rawPoolConfiguration(_ config: RedisConnectionPool.Configuration) -> Redis {
        return Redis(config: config)
    }
}

/// A client for interfacing with a Redis instance.
public final class Redis { 
    fileprivate let driver: RedisDriver

    /// Creates a Redis client that will connect with the given
    /// configuration.
    ///
    /// - Parameters:
    ///   - config: The configuration of the pool backing this `Redis`
    ///     client.
    fileprivate init(config: RedisConnectionPool.Configuration) {
        self.driver = ConnectionPool(config: config)
    }

    /// Used for `Redis.transaction(...)`
    fileprivate init(connection: RedisConnection) {
        self.driver = Connection(connection: connection)
    }
    
    /// Shuts down this `Redis` client, closing it's associated
    /// connection pools.
    public func shutdown() throws {
        try driver.shutdown()
    }
}

private protocol RedisDriver {
    func getClient() -> RedisClient
    func shutdown() throws
    func leaseConnection<T>(_ transaction: @escaping (RedisConnection) -> EventLoopFuture<T>) -> EventLoopFuture<T>
}

private struct Connection: RedisDriver {
    let connection: RedisConnection

    func getClient() -> RedisClient { 
        connection 
    }

    func shutdown() throws {
        try connection.close().wait()
    }
    
    func leaseConnection<T>(_ transaction: @escaping (RedisConnection) -> EventLoopFuture<T>) -> EventLoopFuture<T> {
        transaction(connection)
    }
}

private final class ConnectionPool: RedisDriver {
    /// Map of `EventLoop` identifiers to respective connection pools.
    @Locked
    private var poolStorage: [ObjectIdentifier: RedisConnectionPool] = [:]
    
    /// The configuration to create pools with.
    private var config: RedisConnectionPool.Configuration

    init(config: RedisConnectionPool.Configuration) {
        self.config = config
    }

    func getClient() -> RedisClient {
        getPool()
    }

    func leaseConnection<T>(_ transaction: @escaping (RedisConnection) -> EventLoopFuture<T>) -> EventLoopFuture<T> {
        getPool().leaseConnection(transaction)
    }

    func shutdown() throws {
        try poolStorage.values.forEach {
            let promise: EventLoopPromise<Void> = $0.eventLoop.makePromise()
            $0.close(promise: promise)
            try promise.futureResult.wait()
        }
    }

    /// Gets or creates a pool for the current `EventLoop`.
    ///
    /// - Returns: A `RedisConnectionPool` associated with the current
    ///   `EventLoop` for sending commands to.
    fileprivate func getPool() -> RedisConnectionPool {
        let loop = Loop.current
        let key = ObjectIdentifier(loop)
        if let pool = self.poolStorage[key] {
            return pool
        } else {
            let newPool = RedisConnectionPool(configuration: self.config, boundEventLoop: loop)
            self.poolStorage[key] = newPool
            return newPool
        }
    }
}

/// Alchemy specific.
extension RedisClient {
    /// Wrapper around sending commands to Redis.
    ///
    /// - Parameters:
    ///   - name: The name of the command.
    ///   - args: Any arguments for the command.
    /// - Returns: A future containing the return value of the
    ///   command.
    public func command(_ name: String, args: RESPValueConvertible...) -> EventLoopFuture<RESPValue> {
        self.command(name, args: args)
    }
    
    /// Wrapper around sending commands to Redis.
    ///
    /// - Parameters:
    ///   - name: The name of the command.
    ///   - args: An array of arguments for the command.
    /// - Returns: A future containing the return value of the
    ///   command.
    public func command(_ name: String, args: [RESPValueConvertible]) -> EventLoopFuture<RESPValue> {
        self.send(command: name, with: args.map { $0.convertedToRESPValue() })
    }
    
    /// Evaluate the given Lua script.
    ///
    /// - Parameters:
    ///   - script: The script to run.
    ///   - keys: The arguments that represent Redis keys. See
    ///     [EVAL](https://redis.io/commands/eval) docs for details.
    ///   - args: All other arguments.
    /// - Returns: A future that completes with the result of the
    ///   script.
    public func eval(_ script: String, keys: [String] = [], args: [RESPValueConvertible] = []) -> EventLoopFuture<RESPValue> {
        self.command("EVAL", args: [script] + [keys.count] + keys + args)
    }
    
    /// Subscribe to a single channel.
    ///
    /// - Parameters:
    ///   - channel: The name of the channel to subscribe to.
    ///   - messageReciver: The closure to execute when a message
    ///     comes through the given channel.
    /// - Returns: A future that completes when the subscription is
    ///   established.
    public func subscribe(to channel: RedisChannelName, messageReciver: @escaping (RESPValue) -> Void) -> EventLoopFuture<Void> {
        self.subscribe(to: [channel]) { _, value in messageReciver(value) }
    }
}

/// RedisClient conformance. See `RedisClient` for docs.
extension Redis: RedisClient {
    public var eventLoop: EventLoop {
        Loop.current
    }
    
    public func logging(to logger: Logger) -> RedisClient {
        driver.getClient().logging(to: logger)
    }
    
    public func send(command: String, with arguments: [RESPValue]) -> EventLoopFuture<RESPValue> {
        driver.getClient().send(command: command, with: arguments).hop(to: Loop.current)
    }
    
    public func subscribe(
        to channels: [RedisChannelName],
        messageReceiver receiver: @escaping RedisSubscriptionMessageReceiver,
        onSubscribe subscribeHandler: RedisSubscriptionChangeHandler?,
        onUnsubscribe unsubscribeHandler: RedisSubscriptionChangeHandler?
    ) -> EventLoopFuture<Void> {
        driver.getClient()
            .subscribe(
                to: channels,
                messageReceiver: receiver,
                onSubscribe: subscribeHandler,
                onUnsubscribe: unsubscribeHandler
            )
    }

    public func psubscribe(
        to patterns: [String],
        messageReceiver receiver: @escaping RedisSubscriptionMessageReceiver,
        onSubscribe subscribeHandler: RedisSubscriptionChangeHandler?,
        onUnsubscribe unsubscribeHandler: RedisSubscriptionChangeHandler?
    ) -> EventLoopFuture<Void> {
        driver.getClient()
            .psubscribe(
                to: patterns,
                messageReceiver: receiver,
                onSubscribe: subscribeHandler,
                onUnsubscribe: unsubscribeHandler
            )
    }
    
    public func unsubscribe(from channels: [RedisChannelName]) -> EventLoopFuture<Void> {
        driver.getClient().unsubscribe(from: channels)
    }
    
    public func punsubscribe(from patterns: [String]) -> EventLoopFuture<Void> {
        driver.getClient().punsubscribe(from: patterns)
    }
}

extension Redis {
    /// Sends a Redis transaction over a single connection. Wrapper around 
    /// "MULTI" ... "EXEC".
    public func transaction<T>(_ action: @escaping (Redis) -> EventLoopFuture<T>) -> EventLoopFuture<T> {
        driver.leaseConnection { conn in
            conn.send(command: "MULTI")
                .flatMap { _ in action(Redis(connection: conn)) }
                .flatMap { conn.send(command: "EXEC").transform(to: $0) }
        }
    }
}
