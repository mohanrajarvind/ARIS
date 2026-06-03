import Foundation
import CoreBluetooth
import Combine

let bleServiceUUID = CBUUID(string: "1234")
let bleCharacteristicUUID = CBUUID(string: "5678")

final class BLEManager: NSObject, ObservableObject {
    @Published var isConnected = false
    @Published var statusText = "Disconnected"

    private var centralManager: CBCentralManager!
    private var espPeripheral: CBPeripheral?
    private var txCharacteristic: CBCharacteristic?

    private var pendingMessages: [String] = []
    private var isSending = false
    private let sendInterval: TimeInterval = 0.05   // 50 ms

    override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: .main)
    }

    func send(_ message: String) {
        guard isConnected,
              txCharacteristic != nil,
              espPeripheral != nil else { return }

        pendingMessages.append(message)
        processQueue()
    }

    func sendBatch(_ messages: [String]) {
        guard isConnected,
              txCharacteristic != nil,
              espPeripheral != nil else { return }

        pendingMessages.append(contentsOf: messages)
        processQueue()
    }

    private func processQueue() {
        guard !isSending,
              isConnected,
              let characteristic = txCharacteristic,
              let peripheral = espPeripheral,
              !pendingMessages.isEmpty else { return }

        isSending = true
        let message = pendingMessages.removeFirst()

        guard let data = message.data(using: .utf8) else {
            isSending = false
            DispatchQueue.main.asyncAfter(deadline: .now() + sendInterval) {
                self.processQueue()
            }
            return
        }

        peripheral.writeValue(data, for: characteristic, type: .withResponse)
    }
}

// MARK: - CBCentralManagerDelegate
extension BLEManager: CBCentralManagerDelegate {
    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOn {
            statusText = "Scanning for ESP32..."
            centralManager.scanForPeripherals(withServices: [bleServiceUUID])
        } else {
            statusText = "Bluetooth unavailable"
        }
    }

    func centralManager(_ central: CBCentralManager,
                        didDiscover peripheral: CBPeripheral,
                        advertisementData: [String : Any],
                        rssi RSSI: NSNumber) {
        espPeripheral = peripheral
        espPeripheral?.delegate = self
        centralManager.stopScan()
        centralManager.connect(peripheral)
        statusText = "Connecting..."
    }

    func centralManager(_ central: CBCentralManager,
                        didConnect peripheral: CBPeripheral) {
        isConnected = true
        statusText = "Connected"
        peripheral.discoverServices([bleServiceUUID])
    }

    func centralManager(_ central: CBCentralManager,
                        didDisconnectPeripheral peripheral: CBPeripheral,
                        error: Error?) {
        isConnected = false
        statusText = "Disconnected"
        txCharacteristic = nil
        pendingMessages.removeAll()
        isSending = false
        centralManager.scanForPeripherals(withServices: [bleServiceUUID])
    }
}

// MARK: - CBPeripheralDelegate
extension BLEManager: CBPeripheralDelegate {
    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }
        for service in services {
            peripheral.discoverCharacteristics([bleCharacteristicUUID], for: service)
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didDiscoverCharacteristicsFor service: CBService,
                    error: Error?) {
        guard let characteristics = service.characteristics else { return }
        for characteristic in characteristics where characteristic.uuid == bleCharacteristicUUID {
            txCharacteristic = characteristic
            statusText = "Ready"
            processQueue()
        }
    }

    func peripheral(_ peripheral: CBPeripheral,
                    didWriteValueFor characteristic: CBCharacteristic,
                    error: Error?) {
        if let error = error {
            print("BLE write error: \(error.localizedDescription)")
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + sendInterval) {
            self.isSending = false
            self.processQueue()
        }
    }
}
