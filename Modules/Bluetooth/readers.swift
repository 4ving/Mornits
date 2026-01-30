//
//  readers.swift
//  Bluetooth
//
//  Created by Serhiy Mytrovtsiy on 08/06/2021.
//  Using Swift 5.0.
//  Running on macOS 10.15.
//
//  Copyright © 2021 Serhiy Mytrovtsiy. All rights reserved.
//

import CoreBluetooth
import Foundation
import IOBluetooth
import Kit

private struct bleDevice {
    var name: String?
    var address: String
    var uuid: UUID?
    var batteryLevel: [KeyValue_t]
    var isConnected: Bool = false
    var isPaired: Bool = false
}

private struct ioDevice {
    var name: String
    var address: String
    var rssi: Int8
    var isConnected: Bool
    var isPaired: Bool
}

internal class DevicesReader: Reader<[BLEDevice]>, CBCentralManagerDelegate, CBPeripheralDelegate {
    private var devices: [BLEDevice] = []
    private var devicesToRemove: [UUID] = []
    private var manager: CBCentralManager!

    private var characteristicsDict: [UUID: CBCharacteristic] = [:]
    private var bleLevels: [UUID: KeyValue_t] = [:]

    static let batteryServiceUUID = CBUUID(string: "0x180F")
    static let batteryCharacteristicsUUID = CBUUID(string: "0x2A19")

    init(callback: @escaping (T?) -> Void = { _ in }) {
        super.init(.bluetooth, callback: callback)
        self.manager = CBCentralManager(delegate: self, queue: nil)
    }

    public override func read() {
        let hid = self.HIDDevices()
        let SPB = self.profilerDevices()
        let list = self.cacheDevices()

        // Create a unique set of devices from various sources
        var uniqueList: [bleDevice] = []
        let allSources = hid + SPB.0 + list
        allSources.forEach { v in
            if !uniqueList.contains(where: { $0.address == v.address }) {
                uniqueList.append(v)
            }
        }

        uniqueList.forEach { (data: bleDevice) in
            // RSSI is only available via IOBluetoothDevice or CBCentralManager delegate.
            // Since we avoid IOBluetoothDevice, RSSI will be nil unless we get it from CBPeripheral (not implemented here for all devices).
            // This is an acceptable tradeoff to avoid logs.
            let rssi: Int? = nil

            /*
            if data.address.range(
                of: "^([0-9a-fA-F]{2}[:-]){5}([0-9a-fA-F]{2})$", options: .regularExpression) != nil
            {
                if let device = IOBluetoothDevice(addressString: data.address) {
                    isPaired = device.isPaired()
                    isConnected = device.isConnected()
                    if device.rssi() != 127 {
                        rssi = Int(device.rssi())
                    }
                }
            }
            */

            // Only show if paired or connected (matches original logic)
            // Note: cacheDevices already filters for paired, HID are connected.
            // If the device object couldn't be created or isn't connected/paired,
            // we might still want to show it if it came from hid/profiler (which implies connected).
            // However, safe fallback: if it's in HID/Profiler, assume connected?
            // But IOBluetoothDevice is the source of truth for Classic Bluetooth status.
            // Let's trust the sources:
            // HID = connected.
            // Profiler = connected (from "device_connected" list).
            // Cache = paired.

            if let idx = self.devices.firstIndex(where: { $0.address == data.address }) {
                self.devices[idx].RSSI = rssi
                self.devices[idx].batteryLevel = data.batteryLevel
                self.devices[idx].isPaired = data.isPaired
                self.devices[idx].isConnected = data.isConnected
                return
            }

            self.devices.append(
                BLEDevice(
                    address: data.address,
                    name: data.name ?? "Unknown",
                    uuid: data.uuid,
                    RSSI: rssi,
                    batteryLevel: data.batteryLevel,
                    isConnected: data.isConnected,
                    isPaired: data.isPaired
                ))
        }

        if self.manager.state == .poweredOn {
            let peripherals = self.manager.retrievePeripherals(
                withIdentifiers: self.devices.compactMap({ $0.uuid }))
            peripherals.forEach { (p: CBPeripheral) in
                guard let idx = self.devices.firstIndex(where: { $0.uuid == p.identifier }) else {
                    return
                }

                if self.devices[idx].peripheral == nil {
                    self.devices[idx].peripheral = p
                }

                if p.state == .disconnected {
                    if self.manager.isScanning {
                        self.manager.connect(p, options: nil)
                    }
                } else if p.state == .disconnecting {
                    self.devicesToRemove.append(p.identifier)
                } else if p.state == .connected && !self.devices[idx].isPeripheralInitialized {
                    p.delegate = self
                    p.discoverServices([DevicesReader.batteryServiceUUID])
                    self.devices[idx].isPeripheralInitialized = true
                }
            }
        }

        for (i, d) in self.devices.enumerated() {
            if let uuid = d.uuid, let val = self.bleLevels[uuid] {
                self.devices[i].batteryLevel = [val]
            }
        }

        if !self.devicesToRemove.isEmpty {
            self.devices = self.devices.filter { (d: BLEDevice) -> Bool in
                if let uuid = d.uuid, self.devicesToRemove.contains(uuid) {
                    return false
                }
                return true
            }
            self.devicesToRemove = []
        }
        if !SPB.1.isEmpty {
            self.devices = self.devices.filter({ !SPB.1.contains($0.address) })
        }

        self.callback(self.devices)
    }

