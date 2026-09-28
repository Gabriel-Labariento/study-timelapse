import Foundation
func XCTAssertTrue(_ value: Bool, file: StaticString = #file, line: UInt = #line) { precondition(value, "Expected true at \(file):\(line)") }
func XCTAssertFalse(_ value: Bool, file: StaticString = #file, line: UInt = #line) { precondition(!value, "Expected false at \(file):\(line)") }
func XCTAssertNil<T>(_ value: T?, file: StaticString = #file, line: UInt = #line) { precondition(value == nil, "Expected nil at \(file):\(line)") }
func XCTAssertEqual<T: Equatable>(_ a: T, _ b: T, file: StaticString = #file, line: UInt = #line) { precondition(a == b, "\(a) != \(b) at \(file):\(line)") }
func XCTAssertEqual(_ a: Double, _ b: Double, accuracy: Double, file: StaticString = #file, line: UInt = #line) { precondition(abs(a-b) <= accuracy, "\(a) != \(b) at \(file):\(line)") }
func XCTAssertGreaterThanOrEqual<T: Comparable>(_ a: T, _ b: T) { precondition(a >= b) }
func XCTAssertLessThanOrEqual<T: Comparable>(_ a: T, _ b: T) { precondition(a <= b) }
