import Foundation

internal import CxxStdlib
internal import StatsigCpp

/// Errors surfaced by the throwing `Statsig` APIs.
///
/// Use the `...Result` variants (for example, ``Statsig/checkGateResult(user:gate:)``)
/// or the non-throwing convenience overloads if you prefer to avoid throws.
public enum StatsigError: Error, CustomStringConvertible {
    case message(String)

    public var description: String {
        switch self {
        case let .message(message):
            return message
        }
    }
}

/// Configuration for the server-side Statsig SDK.
///
/// - Important: The default polling interval refreshes rules approximately every
///   10 seconds via a background thread.
public struct StatsigOptions: Sendable {
    /// Base URL for the Statsig API.
    public var api: String
    /// When `true`, disables network sync and event logging.
    public var localMode: Bool
    /// Background polling interval for downloading updated rulesets, in milliseconds.
    public var rulesetsSyncIntervalMs: Int
    /// Background flush interval for event logging, in milliseconds.
    public var loggingIntervalMs: Int
    /// Maximum buffered events before a forced flush.
    public var loggingMaxBufferSize: Int

    /// Creates SDK options with sensible server-side defaults.
    ///
    /// Defaults:
    /// - `rulesetsSyncIntervalMs`: `10_000`
    /// - `loggingIntervalMs`: `60_000`
    /// - `loggingMaxBufferSize`: `1_000`
    public init(
        api: String = "",
        localMode: Bool = false,
        rulesetsSyncIntervalMs: Int = 10000,
        loggingIntervalMs: Int = 60000,
        loggingMaxBufferSize: Int = 1000
    ) {
        self.api = api
        self.localMode = localMode
        self.rulesetsSyncIntervalMs = rulesetsSyncIntervalMs
        self.loggingIntervalMs = loggingIntervalMs
        self.loggingMaxBufferSize = loggingMaxBufferSize
    }
}

/// A user (or evaluation unit) to evaluate gates and configs against.
///
/// - Important: `userID` is used for deterministic bucketing. Use a stable,
///   non-empty identifier when you want sticky rollouts. If `userID` is empty,
///   all empty users will bucket the same way.
public struct StatsigUser: Codable {
    /// Stable identifier for bucketing and targeting.
    public var userID: String
    public var email: String?
    public var ipAddress: String?
    public var userAgent: String?
    public var country: String?
    public var locale: String?
    public var appVersion: String?
    public var custom: [String: String]?
    public var privateAttribute: [String: String]?
    public var statsigEnvironment: [String: String]?
    public var customIDs: [String: String]?

    public init(userID: String) {
        self.userID = userID
    }
}

public extension StatsigUser {
    /// Creates a user with a random UUID user ID.
    ///
    /// Use this for anonymous evaluations where a stable identifier is not available.
    static func random() -> StatsigUser {
        StatsigUser(userID: UUID().uuidString)
    }
}

/// A dynamic config / experiment / layer payload with typed accessors.
///
/// The underlying SDK returns JSON containing `name`, `value`, and `ruleID`.
/// This wrapper extracts the `value` object and provides iOS-style getters.
public struct StatsigConfig {
    /// Raw JSON returned by the underlying SDK.
    public let rawJSON: String
    private let values: [String: Any]
    private struct Envelope<T: Decodable>: Decodable {
        let value: T
    }

    init(jsonString: String) {
        self.rawJSON = jsonString
        self.values = StatsigConfig.parseValues(from: jsonString)
    }

    private static func parseValues(from jsonString: String) -> [String: Any] {
        guard let data = jsonString.data(using: .utf8) else {
            return [:]
        }
        guard
            let root = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
            let value = root["value"] as? [String: Any]
        else {
            return [:]
        }
        return value
    }

    /// Returns the string value for `key`, or `defaultValue` if missing or mismatched.
    public func getValue(forKey key: String, defaultValue: String) -> String {
        values[key] as? String ?? defaultValue
    }

    /// Returns the bool value for `key`, or `defaultValue` if missing or mismatched.
    public func getValue(forKey key: String, defaultValue: Bool) -> Bool {
        if let boolValue = values[key] as? Bool {
            return boolValue
        }
        if let number = values[key] as? NSNumber {
            return number.boolValue
        }
        return defaultValue
    }

