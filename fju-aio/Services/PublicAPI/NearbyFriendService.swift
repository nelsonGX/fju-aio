import Foundation
import CoreBluetooth
import os.log

// MARK: - UUIDs
// Custom 128-bit UUIDs scoped to this app — no entitlement required.

private let kServiceUUID        = CBUUID(string: "A1B2C3D4-E5F6-7890-ABCD-EF1234567890")
private let kProfileCharUUID    = CBUUID(string: "A1B2C3D4-E5F6-7890-ABCD-EF1234567891")
private let kAddRequestCharUUID = CBUUID(string: "A1B2C3D4-E5F6-7890-ABCD-EF1234567892")

// MARK: - Peer Profile

struct NearbyPeerProfile: Identifiable, Equatable {
    let id: String          // cloudKitRecordName
    let empNo: String
    let displayName: String
    let userId: Int
}

// MARK: - NearbyFriendService
// Acts as both BLE peripheral (advertises own profile) and central (scans + reads peers).
// No special entitlements required — uses CoreBluetooth only.

@MainActor
@Observable
final class NearbyFriendService: NSObject {

    static let shared = NearbyFriendService()

    private(set) var discoveredPeers: [NearbyPeerProfile] = []
    private(set) var incomingAddRequests: [NearbyPeerProfile] = []
    private(set) var isActive = false

    private let logger = Logger(subsystem: Bundle.main.bundleIdentifier ?? "com.nelsongx.apps.fju-aio", category: "NearbyFriend")

    // Peripheral side
    private var peripheralManager: CBPeripheralManager?
    private var profileCharacteristic: CBMutableCharacteristic?
    private var myProfileData: Data?

    // Central side
    private var centralManager: CBCentralManager?
    /// peripherals being held in memory while we read from them
    private var pendingPeripherals: [CBPeripheral] = []
    private var peripheralsByRecordName: [String: CBPeripheral] = [:]
    private var addRequestCharacteristicsByRecordName: [String: CBCharacteristic] = [:]
    private var pendingAddRequestRecordNames: Set<String> = []
    /// track which peripheral IDs we have already processed
    private var seenPeripheralIDs: Set<UUID> = []

    private override init() {}

    // MARK: - Start / Stop

    func start(profile: MutualQRPayload) {
        // Force-clean any lingering session so re-opening the sheet always starts fresh
        if isActive { stop() }
        guard let data = try? JSONEncoder().encode(profile) else { return }
        myProfileData = data

        // Use a background queue — passing .main can suppress the permission prompt on some iOS versions
        let btQueue = DispatchQueue(label: "com.nelsongx.apps.fju-aio.bluetooth", qos: .userInitiated)

        peripheralManager = CBPeripheralManager(delegate: self, queue: btQueue, options: [
            CBPeripheralManagerOptionShowPowerAlertKey: true
        ])

        centralManager = CBCentralManager(delegate: self, queue: btQueue, options: [
            CBCentralManagerOptionShowPowerAlertKey: true
        ])

        isActive = true
        logger.info("▶️ NearbyFriendService started as \(profile.displayName, privacy: .public) (\(data.count, privacy: .public) bytes)")
    }

    func stop() {
        peripheralManager?.stopAdvertising()
        peripheralManager = nil

        centralManager?.stopScan()
        for p in pendingPeripherals { centralManager?.cancelPeripheralConnection(p) }
        centralManager = nil

        pendingPeripherals = []
        peripheralsByRecordName = [:]
        addRequestCharacteristicsByRecordName = [:]
        pendingAddRequestRecordNames = []
        seenPeripheralIDs = []
        discoveredPeers = []
        incomingAddRequests = []
        myProfileData = nil
        profileCharacteristic = nil
        isActive = false
        logger.info("⏹ NearbyFriendService stopped")
    }

    func removePeer(id: String) {
        discoveredPeers.removeAll { $0.id == id }
    }

    func dismissIncomingRequest(id: String) {
        incomingAddRequests.removeAll { $0.id == id }
    }

    func sendAddRequest(to peer: NearbyPeerProfile) {
        sendAddRequest(toRecordName: peer.id)
    }

    func sendAddRequest(to payload: MutualQRPayload) {
        sendAddRequest(toRecordName: payload.cloudKitRecordName)
    }

    private func sendAddRequest(toRecordName recordName: String) {
        guard recordName != ProfileQRService.stableDeviceToken() else { return }
        pendingAddRequestRecordNames.insert(recordName)
        logger.info("📨 Queued add request for \(recordName, privacy: .public)")

        if let peripheral = peripheralsByRecordName[recordName],
           let characteristic = addRequestCharacteristicsByRecordName[recordName] {
            writeAddRequest(to: peripheral, characteristic: characteristic, recordName: recordName)
        } else if centralManager?.state == .poweredOn {
            startScanning()
        }
    }

