import Foundation

/// Minimal assertion harness. Collects failures instead of trapping so one run
/// reports everything that is wrong.
@MainActor
enum Expect {
    private(set) static var passed = 0
    private(set) static var failures: [String] = []
    private static var group = ""

    static func suite(_ name: String, _ body: () throws -> Void) {
        group = name
        print("\n\(name)")
        do {
            try body()
        } catch {
            record(false, "threw \(error)")
        }
    }

    static func that(_ condition: Bool, _ description: @autoclosure () -> String) {
        record(condition, description())
    }

    static func equal<T: Equatable>(_ actual: T, _ expected: T, _ label: String) {
        record(actual == expected, "\(label): expected \(expected), got \(actual)")
    }

    private static func record(_ ok: Bool, _ description: String) {
        if ok {
            passed += 1
        } else {
            failures.append("\(group): \(description)")
            print("  FAIL  \(description)")
        }
    }

    /// - Returns: process exit code.
    static func report() -> Int32 {
        print("\n\(passed) passed, \(failures.count) failed")
        for failure in failures { print("  \(failure)") }
        return failures.isEmpty ? 0 : 1
    }
}
