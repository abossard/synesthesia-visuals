// Store.swift - Generic Store for unidirectional data flow
// TCA-inspired architecture: Actions → Reducer → State → Effects

import Foundation

/// A store manages application state using unidirectional data flow.
///
/// Key concepts:
/// - **State**: Single immutable snapshot of application data
/// - **Action**: Describes something that happened (user event, system event)
/// - **Reducer**: Pure function (State, Action) → (State, Effect)
/// - **Effect**: Async operations that can dispatch new actions
///
/// Thread safety: The store is isolated to `@MainActor` for UI integration.
@MainActor
public final class Store<State, Action: Sendable>: ObservableObject {

    // MARK: - Published State

    /// Current state snapshot. SwiftUI views observe this automatically.
    @Published public private(set) var state: State

    // MARK: - Private

    private let reducer: (inout State, Action) -> Effect<Action>
    private var effectTasks: [UUID: Task<Void, Never>] = [:]
    private var effectCancellables: [AnyHashable: UUID] = [:]

    // MARK: - Init

    /// Create a store with initial state and reducer.
    ///
    /// - Parameters:
    ///   - initialState: The starting state
    ///   - reducer: Pure function that processes actions and returns effects
    public init(
        initialState: State,
        reducer: @escaping (inout State, Action) -> Effect<Action>
    ) {
        self.state = initialState
        self.reducer = reducer
    }

    // MARK: - Public API

    /// Send an action to the store.
    ///
    /// The reducer processes the action synchronously, updating state.
    /// Any effects returned by the reducer are executed asynchronously.
    ///
    /// - Parameter action: The action to process
    public func send(_ action: Action) {
        let effect = reducer(&state, action)
        executeEffect(effect)
    }

    /// Send multiple actions in sequence.
    ///
    /// - Parameter actions: Actions to process in order
    public func send(_ actions: [Action]) {
        for action in actions {
            send(action)
        }
    }

    /// Cancel all running effects.
    public func cancelAllEffects() {
        for (_, task) in effectTasks {
            task.cancel()
        }
        effectTasks.removeAll()
        effectCancellables.removeAll()
    }

    /// Cancel effects with a specific ID.
    ///
    /// - Parameter id: The cancellation ID
    public func cancelEffect(id: AnyHashable) {
        if let taskId = effectCancellables[id] {
            effectTasks[taskId]?.cancel()
            effectTasks.removeValue(forKey: taskId)
            effectCancellables.removeValue(forKey: id)
        }
    }

    // MARK: - Private

    private func executeEffect(_ effect: Effect<Action>) {
        switch effect.operation {
        case .none:
            break

        case .run(let priority, let operation, let cancellationId):
            let taskId = UUID()

            // Track cancellation ID if provided
            if let cancellationId = cancellationId {
                // Cancel any existing effect with this ID
                cancelEffect(id: cancellationId)
                effectCancellables[cancellationId] = taskId
            }

            let task = Task(priority: priority) { [weak self] in
                guard let self = self else { return }

                await operation(Send { [weak self] action in
                    guard let self = self else { return }
                    await MainActor.run {
                        self.send(action)
                    }
                })

                // Cleanup
                await MainActor.run { [weak self] in
                    self?.effectTasks.removeValue(forKey: taskId)
                    if let cancellationId = cancellationId {
                        self?.effectCancellables.removeValue(forKey: cancellationId)
                    }
                }
            }

            effectTasks[taskId] = task

        case .merge(let effects):
            for effect in effects {
                executeEffect(effect)
            }

        case .concatenate(let effects):
            executeConcatenatedEffects(effects)
        }
    }

    private func executeConcatenatedEffects(_ effects: [Effect<Action>]) {
        guard !effects.isEmpty else { return }

        Task { [weak self] in
            for effect in effects {
                guard !Task.isCancelled else { break }
                await self?.executeEffectAndWait(effect)
            }
        }
    }

    private func executeEffectAndWait(_ effect: Effect<Action>) async {
        switch effect.operation {
        case .none:
            break

        case .run(let priority, let operation, _):
            await withTaskPriority(priority) {
                await operation(Send { [weak self] action in
                    guard let self = self else { return }
                    await MainActor.run {
                        self.send(action)
                    }
                })
            }

        case .merge(let effects):
            await withTaskGroup(of: Void.self) { group in
                for effect in effects {
                    group.addTask { [weak self] in
                        await self?.executeEffectAndWait(effect)
                    }
                }
            }

        case .concatenate(let effects):
            for effect in effects {
                await executeEffectAndWait(effect)
            }
        }
    }

    private func withTaskPriority(_ priority: TaskPriority?, operation: @escaping () async -> Void) async {
        if let priority = priority {
            await Task(priority: priority) {
                await operation()
            }.value
        } else {
            await operation()
        }
    }
}

// MARK: - Send (Action Dispatcher)

/// A send function used by effects to dispatch actions back to the store.
public struct Send<Action: Sendable>: Sendable {
    private let send: @Sendable (Action) async -> Void

    public init(send: @escaping @Sendable (Action) async -> Void) {
        self.send = send
    }

    /// Dispatch an action to the store.
    ///
    /// - Parameter action: The action to dispatch
    public func callAsFunction(_ action: Action) async {
        await send(action)
    }
}

// MARK: - Scoped Store

extension Store {
    /// Create a derived store that focuses on a subset of state.
    ///
    /// Useful for passing to child views that only need part of the state.
    ///
    /// - Parameters:
    ///   - toChildState: Extract child state from parent state
    ///   - fromChildAction: Embed child action in parent action
    /// - Returns: A new store scoped to child state/action
    public func scope<ChildState, ChildAction: Sendable>(
        state toChildState: @escaping (State) -> ChildState,
        action fromChildAction: @escaping (ChildAction) -> Action
    ) -> Store<ChildState, ChildAction> {
        let childStore = Store<ChildState, ChildAction>(
            initialState: toChildState(state),
            reducer: { [weak self] _, childAction in
                guard let self = self else { return .none }
                let parentAction = fromChildAction(childAction)
                self.send(parentAction)
                return .none
            }
        )

        // Keep child state in sync with parent
        // Note: In production, use Combine publisher for proper observation
        return childStore
    }
}

// MARK: - ViewStore (for SwiftUI integration)

/// A lightweight store view for SwiftUI that avoids unnecessary re-renders.
@MainActor
public final class ViewStore<State: Equatable, Action: Sendable>: ObservableObject {
    @Published public private(set) var state: State

    private let store: Store<State, Action>
    private var observation: Task<Void, Never>?

    public init(store: Store<State, Action>) {
        self.store = store
        self.state = store.state

        // Observe store changes
        observation = Task { }
    }

    deinit {
        observation?.cancel()
    }

    public func send(_ action: Action) {
        store.send(action)
        state = store.state
    }
}