    // MARK: - HIDDevices (connected ble peripherals to the mac: keyboard, mouse etc...)

    private func HIDDevices() -> [bleDevice] {
        guard let ioDevices = fetchIOService("AppleDeviceManagementHIDEventService") else {
            return []
        }

        var list: [bleDevice] = []
        ioDevices.filter { $0.object(forKey: "BluetoothDevice") as? Bool == true }.forEach {
            (d: NSDictionary) in
            guard let name = d.object(forKey: "Product") as? String,
                let batteryPercent = d.object(forKey: "BatteryPercent") as? Int
            else {
                return
            }

            var address: String = ""
            if let addr = d.object(forKey: "DeviceAddress") as? String, !addr.isEmpty {
                address = addr
            } else if let addr = d.object(forKey: "SerialNumber") as? String, !addr.isEmpty {
                address = addr
            } else if let bleAddr = d.object(forKey: "BD_ADDR") as? Data,
                let addr = String(data: bleAddr, encoding: .utf8), !addr.isEmpty
            {
                address = addr
            }

            if address.isEmpty {
                return
            }

            list.append(
                bleDevice(
                    name: name,
                    address: address.replacingOccurrences(of: ":", with: "-").lowercased(),
                    uuid: nil,
                    batteryLevel: [KeyValue_t(key: "battery", value: "\(batteryPercent)")],
                    isConnected: true
                ))
        }

        return list
    }

    // MARK: - Cache

    private func cacheDevices() -> [bleDevice] {
        guard let cache = UserDefaults(suiteName: "/Library/Preferences/com.apple.Bluetooth"),
            let deviceCache = cache.object(forKey: "DeviceCache") as? [String: [String: Any]],
            let pairedDevices = cache.object(forKey: "PairedDevices") as? [String],
            let coreCache = cache.object(forKey: "CoreBluetoothCache") as? [String: [String: Any]]
        else {
            return []
        }

        var list: [bleDevice] = []
        deviceCache.filter({ pairedDevices.contains($0.key) }).forEach {
            (address: String, dict: [String: Any]) in
            let name = dict.first { $0.key == "Name" }?.value as? String
            var uuid: UUID? = nil
            var batteryLevel: [KeyValue_t] = []

            for key in [
                "BatteryPercent", "BatteryPercentCase", "BatteryPercentLeft", "BatteryPercentRight",
            ] {
                if let pair = dict.first(where: { $0.key == key }) {
                    var percentage: Int = 0
                    switch pair.value {
                    case let value as Int:
                        percentage = value
                        if percentage == 1 {
                            percentage *= 100
                        }
                    case let value as Double:
                        percentage = Int(value * 100)
                    default: continue
                    }

                    batteryLevel.append(KeyValue_t(key: key, value: "\(percentage)"))
                }
            }

            coreCache.forEach { (key: String, dict: [String: Any]) in
                guard let field = dict.first(where: { $0.key == "DeviceAddress" }),
                    let value = field.value as? String,
                    value == address
                else {
                    return
                }
                uuid = UUID(uuidString: key)
            }

            list.append(
                bleDevice(
                    name: name,
                    address: address.replacingOccurrences(of: ":", with: "-").lowercased(),
                    uuid: uuid,
                    batteryLevel: batteryLevel,
                    isPaired: true
                ))
        }

        return list
    }

    // MARK: - system_profiler