    // MARK: - Peripheral setup (called once CBPeripheralManager is powered on)

    private func setupPeripheral() {
        guard let pm = peripheralManager, let data = myProfileData else { return }

        let characteristic = CBMutableCharacteristic(
            type: kProfileCharUUID,
            properties: [.read],
            value: data,            // static value — no need for dynamic reads
            permissions: [.readable]
        )
        profileCharacteristic = characteristic

        let addRequestCharacteristic = CBMutableCharacteristic(
            type: kAddRequestCharUUID,
            properties: [.write, .writeWithoutResponse],
            value: nil,
            permissions: [.writeable]
        )

        let service = CBMutableService(type: kServiceUUID, primary: true)
        service.characteristics = [characteristic, addRequestCharacteristic]
        pm.add(service)
    }

    private func startAdvertising() {
        peripheralManager?.startAdvertising([
            CBAdvertisementDataServiceUUIDsKey: [kServiceUUID],
            CBAdvertisementDataLocalNameKey: "FJU-Nearby"
        ])
        logger.info("📡 Advertising BLE service")
    }

    // MARK: - Central setup (called once CBCentralManager is powered on)

    private func startScanning() {
        centralManager?.scanForPeripherals(
            withServices: [kServiceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )
        logger.info("🔍 Scanning for nearby peers")
    }

    private func writeAddRequest(to peripheral: CBPeripheral, characteristic: CBCharacteristic, recordName: String) {
        guard let data = myProfileData else { return }
        let writeType: CBCharacteristicWriteType = characteristic.properties.contains(.write) ? .withResponse : .withoutResponse
        peripheral.writeValue(data, for: characteristic, type: writeType)
        pendingAddRequestRecordNames.remove(recordName)
        logger.info("📨 Sent add request to \(recordName, privacy: .public)")
    }
}

// MARK: - CBPeripheralManagerDelegate

extension NearbyFriendService: CBPeripheralManagerDelegate {

    nonisolated func peripheralManagerDidUpdateState(_ peripheral: CBPeripheralManager) {
        Task { @MainActor in
            switch peripheral.state {
            case .poweredOn:
                self.logger.info("🔵 Peripheral powered on")
                self.setupPeripheral()
            case .poweredOff:
                self.logger.warning("⚠️ Bluetooth powered off")
            default:
                break
            }
        }
    }

    nonisolated func peripheralManager(_ peripheral: CBPeripheralManager, didAdd service: CBService, error: Error?) {
        Task { @MainActor in
            if let error {
                self.logger.error("❌ Failed to add service: \(error.localizedDescription, privacy: .public)")
            } else {
                self.logger.info("✅ Service added — starting advertising")
                self.startAdvertising()
            }
        }
    }

    nonisolated func peripheralManagerDidStartAdvertising(_ peripheral: CBPeripheralManager, error: Error?) {
        Task { @MainActor in
            if let error {
                self.logger.error("❌ Advertising failed: \(error.localizedDescription, privacy: .public)")
            } else {
                self.logger.info("📡 Advertising started")
            }
        }
    }

    nonisolated func peripheralManager(
        _ peripheral: CBPeripheralManager,
        didReceiveWrite requests: [CBATTRequest]
    ) {
        Task { @MainActor in
            for request in requests where request.characteristic.uuid == kAddRequestCharUUID {
                guard let value = request.value,
                      let payload = try? JSONDecoder().decode(MutualQRPayload.self, from: value),
                      payload.cloudKitRecordName != ProfileQRService.stableDeviceToken() else {
                    peripheral.respond(to: request, withResult: .invalidAttributeValueLength)
                    continue
                }

                let peer = NearbyPeerProfile(
                    id: payload.cloudKitRecordName,
                    empNo: payload.empNo,
                    displayName: payload.displayName,
                    userId: payload.userId
                )

                if !self.incomingAddRequests.contains(where: { $0.id == peer.id }) {
                    self.incomingAddRequests.append(peer)
                    self.logger.info("📥 Incoming add request from \(peer.displayName, privacy: .public)")
                }
                peripheral.respond(to: request, withResult: .success)
            }
        }
    }
}

// MARK: - CBCentralManagerDelegate

extension NearbyFriendService: CBCentralManagerDelegate {

    nonisolated func centralManagerDidUpdateState(_ central: CBCentralManager) {
        Task { @MainActor in
            switch central.state {
            case .poweredOn:
                self.logger.info("🔵 Central powered on")
                self.startScanning()
            case .poweredOff:
                self.logger.warning("⚠️ Bluetooth powered off")
            default:
                break
            }
        }
    }

