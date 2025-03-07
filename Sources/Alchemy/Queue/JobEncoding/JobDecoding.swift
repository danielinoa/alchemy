/// Storage for `Job` decoding behavior.
struct JobDecoding {
    /// Stored decoding behavior for jobs.
    @Locked private static var decoders: [String: (JobData) throws -> Job] = [:]
    
    /// Register a job to cache its decoding behavior.
    ///
    /// - Parameter type: A job type.
    static func register<J: Job>(_ type: J.Type) {
        self.decoders[J.name] = { try J(jsonString: $0.json) }
    }
    
    /// Indicates if the given type is already registered.
    ///
    /// - Parameter type: A job type.
    /// - Returns: Whether this job type is already registered.
    static func isRegistered<J: Job>(_ type: J.Type) -> Bool {
        decoders[J.name] != nil
    }
    
    /// Decode a job from the given job data.
    ///
    /// - Parameter jobData: The job data to decode.
    /// - Throws: Any errors encountered while decoding the job.
    /// - Returns: The decoded job.
    static func decode(_ jobData: JobData) throws -> Job {
        guard let decoder = JobDecoding.decoders[jobData.jobName] else {
            throw JobError("Unknown job of type '\(jobData.jobName)'. Please register it via `app.registerJob(MyJob.self)`.")
        }
        
        return try decoder(jobData)
    }
}
