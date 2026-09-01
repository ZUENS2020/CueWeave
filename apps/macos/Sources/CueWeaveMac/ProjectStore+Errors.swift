import Foundation

extension ProjectStore {
    func actionableMessage(for error: Error) -> String {
        let message = error.localizedDescription
        if message.contains("[authentication]") || message.contains("HTTP 401") || message.contains("HTTP 403") {
            return "The selected provider rejected the API key. Open Settings, verify the key and provider, then try again.\n\n\(message)"
        }
        if message.contains("[quota]") || message.contains("HTTP 429") {
            return "The provider rate limit or quota was reached. Wait or check the account quota before retrying.\n\n\(message)"
        }
        if message.localizedCaseInsensitiveContains("timed out") {
            return "The provider did not answer before the timeout. The project was not changed; retry when the connection is stable.\n\n\(message)"
        }
        if message.contains("14 MiB") || message.contains("19 MiB") {
            return "The target audio is too large for inline Gemini alignment. Manual timing and export remain available.\n\n\(message)"
        }
        if message.contains("invalid alignment") {
            return "Gemini returned an unsafe or incomplete timeline, so CueWeave rejected it without changing the project.\n\n\(message)"
        }
        return message
    }

    func audioLoadMessage(for url: URL, error: Error) -> String {
        var isDirectory: ObjCBool = false
        let exists = FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
        if !exists || isDirectory.boolValue {
            return "Target audio was not found at \(url.path). Replace the target MP3 from the Source page."
        }
        let nsError = error as NSError
        if nsError.domain == NSOSStatusErrorDomain || nsError.localizedDescription.contains("OSStatus") {
            return "CueWeave could not decode the target audio at \(url.path). Confirm it is a readable MP3 and has not been moved, then use Replace Target."
        }
        return "CueWeave could not load the target audio at \(url.path).\n\n\(error.localizedDescription)"
    }
}
