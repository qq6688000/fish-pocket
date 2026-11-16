import Combine
import Foundation

/// ObservableObject sends before mutation. Deliver on the main queue so snapshots read
/// the committed values, and discard queued deliveries after an engine is replaced.
@MainActor
final class ModelChanges {
    private var subscriptions: [AnyCancellable] = []
    private var generation = 0

    func attach(to app: AppModel, remoteOnly: Bool = false, changed: @escaping @MainActor () -> Void) {
        generation += 1
        let token = generation
        subscriptions.removeAll()
        var publishers = [app.remote.objectWillChange.eraseToAnyPublisher()]
        if !remoteOnly {
            publishers.append(app.objectWillChange.eraseToAnyPublisher())
            publishers.append(app.account.objectWillChange.eraseToAnyPublisher())
        }
        subscriptions = publishers.map { publisher in
            publisher.sink { [weak self] _ in
                Task { @MainActor [weak self] in
                    guard let self, self.generation == token else { return }
                    changed()
                }
            }
        }
        changed()
    }
}
