import XCTest
import CoreBluetooth
@testable import GooseSwift

final class GooseBLETypesTests: XCTestCase {

  // MARK: - GooseBLEClient.generation(from:) helper tests

  func testGenerationDerivation_gen4ServiceUUID() {
    let gen4ServiceUUID = CBUUID(string: "61080001-8d6d-82b8-614a-1c8cb0f8dcc6")
    let generation = GooseBLEClient.generation(from: [gen4ServiceUUID])
    XCTAssertEqual(generation, "4.0", "61080001 service UUID should derive generation 4.0")
  }

  func testGenerationDerivation_gen5ServiceUUID() {
    let gen5ServiceUUID = CBUUID(string: "fd4b0001-cce1-4033-93ce-002d5875f58a")
    let generation = GooseBLEClient.generation(from: [gen5ServiceUUID])
    XCTAssertEqual(generation, "5.0", "fd4b0001 service UUID should derive generation 5.0")
  }

  func testGenerationDerivation_unknownServiceUUID() {
    let unknownUUID = CBUUID(string: "00001800-0000-1000-8000-00805f9b34fb")
    let generation = GooseBLEClient.generation(from: [unknownUUID])
    XCTAssertEqual(generation, "unknown", "Unknown service UUID should derive 'unknown'")
  }

  func testGenerationDerivation_emptyServiceList() {
    let generation = GooseBLEClient.generation(from: [])
    XCTAssertEqual(generation, "unknown", "Empty service list should derive 'unknown'")
  }

  func testGenerationDerivation_gen4TakesPrecedenceWhenBothPresent() {
    let gen4UUID = CBUUID(string: "61080001-8d6d-82b8-614a-1c8cb0f8dcc6")
    let gen5UUID = CBUUID(string: "fd4b0001-cce1-4033-93ce-002d5875f58a")
    // Gen4 listed first — should return "4.0"
    let generation = GooseBLEClient.generation(from: [gen4UUID, gen5UUID])
    XCTAssertEqual(generation, "4.0", "Gen4 UUID first in list should derive 4.0")
  }

  // MARK: - GooseNotificationEvent.rustDeviceType tests

  func testRustDeviceType_gen4CharacteristicPrefix() {
    let event = GooseNotificationEvent(
      deviceID: UUID(),
      serviceUUID: "61080001-8d6d-82b8-614a-1c8cb0f8dcc6",
      characteristicUUID: "61080003-8d6d-82b8-614a-1c8cb0f8dcc6",
      value: Data(),
      capturedAt: Date()
    )
    XCTAssertEqual(event.rustDeviceType, "GEN4",
      "Characteristic starting with 610800 should produce rustDeviceType GEN4")
  }

  func testRustDeviceType_gen5CharacteristicPrefix() {
    let event = GooseNotificationEvent(
      deviceID: UUID(),
      serviceUUID: "fd4b0001-cce1-4033-93ce-002d5875f58a",
      characteristicUUID: "fd4b0003-cce1-4033-93ce-002d5875f58a",
      value: Data(),
      capturedAt: Date()
    )
    XCTAssertEqual(event.rustDeviceType, "GOOSE",
      "Characteristic starting with fd4b should produce rustDeviceType GOOSE")
  }
}
