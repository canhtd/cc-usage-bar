import Foundation

/// A NULL-terminated C string array built before `fork`, so the child only has to pass
/// the pointers to `execve`. Allocating or copying after a fork in a Cocoa process is
/// not async-signal-safe; doing all of it up front is what keeps the child trivial.
nonisolated final class CStringArray {
    let pointer: UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>
    private let count: Int

    init(_ strings: [String]) {
        count = strings.count
        pointer = UnsafeMutablePointer<UnsafeMutablePointer<CChar>?>.allocate(
            capacity: strings.count + 1)
        for (index, string) in strings.enumerated() {
            pointer[index] = strdup(string)
        }
        pointer[strings.count] = nil
    }

    func deallocate() {
        for index in 0..<count { free(pointer[index]) }
        pointer.deallocate()
    }
}
