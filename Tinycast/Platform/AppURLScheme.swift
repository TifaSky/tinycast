import Foundation

/// This build's own link scheme, declared in project.yml.
enum AppURLScheme {
    static let current: String = {
        guard let scheme = Bundle.main.object(forInfoDictionaryKey: "TinycastURLScheme") as? String
        else { preconditionFailure("Info.plist must name TinycastURLScheme") }
        return scheme
    }()
}
