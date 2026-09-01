import Foundation

extension ProjectStore {
    func actionableMessage(for error: Error) -> String {
        let message = error.localizedDescription
        if message.contains("[authentication]") || message.contains("HTTP 401") || message.contains("HTTP 403") {
            return L10n.shared.t("error.auth", message)
        }
        if message.contains("[quota]") || message.contains("HTTP 429") {
            return L10n.shared.t("error.quota", message)
        }
        if message.localizedCaseInsensitiveContains("timed out") {
            return L10n.shared.t("error.timeout", message)
        }
        if message.contains("14 MiB") || message.contains("19 MiB") {
            return L10n.shared.t("error.tooLarge", message)
        }
        if message.contains("invalid alignment") {
            return L10n.shared.t("error.invalidAlignment", message)
        }
        return message
    }

    func audioLoadMessage(for url: URL, error: Error) -> String {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        if !exists || isDirectory.boolValue {
            return L10n.shared.t("error.audioMissing", url.path)
        }
        let nsError = error as NSError
        if nsError.domain == NSOSStatusErrorDomain || nsError.localizedDescription.contains("OSStatus") {
            return L10n.shared.t("error.audioDecode", url.path)
        }
        return L10n.shared.t("error.audioLoad", url.path, error.localizedDescription)
    }
}