    /// Returns the integer value for `key`, or `defaultValue` if missing or mismatched.
    public func getValue(forKey key: String, defaultValue: Int) -> Int {
        if let intValue = values[key] as? Int {
            return intValue
        }
        if let number = values[key] as? NSNumber {
            return number.intValue
        }
        return defaultValue
    }

    /// Returns the double value for `key`, or `defaultValue` if missing or mismatched.
    public func getValue(forKey key: String, defaultValue: Double) -> Double {
        if let doubleValue = values[key] as? Double {
            return doubleValue
        }
        if let number = values[key] as? NSNumber {
            return number.doubleValue
        }
        return defaultValue
    }

    /// Decodes the config's `value` payload into a `Decodable` type.
    ///
    /// The decoder only sees the `value` object, not the outer envelope.
    public func decodeValue<T: Decodable>(
        as type: T.Type,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> T {
        guard let data = rawJSON.data(using: .utf8) else {
            throw StatsigError.message("Config JSON is not valid UTF-8")
        }
        do {
            return try decoder.decode(Envelope<T>.self, from: data).value
        } catch {
            throw StatsigError.message("Failed to decode config value: \(error)")
        }
    }
}

/// A gate evaluation with resolution status.
///
/// Use this when you want iOS-style behavior (no throws) while still
/// distinguishing errors from legitimate `false` results.
public struct StatsigGateResult {
    /// The evaluated gate value. Defaults to `false` when unresolved.
    public let value: Bool
    /// `true` when the SDK returned a value successfully.
    public let isResolved: Bool
    /// The underlying error when `isResolved == false`.
    public let error: StatsigError?
}

/// A config evaluation with resolution status.
public struct StatsigConfigResult {
    /// The evaluated config. Empty when unresolved.
    public let config: StatsigConfig
    /// `true` when the SDK returned a value successfully.
    public let isResolved: Bool
    /// The underlying error when `isResolved == false`.
    public let error: StatsigError?
}

/// Server-side Statsig entry points with explicit users per evaluation.
public enum Statsig {
    /// Returns `true` after successful initialization.
    public static func isInitialized() -> Bool {
        statsig.swift.isInitialized()
    }

    /// Initializes the SDK with a server secret key.
    ///
    /// This triggers an immediate ruleset fetch and starts background polling
    /// (default ~10 seconds) unless `localMode` is enabled via options.
    ///
    /// - Parameter sdkKey: Your Statsig server secret key.
    /// - Throws: ``StatsigError`` when initialization fails.
    public static func initialize(sdkKey: String) throws {
        let result = statsig.swift.initialize(std.string(sdkKey))
        if !result.ok {
            throw StatsigError.message(String(result.error))
        }
    }

    /// Initializes the SDK with explicit options.
    ///
    /// - Parameters:
    ///   - sdkKey: Your Statsig server secret key.
    ///   - options: SDK options controlling polling and logging behavior.
    /// - Throws: ``StatsigError`` when initialization fails.
    public static func initialize(sdkKey: String, options: StatsigOptions) throws {
        let result = statsig.swift.initializeWithOptions(
            std.string(sdkKey),
            std.string(options.api),
            options.localMode,
            Int32(options.rulesetsSyncIntervalMs),
            Int32(options.loggingIntervalMs),
            Int32(options.loggingMaxBufferSize)
        )
        if !result.ok {
            throw StatsigError.message(String(result.error))
        }
    }

    /// Shuts down background threads and flushes any buffered events.
    ///
    /// After calling this, you must re-initialize before evaluating again.
    /// - Throws: ``StatsigError`` when shutdown fails.
    public static func shutdown() throws {
        let result = statsig.swift.shutdown()
        if !result.ok {
            throw StatsigError.message(String(result.error))
        }
    }

    /// Evaluates a gate using a JSON-encoded user.
    ///
    /// Prefer ``checkGate(user:gate:)`` unless you already have validated user JSON.
    /// - Throws: ``StatsigError`` when user parsing or evaluation fails.
    public static func checkGate(userJSON: String, gate: String) throws -> Bool {
        let result = statsig.swift.checkGateJson(std.string(userJSON), std.string(gate))
        if !result.ok {
            throw StatsigError.message(String(result.error))
        }
        return result.value
    }

