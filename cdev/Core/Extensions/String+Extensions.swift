import Foundation

extension String {
    /// Check if string is a valid URL
    var isValidURL: Bool {
        guard let url = URL(string: self) else { return false }
        return url.scheme != nil && url.host != nil
    }

    /// Convert to URL if valid
    var asURL: URL? {
        URL(string: self)
    }

    /// Truncate string with ellipsis
    func truncated(to length: Int, trailing: String = "...") -> String {
        if self.count <= length {
            return self
        }
        return String(self.prefix(length)) + trailing
    }

    /// Check if string contains only whitespace
    var isBlank: Bool {
        self.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Safe JSON parsing
    func parseJSON<T: Decodable>(as type: T.Type) -> T? {
        guard let data = self.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(type, from: data)
    }
}

// MARK: - Diff Parsing

extension String {
    /// Extract file path from diff header
    var diffFilePath: String? {
        // Parse "--- a/path/to/file" or "+++ b/path/to/file"
        if self.hasPrefix("--- a/") {
            return String(self.dropFirst(6))
        } else if self.hasPrefix("+++ b/") {
            return String(self.dropFirst(6))
        }
        return nil
    }

    /// Check if line is diff addition
    var isDiffAddition: Bool {
        self.hasPrefix("+") && !self.hasPrefix("+++")
    }

    /// Check if line is diff deletion
    var isDiffDeletion: Bool {
        self.hasPrefix("-") && !self.hasPrefix("---")
    }

    /// Check if line is diff header
    var isDiffHeader: Bool {
        self.hasPrefix("@@") || self.hasPrefix("---") || self.hasPrefix("+++") || self.hasPrefix("diff")
    }
}
