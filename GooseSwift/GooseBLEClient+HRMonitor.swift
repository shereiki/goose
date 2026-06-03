import CoreBluetooth
import Foundation
import OSLog


final class GooseBLEHRMonitorManager: NSObject, CBCentralManagerDelegate, CBPeripheralDelegate {
  var central: CBCentralManager?
  var discoveredHRDevices: [GooseDiscoveredDevice] = []
  var hrPeripheral: CBPeripheral?
  var hrConnectionState: String = "disconnected"
  var connectedDeviceName: String?
  weak var owner: GooseBLEClient?

  func start(queue: DispatchQueue) {
    guard central == nil else { return }
    central = CBCentralManager(
      delegate: self,
      queue: queue,
      options: [CBCentralManagerOptionRestoreIdentifierKey: "com.goose.swift.hr-monitor"]
    )
  }

  func startScan() {
    central?.scanForPeripherals(
      withServices: [CBUUID(string: "180D")],
      options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
    )
  }

  func stopScan() {
    central?.stopScan()
  }

  func connect(_ device: GooseDiscoveredDevice) {
    guard let peripheral = central?.retrievePeripherals(withIdentifiers: [device.id]).first else {
      return
    }
    connectedDeviceName = device.name
    central?.connect(peripheral, options: nil)
  }

  // MARK: - CBCentralManagerDelegate

  func centralManagerDidUpdateState(_ central: CBCentralManager) {
    // State changes are informational; scanning starts only when explicitly requested
  }

  func centralManager(
    _ central: CBCentralManager,
    willRestoreState dict: [String: Any]
  ) {
    // State restoration not required for manual-only HR monitor connections
  }

  func centralManager(
    _ central: CBCentralManager,
    didDiscover peripheral: CBPeripheral,
    advertisementData: [String: Any],
    rssi RSSI: NSNumber
  ) {
    var rawName = peripheral.name
      ?? (advertisementData[CBAdvertisementDataLocalNameKey] as? String)
      ?? "unknown_hr_monitor"
    rawName = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
    if rawName.isEmpty { rawName = "unknown_hr_monitor" }
    let sanitizedName = String(rawName.prefix(64))

    let device = GooseDiscoveredDevice(
      id: peripheral.identifier,
      name: sanitizedName,
      rssi: RSSI.intValue,
      generation: "hr_monitor"
    )

    if let index = discoveredHRDevices.firstIndex(where: { $0.id == device.id }) {
      discoveredHRDevices[index] = device
    } else {
      discoveredHRDevices.append(device)
    }
    discoveredHRDevices.sort { $0.rssi > $1.rssi }

    DispatchQueue.main.async { [weak self] in
      self?.owner?.objectWillChange.send()
    }
  }

  func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    hrConnectionState = "connected"
    hrPeripheral = peripheral
    peripheral.delegate = self
    peripheral.discoverServices([CBUUID(string: "180D")])
  }

  func centralManager(
    _ central: CBCentralManager,
    didDisconnectPeripheral peripheral: CBPeripheral,
    error: Error?
  ) {
    hrConnectionState = "disconnected"
    hrPeripheral = nil
  }

  // MARK: - CBPeripheralDelegate

  func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
    guard error == nil, let services = peripheral.services else { return }
    for service in services where service.uuid == CBUUID(string: "180D") {
      peripheral.discoverCharacteristics([CBUUID(string: "2A37")], for: service)
    }
  }

  func peripheral(
    _ peripheral: CBPeripheral,
    didDiscoverCharacteristicsFor service: CBService,
    error: Error?
  ) {
    guard error == nil, let characteristics = service.characteristics else { return }
    for characteristic in characteristics where characteristic.uuid == CBUUID(string: "2A37") {
      peripheral.setNotifyValue(true, for: characteristic)
    }
  }

  func peripheral(
    _ peripheral: CBPeripheral,
    didUpdateValueFor characteristic: CBCharacteristic,
    error: Error?
  ) {
    guard error == nil, characteristic.uuid == CBUUID(string: "2A37") else { return }
    let capturedAt = Date()
    let value = characteristic.value ?? Data()

    // This callback runs on the background CoreBluetooth queue (CBCentralManager was created
    // with that queue). Deliver directly on this queue — do NOT hop to @MainActor or
    // DispatchQueue.main (review MEDIUM-3: HR notifications arrive at high frequency).
    let event = GooseNotificationEvent(
      deviceID: peripheral.identifier,
      serviceUUID: "180D",
      characteristicUUID: "2A37",
      value: value,
      capturedAt: capturedAt
    )
    owner?.onNotification?(event)

    // For live HR display, use the existing method which performs its own main-thread hop
    owner?.handleStandardHeartRate(value, characteristic: characteristic, capturedAt: capturedAt)
  }
}


extension GooseBLEClient {
  func startHRMonitorScan() {
    hrMonitorManager.owner = self
    hrMonitorManager.start(queue: coreBluetoothQueue)
    hrMonitorManager.startScan()
    record(source: "ble.hr_monitor", title: "scan.start")
  }

  func stopHRMonitorScan() {
    hrMonitorManager.stopScan()
    record(source: "ble.hr_monitor", title: "scan.stop")
  }

  func connectHRMonitor(_ device: GooseDiscoveredDevice) {
    hrMonitorManager.connect(device)
    record(source: "ble.hr_monitor", title: "connect.requested", body: device.name)
  }
}