    /// iOS-style convenience that never throws.
    ///
    /// - Important: This logs a gate exposure on every call.
    /// - Returns: `false` when evaluation fails.
    public static func checkGate(_ gate: String, user: StatsigUser) -> Bool {
        (try? checkGate(user: user, gate: gate)) ?? false
    }

    /// Evaluates a gate and reports whether the result resolved successfully.
    public static func checkGateResult(user: StatsigUser, gate: String) -> StatsigGateResult {
        do {
            let value = try checkGate(user: user, gate: gate)
            return StatsigGateResult(value: value, isResolved: true, error: nil)
        } catch let err as StatsigError {
            return StatsigGateResult(value: false, isResolved: false, error: err)
        } catch {
            return StatsigGateResult(value: false, isResolved: false, error: .message("\(error)"))
        }
    }

    /// Evaluates a gate and returns `defaultValue` when evaluation fails.
    ///
    /// This is useful when a feature must have a deterministic fallback even if the
    /// SDK cannot resolve the gate (e.g., during startup or when the ruleset is unavailable).
    ///
    /// - Important: This logs a gate exposure on every call.
    public static func checkGate(
        user: StatsigUser,
        gate: String,
        defaultValue: Bool
    ) -> Bool {
        let result = checkGateResult(user: user, gate: gate)
        return result.isResolved ? result.value : defaultValue
    }

    /// Evaluates a gate for a specific user.
    ///
    /// - Important: This logs a gate exposure on every call.
    /// - Throws: ``StatsigError`` when evaluation fails.
    public static func checkGate(user: StatsigUser, gate: String) throws -> Bool {
        return try checkGate(userJSON: encodeUser(user), gate: gate)
    }

    /// Gets a config as raw JSON using a JSON-encoded user.
    /// - Throws: ``StatsigError`` when user parsing or evaluation fails.
    public static func getConfigJSON(userJSON: String, configName: String) throws -> String {
        let result = statsig.swift.getConfigJson(std.string(userJSON), std.string(configName))
        if !result.ok {
            throw StatsigError.message(String(result.error))
        }
        return String(result.value)
    }

    /// Gets a config for a specific user.
    ///
    /// - Important: This logs a config exposure on every call.
    /// - Throws: ``StatsigError`` when evaluation fails.
    public static func getConfig(user: StatsigUser, configName: String) throws -> StatsigConfig {
        let json = try getConfigJSON(user: user, configName: configName)
        return StatsigConfig(jsonString: json)
    }

