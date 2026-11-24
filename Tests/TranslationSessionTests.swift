import Foundation

@main
@MainActor
struct TranslationSessionTests {
    static let source = Locale.Language(identifier: "en")
    static let target = Locale.Language(identifier: "fr")

    static func main() async {
        let session = TextTranslator.Session()
        let cancelled = Task { try await session.translate("Hello", from: source, to: target) }
        cancelled.cancel()
        await expectCancellation(cancelled)
        precondition(session.request == nil)

        let first = Task { try await session.translate("First", from: source, to: target) }
        let firstID = await pendingID(session)
        session.cancel()
        session.cancel()
        await expectCancellation(first)
        precondition(session.request == nil)

        let old = Task { try await session.translate("Old", from: source, to: target) }
        let oldID = await pendingID(session)
        let replacement = Task { try await session.translate("New", from: source, to: target) }
        for _ in 0..<100 where session.request?.id == oldID { await Task.yield() }
        guard let replacementID = session.request?.id else {
            preconditionFailure("the replacement request must remain pending")
        }
        precondition(replacementID != oldID && replacementID != firstID)
        await expectCancellation(old)
        old.cancel()
        await Task.yield()
        precondition(session.request?.id == replacementID,
                     "a stale cancellation must not cancel the replacement")
        session.cancel()
        await expectCancellation(replacement)
        precondition(session.request == nil)
        print("Translation session cancellation passed; no language assets or model required")
    }

    static func pendingID(_ session: TextTranslator.Session) async -> UUID {
        for _ in 0..<100 where session.request == nil { await Task.yield() }
        guard let id = session.request?.id else { preconditionFailure("request did not register") }
        return id
    }

    static func expectCancellation(_ task: Task<String, any Error>) async {
        do {
            _ = try await task.value
            preconditionFailure("a cancelled translation must not produce text")
        } catch is CancellationError {
        } catch {
            preconditionFailure("unexpected translation failure: \(error)")
        }
    }
}
