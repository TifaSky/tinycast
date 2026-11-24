import Foundation
import NaturalLanguage
import Observation
import SwiftUI
import Translation

enum TextTranslator {
    enum Failure: LocalizedError, Equatable {
        case undetectableSource
        case unsupported
        case notInstalled(language: String)
        case failed

        var errorDescription: String? {
            switch self {
            case .undetectableSource:
                return String(localized: "The language of the selected text could not be identified.")
            case .unsupported:
                return String(localized: "Apple's translator does not support this language pair.")
            case .notInstalled(let language):
                return String(localized: "\(language) needs to be downloaded before it can be used.")
            case .failed:
                return String(localized: "The text could not be translated.")
            }
        }
    }

    private static let readerLanguageOdds = 20.0

    /// `TranslationSession(installedSource:)` needs a language; availability reports only a status.
    private static func sourceLanguage(of text: String) -> Locale.Language? {
        let recognizer = NLLanguageRecognizer()
        recognizer.processString(text)
        let readerLanguages = SystemLanguages.preferred.map(Locale.Language.init(identifier:))
        let weighted = recognizer.languageHypotheses(withMaximum: .max)
            .filter { $0.key != .undetermined }
            .map { code, probability in
                let language = Locale.Language(identifier: code.rawValue)
                let isReaders = readerLanguages.contains { isSameLanguage($0, language) }
                let odds = isReaders ? readerLanguageOdds : 1
                return (language: language, weight: probability * odds)
            }
        return weighted.max { $0.weight < $1.weight }?.language
    }

    /// Installed pairs only: a missing language is downloaded in System Settings, never from here.
    static func translate(
        _ text: String, to target: Locale.Language, using session: Session
    ) async throws -> String {
        try Task.checkCancellation()
        guard let source = sourceLanguage(of: text) else { throw Failure.undetectableSource }
        guard !isSameLanguage(source, target) else { return text }
        let availability = LanguageAvailability()
        switch await availability.status(from: source, to: target) {
        case .installed:
            return try await translate(text, from: source, to: target, using: session)
        case .supported:
            break
        case .unsupported:
            throw Failure.unsupported
        @unknown default:
            throw Failure.unsupported
        }
        let supported = await availability.supportedLanguages
        let sources = variants(of: source, among: supported)
        let targets = variants(of: target, among: supported)
        if let pair = await installedPair(sources, targets, availability) {
            return try await translate(text, from: pair.source, to: pair.target, using: session)
        }
        // Every source spelling already failed, so only a third language can prove the target.
        let partners = supported.filter {
            $0.languageCode != source.languageCode && $0.languageCode != target.languageCode
        }
        let targetIsInstalled = await installedPair(partners, targets, availability) != nil
        throw Failure.notInstalled(language: displayName(of: targetIsInstalled ? source : target))
    }

    private static func translate(
        _ text: String, from source: Locale.Language, to target: Locale.Language, using session: Session
    ) async throws -> String {
        do {
            try Task.checkCancellation()
            let translated: String
            if #available(macOS 26.0, *) {
                let session = TranslationSession(installedSource: source, target: target)
                translated = try await session.translate(text).targetText
            } else {
                translated = try await session.translate(text, from: source, to: target)
            }
            try Task.checkCancellation()
            return translated
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            try Task.checkCancellation()
            throw Failure.failed
        }
    }

    /// macOS 15 lends a session only while its SwiftUI task remains in the hosted hierarchy.
    @MainActor
    @Observable
    final class Session {
        struct Request {
            let id = UUID()
            let text: String
            let configuration: TranslationSession.Configuration
        }

        private(set) var request: Request?
        @ObservationIgnored private var continuation: CheckedContinuation<String, any Error>?

        func translate(
            _ text: String, from source: Locale.Language, to target: Locale.Language
        ) async throws -> String {
            try Task.checkCancellation()
            cancel()
            let request = Request(
                text: text, configuration: .init(source: source, target: target))
            let id = request.id
            return try await withTaskCancellationHandler {
                try await withCheckedThrowingContinuation { continuation in
                    guard !Task.isCancelled else {
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    self.continuation = continuation
                    self.request = request
                }
            } onCancel: {
                Task { @MainActor in self.finish(id, with: .failure(CancellationError())) }
            }
        }

        func cancel() {
            guard let request else { return }
            finish(request.id, with: .failure(CancellationError()))
        }

        fileprivate func finish(_ id: UUID, with result: Result<String, any Error>) {
            guard request?.id == id else { return }
            let continuation = continuation
            self.continuation = nil
            request = nil
            assert(continuation != nil)
            continuation?.resume(with: result)
        }
    }

    struct SessionView: View {
        let session: Session

        var body: some View {
            if let request = session.request {
                Color.clear
                    .translationTask(
                        request.configuration,
                        action: Self.translationAction(id: request.id, text: request.text, owner: session))
                    .onDisappear {
                        session.finish(request.id, with: .failure(CancellationError()))
                    }
                    .id(request.id)
            }
        }

        nonisolated private static func translationAction(
            id: UUID, text: String, owner: Session
        ) -> (TranslationSession) async -> Void {
            { native in
                do {
                    let translated = try await native.translate(text).targetText
                    try Task.checkCancellation()
                    await owner.finish(id, with: .success(translated))
                } catch {
                    await owner.finish(id, with: .failure(error))
                }
            }
        }
    }

    /// A download is a locale, so the region a bare code resolves to can miss the one installed.
    private static func installedPair(
        _ sources: [Locale.Language], _ targets: [Locale.Language],
        _ availability: LanguageAvailability
    ) async -> (source: Locale.Language, target: Locale.Language)? {
        for source in sources {
            for target in targets where await availability.status(from: source, to: target) == .installed {
                return (source, target)
            }
        }
        return nil
    }

    /// A region is not a language: the translator calls Egyptian into Saudi Arabic an unsupported pair.
    private static func isSameLanguage(_ lhs: Locale.Language, _ rhs: Locale.Language) -> Bool {
        let lhs = Locale.Language(identifier: lhs.maximalIdentifier)
        let rhs = Locale.Language(identifier: rhs.maximalIdentifier)
        return lhs.languageCode == rhs.languageCode && lhs.script == rhs.script
    }

    /// Region may move, since one English is another's asset, but a different script is a language.
    private static func variants(
        of language: Locale.Language, among supported: [Locale.Language]
    ) -> [Locale.Language] {
        [language]
            + supported.filter {
                $0.languageCode == language.languageCode && $0.script == language.script
                    && !$0.isEquivalent(to: language)
            }
    }

    /// Minimal, not maximal: the maximal form would spell `es` "Spanish (Latin, Spain)" in a menu.
    static func displayName(of language: Locale.Language) -> String {
        Locale.current.localizedString(forIdentifier: language.minimalIdentifier)
            ?? language.minimalIdentifier
    }

    /// The framework's own list, so the picker cannot offer a pair that only fails at press time.
    static func supportedLanguages() async -> [Locale.Language] {
        await LanguageAvailability().supportedLanguages
            .sorted { displayName(of: $0) < displayName(of: $1) }
    }
}