    nonisolated func centralManager(
        _ central: CBCentralManager,
        didDiscover peripheral: CBPeripheral,
        advertisementData: [String: Any],
        rssi RSSI: NSNumber
    ) {
        Task { @MainActor in
            guard !self.seenPeripheralIDs.contains(peripheral.identifier) else { return }
            self.seenPeripheralIDs.insert(peripheral.identifier)
            self.logger.info("📶 Discovered peripheral \(peripheral.identifier, privacy: .public) RSSI=\(RSSI, privacy: .public)")

            // Keep a strong reference and connect
            self.pendingPeripherals.append(peripheral)
            peripheral.delegate = self
            central.connect(peripheral, options: nil)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
        Task { @MainActor in
            self.logger.info("🔗 Connected to \(peripheral.identifier, privacy: .public) — discovering services")
            peripheral.discoverServices([kServiceUUID])
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didFailToConnect peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            self.logger.error("❌ Failed to connect: \(error?.localizedDescription ?? "unknown", privacy: .public)")
            self.pendingPeripherals.removeAll { $0 == peripheral }
            self.seenPeripheralIDs.remove(peripheral.identifier)
        }
    }

    nonisolated func centralManager(_ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?) {
        Task { @MainActor in
            self.pendingPeripherals.removeAll { $0 == peripheral }
        }
    }
}

// MARK: - CBPeripheralDelegate

extension NearbyFriendService: CBPeripheralDelegate {

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        Task { @MainActor in
            guard error == nil,
                  let service = peripheral.services?.first(where: { $0.uuid == kServiceUUID }) else {
                self.logger.error("❌ Service discovery failed: \(error?.localizedDescription ?? "not found", privacy: .public)")
                return
            }
            self.logger.info("✅ Service found — discovering characteristics")
            peripheral.discoverCharacteristics([kProfileCharUUID, kAddRequestCharUUID], for: service)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?) {
        Task { @MainActor in
            guard error == nil,
                  let profileChar = service.characteristics?.first(where: { $0.uuid == kProfileCharUUID }) else {
                self.logger.error("❌ Characteristic discovery failed: \(error?.localizedDescription ?? "not found", privacy: .public)")
                return
            }
            if let addRequestChar = service.characteristics?.first(where: { $0.uuid == kAddRequestCharUUID }) {
                for (recordName, storedPeripheral) in self.peripheralsByRecordName where storedPeripheral == peripheral {
                    self.addRequestCharacteristicsByRecordName[recordName] = addRequestChar
                    if self.pendingAddRequestRecordNames.contains(recordName) {
                        self.writeAddRequest(to: peripheral, characteristic: addRequestChar, recordName: recordName)
                    }
                }
            }
            self.logger.info("📖 Reading profile characteristic")
            peripheral.readValue(for: profileChar)
        }
    }

    nonisolated func peripheral(_ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic, error: Error?) {
        Task { @MainActor in
            guard error == nil, let data = characteristic.value else {
                self.logger.error("❌ Read failed: \(error?.localizedDescription ?? "no data", privacy: .public)")
                self.centralManager?.cancelPeripheralConnection(peripheral)
                return
            }

            guard let payload = try? JSONDecoder().decode(MutualQRPayload.self, from: data) else {
                self.logger.warning("⚠️ Could not decode profile from \(peripheral.identifier, privacy: .public)")
                self.centralManager?.cancelPeripheralConnection(peripheral)
                return
            }

            let myToken = ProfileQRService.stableDeviceToken()
            guard payload.cloudKitRecordName != myToken else {
                self.logger.info("🔄 Skipping own profile advertisement")
                self.centralManager?.cancelPeripheralConnection(peripheral)
                return
            }

            let peer = NearbyPeerProfile(
                id: payload.cloudKitRecordName,
                empNo: payload.empNo,
                displayName: payload.displayName,
                userId: payload.userId
            )

            self.logger.info("✅ Received profile: \(peer.displayName, privacy: .public) (\(peer.empNo, privacy: .public))")

            self.peripheralsByRecordName[peer.id] = peripheral
            if let service = peripheral.services?.first(where: { $0.uuid == kServiceUUID }),
               let addRequestChar = service.characteristics?.first(where: { $0.uuid == kAddRequestCharUUID }) {
                self.addRequestCharacteristicsByRecordName[peer.id] = addRequestChar
                if self.pendingAddRequestRecordNames.contains(peer.id) {
                    self.writeAddRequest(to: peripheral, characteristic: addRequestChar, recordName: peer.id)
                }
            }

            if !self.discoveredPeers.contains(where: { $0.id == peer.id }),
               !self.incomingAddRequests.contains(where: { $0.id == peer.id }) {
                self.discoveredPeers.append(peer)
            }

            if !self.pendingAddRequestRecordNames.contains(peer.id) {
                self.centralManager?.cancelPeripheralConnection(peripheral)
            }
        }
    }
}