    private func profilerDevices() -> ([bleDevice], [String]) {
        if #unavailable(macOS 11) { return ([], []) }

        guard
            let res = process(
                path: "/usr/sbin/system_profiler", arguments: ["SPBluetoothDataType", "-json"])
        else {
            return ([], [])
        }

        var list: [bleDevice] = []
        var notConnected: [String] = []
        do {
            if let json = try JSONSerialization.jsonObject(with: Data(res.utf8), options: [])
                as? [String: Any]
            {
                guard let arr = json["SPBluetoothDataType"] as? [[String: Any]],
                    let data = arr.first
                else {
                    return (list, notConnected)
                }

                if let rawList = data["device_connected"] as? [[String: [String: Any]]],
                    let devices = rawList.first
                {
                    for obj in devices {
                        var batteryLevel: [KeyValue_t] = []

                        for key in [
                            "device_batteryLevelCase", "device_batteryLevelLeft",
                            "device_batteryLevelRight", "Left Battery Level", "Right Battery Level",
                            "device_batteryLevelMain",
                        ] {
                            if let pair = obj.value.first(where: { $0.key == key }) {
                                batteryLevel.append(
                                    KeyValue_t(
                                        key: key,
                                        value: (pair.value as? String)?.replacingOccurrences(
                                            of: "%", with: "") ?? "-1"))
                            }
                        }

                        let address = obj.value["device_address"] as? String ?? ""
                        if address.isEmpty { continue }

                        list.append(
                            bleDevice(
                                name: obj.key,
                                address: address.replacingOccurrences(of: ":", with: "-")
                                    .lowercased(),
                                batteryLevel: batteryLevel,
                                isConnected: true
                            ))
                    }
                }
                if let rawList = data["device_not_connected"] as? [[String: [String: String]]] {
                    for device in rawList {
                        for d in device.values {
                            if let addr = d["device_address"], !addr.isEmpty {
                                notConnected.append(
                                    addr.replacingOccurrences(of: ":", with: "-").lowercased())
                            }
                        }
                    }
                }
            }
        } catch let err as NSError {
            error("error to parse system_profiler SPBluetoothDataType: \(err.localizedDescription)")
            return (list, notConnected)
        }

        return (list, notConnected)
    }

    // MARK: - CBCentralManager

    func centralManagerDidUpdateState(_ central: CBCentralManager) {
        if central.state == .poweredOff {
            central.stopScan()
        } else if central.state == .poweredOn {
            central.scanForPeripherals(withServices: nil, options: nil)
        }
    }

    func centralManager(
        _ central: CBCentralManager, didDisconnectPeripheral peripheral: CBPeripheral, error: Error?
    ) {
        self.devicesToRemove.append(peripheral.identifier)
    }

    // MARK: - CBPeripheral

    func peripheral(_ peripheral: CBPeripheral, didDiscoverServices error: Error?) {
        guard error == nil else {
            error_msg("didDiscoverServices: \(error!)")
            return
        }

        guard
            let service = peripheral.services?.first(where: {
                $0.uuid == DevicesReader.batteryServiceUUID
            })
        else {
            error_msg("battery service not found, skipping")
            return
        }

        peripheral.discoverCharacteristics([DevicesReader.batteryCharacteristicsUUID], for: service)
    }

    func peripheral(_ peripheral: CBPeripheral, didModifyServices invalidatedServices: [CBService])
    {}

    func peripheral(
        _ peripheral: CBPeripheral, didDiscoverCharacteristicsFor service: CBService, error: Error?
    ) {
        guard error == nil else {
            error_msg("didDiscoverCharacteristicsFor: \(error!)")
            return
        }

        guard
            let batteryCharacteristics = service.characteristics?.first(where: {
                $0.uuid == DevicesReader.batteryCharacteristicsUUID
            })
        else {
            error_msg("characteristics not found")
            return
        }

        self.characteristicsDict[peripheral.identifier] = batteryCharacteristics
        peripheral.readValue(for: batteryCharacteristics)
    }

    func peripheral(
        _ peripheral: CBPeripheral, didUpdateValueFor characteristic: CBCharacteristic,
        error: Error?
    ) {
        guard error == nil else {
            error_msg("didUpdateValueFor: \(error!)")
            return
        }

        if let batteryLevel = characteristic.value?[0] {
            self.bleLevels[peripheral.identifier] = KeyValue_t(
                key: "battery", value: "\(batteryLevel)")
        }
    }
}