    /// Gets a config and decodes its `value` into a `Decodable` type.
    public static func getConfig<T: Decodable>(
        user: StatsigUser,
        configName: String,
        as type: T.Type,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> T {
        let config = try getConfig(user: user, configName: configName)
        return try config.decodeValue(as: type, decoder: decoder)
    }

    /// iOS-style convenience that never throws.
    ///
    /// - Important: This logs a config exposure on every call.
    /// - Returns: An empty config when evaluation fails.
    public static func getConfig(_ configName: String, user: StatsigUser) -> StatsigConfig {
        (try? getConfig(user: user, configName: configName)) ?? emptyConfig()
    }

    /// Gets a config and reports whether the result resolved successfully.
    public static func getConfigResult(user: StatsigUser, configName: String) -> StatsigConfigResult {
        do {
            let config = try getConfig(user: user, configName: configName)
            return StatsigConfigResult(config: config, isResolved: true, error: nil)
        } catch let err as StatsigError {
            return StatsigConfigResult(config: emptyConfig(), isResolved: false, error: err)
        } catch {
            return StatsigConfigResult(
                config: emptyConfig(),
                isResolved: false,
                error: .message("\(error)")
            )
        }
    }

    /// Gets a config as raw JSON for a specific user.
    public static func getConfigJSON(user: StatsigUser, configName: String) throws -> String {
        return try getConfigJSON(userJSON: encodeUser(user), configName: configName)
    }

    /// Gets an experiment as raw JSON using a JSON-encoded user.
    public static func getExperimentJSON(userJSON: String, experimentName: String) throws -> String {
        let result = statsig.swift.getExperimentJson(std.string(userJSON), std.string(experimentName))
        if !result.ok {
            throw StatsigError.message(String(result.error))
        }
        return String(result.value)
    }

    /// Gets an experiment for a specific user.
    ///
    /// - Important: This logs an experiment/config exposure on every call.
    public static func getExperiment(user: StatsigUser, experimentName: String) throws -> StatsigConfig {
        let json = try getExperimentJSON(user: user, experimentName: experimentName)
        return StatsigConfig(jsonString: json)
    }

    /// Gets an experiment and decodes its `value` into a `Decodable` type.
    public static func getExperiment<T: Decodable>(
        user: StatsigUser,
        experimentName: String,
        as type: T.Type,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> T {
        let config = try getExperiment(user: user, experimentName: experimentName)
        return try config.decodeValue(as: type, decoder: decoder)
    }

    /// iOS-style convenience that never throws.
    /// - Returns: An empty config when evaluation fails.
    public static func getExperiment(_ experimentName: String, user: StatsigUser) -> StatsigConfig {
        (try? getExperiment(user: user, experimentName: experimentName)) ?? emptyConfig()
    }

    /// Gets an experiment as raw JSON for a specific user.
    public static func getExperimentJSON(user: StatsigUser, experimentName: String) throws -> String {
        return try getExperimentJSON(userJSON: encodeUser(user), experimentName: experimentName)
    }

    /// Gets a layer as raw JSON using a JSON-encoded user.
    public static func getLayerJSON(userJSON: String, layerName: String) throws -> String {
        let result = statsig.swift.getLayerJson(std.string(userJSON), std.string(layerName))
        if !result.ok {
            throw StatsigError.message(String(result.error))
        }
        return String(result.value)
    }

    /// Gets a layer for a specific user.
    ///
    /// - Important: Layer exposures are logged when parameters are accessed in the
    ///   underlying SDK. Accessing the layer still evaluates and records metadata.
    public static func getLayer(user: StatsigUser, layerName: String) throws -> StatsigConfig {
        let json = try getLayerJSON(user: user, layerName: layerName)
        return StatsigConfig(jsonString: json)
    }

    /// Gets a layer and decodes its `value` into a `Decodable` type.
    public static func getLayer<T: Decodable>(
        user: StatsigUser,
        layerName: String,
        as type: T.Type,
        decoder: JSONDecoder = JSONDecoder()
    ) throws -> T {
        let config = try getLayer(user: user, layerName: layerName)
        return try config.decodeValue(as: type, decoder: decoder)
    }

    /// iOS-style convenience that never throws.
    /// - Returns: An empty config when evaluation fails.
    public static func getLayer(_ layerName: String, user: StatsigUser) -> StatsigConfig {
        (try? getLayer(user: user, layerName: layerName)) ?? emptyConfig()
    }

    /// Gets a layer as raw JSON for a specific user.
    public static func getLayerJSON(user: StatsigUser, layerName: String) throws -> String {
        return try getLayerJSON(userJSON: encodeUser(user), layerName: layerName)
    }

    /// Logs a custom event using a JSON-encoded user.
    public static func logEvent(userJSON: String, eventName: String) throws {
        let result = statsig.swift.logEventJson(std.string(userJSON), std.string(eventName))
        if !result.ok {
            throw StatsigError.message(String(result.error))
        }
    }

    /// Logs a custom event for a specific user.
    public static func logEvent(user: StatsigUser, eventName: String) throws {
        try logEvent(userJSON: encodeUser(user), eventName: eventName)
    }

    /// iOS-style convenience that never throws.
    /// - Note: Errors are swallowed by design. Use the throwing overload if needed.
    public static func logEvent(withName eventName: String, user: StatsigUser) {
        try? logEvent(user: user, eventName: eventName)
    }

    private static func encodeUser(_ user: StatsigUser) throws -> String {
        let encoder = JSONEncoder()
        let data = try encoder.encode(user)
        guard let json = String(data: data, encoding: .utf8) else {
            throw StatsigError.message("Failed to encode user JSON")
        }
        return json
    }

    private static func emptyConfig() -> StatsigConfig {
        StatsigConfig(jsonString: "{}")
    }
}
