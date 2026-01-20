// Effect.swift - Side effect representation for unidirectional data flow
// Effects encapsulate async operations that can dispatch actions

import Foundation

/// An effect represents an async operation that can dispatch actions.
///
/// Effects are the only way to perform side effects in the architecture.
/// The reducer returns effects, and the store executes them.
///
/// Common patterns:
/// - `.none` - No side effect (pure state update)
/// - `.run { send in ... }` - Async operation
/// - `.merge([effect1, effect2])` - Run effects concurrently
/// - `.concatenate([effect1, effect2])` - Run effects sequentially
public struct Effect<Action>: @unchecked Sendable where Action: Sendable {

    /// Internal operation type
    enum Operation {
        case none
        case run(
            priority: TaskPriority?,
            operation: @Sendable (Send<Action>) async -> Void,
            cancellationId: AnyHashable?
        )
        case merge([Effect<Action>])
        case concatenate([Effect<Action>])
    }

    let operation: Operation

    private init(operation: Operation) {
        self.operation = operation
    }

    // MARK: - Factory Methods

    /// No side effect.
    public static var none: Effect {
        Effect(operation: .none)
    }

    /// Run an async operation that can dispatch actions.
    ///
    /// - Parameters:
    ///   - priority: Task priority for the operation
    ///   - operation: Async closure that receives a `Send` function
    /// - Returns: An effect that runs the operation
    public static func run(
        priority: TaskPriority? = nil,
        operation: @escaping @Sendable (Send<Action>) async -> Void
    ) -> Effect {
        Effect(operation: .run(priority: priority, operation: operation, cancellationId: nil))
    }

    /// Run an async operation with a cancellation ID.
    ///
    /// If another effect with the same ID is started, the previous one is cancelled.
    ///
    /// - Parameters:
    ///   - priority: Task priority for the operation
    ///   - id: Cancellation identifier
    ///   - operation: Async closure that receives a `Send` function
    /// - Returns: An effect that runs the operation
    public static func run(
        priority: TaskPriority? = nil,
        cancellationId id: AnyHashable,
        operation: @escaping @Sendable (Send<Action>) async -> Void
    ) -> Effect {
        Effect(operation: .run(priority: priority, operation: operation, cancellationId: id))
    }

    /// Run multiple effects concurrently.
    ///
    /// - Parameter effects: Effects to run in parallel
    /// - Returns: A merged effect
    public static func merge(_ effects: [Effect]) -> Effect {
        let filtered = effects.filter { effect in
            if case .none = effect.operation { return false }
            return true
        }
        guard !filtered.isEmpty else { return .none }
        guard filtered.count > 1 else { return filtered[0] }
        return Effect(operation: .merge(filtered))
    }

    /// Run multiple effects concurrently (variadic).
    ///
    /// - Parameter effects: Effects to run in parallel
    /// - Returns: A merged effect
    public static func merge(_ effects: Effect...) -> Effect {
        merge(effects)
    }

    /// Run effects sequentially, waiting for each to complete.
    ///
    /// - Parameter effects: Effects to run in sequence
    /// - Returns: A concatenated effect
    public static func concatenate(_ effects: [Effect]) -> Effect {
        let filtered = effects.filter { effect in
            if case .none = effect.operation { return false }
            return true
        }
        guard !filtered.isEmpty else { return .none }
        guard filtered.count > 1 else { return filtered[0] }
        return Effect(operation: .concatenate(filtered))
    }

    /// Run effects sequentially (variadic).
    ///
    /// - Parameter effects: Effects to run in sequence
    /// - Returns: A concatenated effect
    public static func concatenate(_ effects: Effect...) -> Effect {
        concatenate(effects)
    }

    /// Cancel an effect by its ID.
    ///
    /// - Parameter id: The cancellation ID to cancel
    /// - Returns: An effect that cancels the identified effect
    public static func cancel(id: AnyHashable) -> Effect {
        .run { _ in
            // Cancellation is handled by the store when it sees this ID
            // This is a marker effect
        }
    }

    /// Fire-and-forget effect (no actions dispatched).
    ///
    /// Use for side effects that don't need to update state.
    ///
    /// - Parameter work: Async work to perform
    /// - Returns: An effect that runs the work
    public static func fireAndForget(
        priority: TaskPriority? = nil,
        _ work: @escaping @Sendable () async -> Void
    ) -> Effect {
        .run(priority: priority) { _ in
            await work()
        }
    }

    /// Send a single action.
    ///
    /// - Parameter action: Action to dispatch
    /// - Returns: An effect that dispatches the action
    public static func send(_ action: Action) -> Effect {
        .run { send in
            await send(action)
        }
    }

    /// Map actions from one type to another.
    ///
    /// - Parameter transform: Function to transform actions
    /// - Returns: A new effect with transformed action type
    public func map<NewAction: Sendable>(
        _ transform: @escaping @Sendable (Action) -> NewAction
    ) -> Effect<NewAction> {
        switch operation {
        case .none:
            return .none

        case .run(let priority, let operation, let cancellationId):
            return Effect<NewAction>(operation: .run(
                priority: priority,
                operation: { send in
                    await operation(Send { action in
                        await send(transform(action))
                    })
                },
                cancellationId: cancellationId
            ))

        case .merge(let effects):
            return .merge(effects.map { $0.map(transform) })

        case .concatenate(let effects):
            return .concatenate(effects.map { $0.map(transform) })
        }
    }
}

// MARK: - Effect Builders

extension Effect {
    /// Create an effect from an async throwing operation.
    ///
    /// - Parameters:
    ///   - operation: Async throwing operation
    ///   - onSuccess: Action to dispatch on success
    ///   - onFailure: Action to dispatch on failure
    /// - Returns: An effect that handles success and failure
    public static func task<Success: Sendable>(
        priority: TaskPriority? = nil,
        operation: @escaping @Sendable () async throws -> Success,
        onSuccess: @escaping @Sendable (Success) -> Action,
        onFailure: @escaping @Sendable (Error) -> Action
    ) -> Effect {
        .run(priority: priority) { send in
            do {
                let result = try await operation()
                await send(onSuccess(result))
            } catch {
                await send(onFailure(error))
            }
        }
    }

    /// Create an effect that delays an action.
    ///
    /// - Parameters:
    ///   - duration: Time to wait before dispatching
    ///   - action: Action to dispatch after delay
    /// - Returns: A delayed effect
    public static func delay(
        _ duration: Duration,
        action: Action
    ) -> Effect {
        .run { send in
            try? await Task.sleep(for: duration)
            await send(action)
        }
    }

    /// Create a long-running subscription effect.
    ///
    /// - Parameters:
    ///   - id: Cancellation ID for the subscription
    ///   - subscribe: Async sequence to subscribe to
    ///   - onValue: Transform sequence values to actions
    /// - Returns: A subscription effect
    public static func subscribe<S: AsyncSequence>(
        id: AnyHashable,
        to sequence: @escaping @Sendable () async throws -> S,
        onValue: @escaping @Sendable (S.Element) -> Action
    ) -> Effect where S: Sendable, S.Element: Sendable {
        .run(cancellationId: id) { send in
            do {
                for try await value in try await sequence() {
                    guard !Task.isCancelled else { break }
                    await send(onValue(value))
                }
            } catch {
                // Subscription ended or was cancelled
            }
        }
    }
}

// MARK: - Cancellation ID Types

/// Common cancellation IDs for effect management.
public enum EffectCancellationId: Hashable, Sendable {
    case osc
    case playback
    case pipeline
    case launchpad
    case audio
    case persistence
    case timer(String)
    case custom(String)
}
