// Minimal assertion adapter for the system Command Line Tools, which ship
// neither XCTest nor Swift Testing. Xcode runs these same fixtures with XCTest.
import Foundation
class XCTestCase {}
func XCTAssertTrue(_ condition: @autoclosure () throws -> Bool,
                   file: StaticString = #filePath, line: UInt = #line) rethrows {
    guard try condition() else { fatalError("Assertion failed at \(file):\(line)") }
}
