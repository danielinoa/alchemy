import ArgumentParser

/// Command to run migrations when launched. This is a subcommand of
/// `Launch`.
struct MigrateCommand<A: Application>: ParsableCommand {
    static var configuration: CommandConfiguration {
        CommandConfiguration(commandName: "migrate")
    }
    
    /// Whether migrations should be run or rolled back. If this is
    /// false (default) then all new migrations will have their
    /// `.up` functions applied to `Database.default`. If this is
    /// true, the last batch will be have their `.down`
    /// functions applied.
    @Flag(help: "Should migrations be rolled back")
    var rollback: Bool = false
    
    /// The environment file to load. Defaults to `env`
    @Option(name: .shortAndLong) var env: String = "env"
    
    // MARK: ParseableCommand
    
    func run() throws {
        Env.defaultLocation = env
        try A().launch(self)
    }
}

extension MigrateCommand: Runner {
    func register(lifecycle: ServiceLifecycle) {
        lifecycle.register(
            label: "Migrate",
            start: .eventLoopFuture { start(lifecycle) },
            shutdown: .none
        )
    }
    
    private func start(_ lifecycle: ServiceLifecycle) -> EventLoopFuture<Void> {
        // Run on event loop
        Loop.group.next()
            .flatSubmit(rollback ? Database.default.rollbackMigrations : Database.default.migrate)
            // Shut down everything when migrations are finished.
            .map {
                let action = rollback ? "migration rollback" : "migrations"
                Log.info("[Migration] \(action) finished, shutting down.")
                lifecycle.shutdown()
            }
    }
}
