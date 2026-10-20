import Foundation

public enum Format {
    public static func bytes(_ b: UInt64) -> String {
        let gb = Double(b) / 1_073_741_824
        if gb >= 1 {
            return String(format: "%.1f GB", gb).replacingOccurrences(of: ".", with: ",")
        }
        return "\(Int((Double(b) / 1_048_576).rounded())) MB"
    }

    public static func cpu(_ perCore: Double, cores: Int) -> String {
        let share = perCore / Double(max(cores, 1))
        return String(format: "%.1f%%", share).replacingOccurrences(of: ".", with: ",")
    }

    public static func age(since start: Date, now: Date) -> String {
        let seconds = max(0, now.timeIntervalSince(start))
        if seconds < 3600 { return "\(Int(seconds / 60)) min" }
        if seconds < 86_400 { return "\(Int(seconds / 3600)) h" }
        let days = Int(seconds / 86_400)
        return days == 1 ? "1 dia" : "\(days) dias"
    }
}
