import Foundation
import Network

@MainActor
final class NetworkConnectionIO {
    struct Message {
        let content: Data
        let endOfStream: Bool
    }

    private let connection: NWConnection
    private var receiving: CheckedContinuation<Message, Error>?
    private var sending: CheckedContinuation<Void, Error>?
    private var cancelled = false

    init(_ connection: NWConnection) {
        self.connection = connection
        connection.start(queue: .main)
    }

    isolated deinit { cancel() }

    func cancel() {
        cancelled = true
        let receiving = receiving
        let sending = sending
        self.receiving = nil
        self.sending = nil
        connection.cancel()
        receiving?.resume(throwing: CancellationError())
        sending?.resume(throwing: CancellationError())
    }

    func receive(maximumLength: Int) async throws -> Message {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            guard !cancelled else { throw CancellationError() }
            return try await withCheckedThrowingContinuation { continuation in
                receiving = continuation
                connection.receive(
                    minimumIncompleteLength: 1, maximumLength: maximumLength
                ) { [weak self] data, _, complete, error in
                    Task { @MainActor [weak self] in
                        guard let self, let continuation = self.receiving else { return }
                        self.receiving = nil
                        if let error {
                            continuation.resume(throwing: error)
                        } else {
                            continuation.resume(
                                returning: Message(content: data ?? Data(), endOfStream: complete))
                        }
                    }
                }
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancel() }
        }
    }

    func send(_ data: Data) async throws {
        try await withTaskCancellationHandler {
            try Task.checkCancellation()
            guard !cancelled else { throw CancellationError() }
            try await withCheckedThrowingContinuation { continuation in
                sending = continuation
                connection.send(
                    content: data, contentContext: .finalMessage, isComplete: true,
                    completion: .contentProcessed { [weak self] error in
                        Task { @MainActor [weak self] in
                            guard let self, let continuation = self.sending else { return }
                            self.sending = nil
                            if let error {
                                continuation.resume(throwing: error)
                            } else {
                                continuation.resume()
                            }
                        }
                    })
            }
        } onCancel: {
            Task { @MainActor [weak self] in self?.cancel() }
        }
    }
}
