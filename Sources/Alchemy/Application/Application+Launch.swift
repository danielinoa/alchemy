import Lifecycle
import LifecycleNIOCompat

extension Application {
    /// Lifecycle logs quite a bit by default, this quiets it's `info`
    /// level logs by default. To output messages lower than `notice`,
    /// you can override this property to `.info` or lower.
    public var lifecycleLogLevel: Logger.Level { .notice }
    
    /// Launch this application. By default it serves, see `Launch`
    /// for subcommands and options. Call this in the `main.swift`
    /// of your project.
    public static func main() {
        Launch<Self>.main()
    }
    
    /// Launch the application with the provided runner. It will setup
    /// core services, call `self.setup()`, and then it's behavior
    /// will be defined by the runner.
    ///
    /// - Parameter runner: The runner that defines what the
    ///   application does when it's launched.
    /// - Throws: Any error that may be encountered in booting the
    ///   application.
    func launch(_ runner: Runner) throws {
        // Create and register app lifecycle
        var lifecycleLogger = Log.logger
        lifecycleLogger.logLevel = lifecycleLogLevel
        let lifecycle = ServiceLifecycle(
            configuration: ServiceLifecycle.Configuration(
                logger: lifecycleLogger,
                installBacktrace: true
            )
        )
        
        ServiceLifecycle.config(default: lifecycle)
        
        // Boot default services
        bootServices()
        
        // Boot the app
        try boot()
        
        // Register the runner
        runner.register(lifecycle: lifecycle)
        
        // Start the lifecycle
        try lifecycle.startAndWait()
    }
}
