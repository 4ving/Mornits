//
//  main.swift
//  Disk
//
//  Created by Serhiy Mytrovtsiy on 07/05/2020.
//  Using Swift 5.0.
//  Running on macOS 10.15.
//
//  Copyright © 2020 Serhiy Mytrovtsiy. All rights reserved.
//

import Cocoa
import Kit
import WidgetKit

public struct stats: Codable {
    var read: Int64 = 0
    var write: Int64 = 0

    var readBytes: Int64 = 0
    var writeBytes: Int64 = 0
}

public struct smart_t: Codable {
    var temperature: Int = 0
    var life: Int = 0
    var totalRead: Int64 = 0
    var totalWritten: Int64 = 0
    var powerCycles: Int = 0
    var powerOnHours: Int = 0
}

public struct drive: Codable {
    var parent: io_object_t = 0

    var uuid: String = ""
    var mediaName: String = ""
    var BSDName: String = ""

    var root: Bool = false
    var removable: Bool = false
    var isNetwork: Bool = false

    var model: String = ""
    var path: URL?
    var connectionType: String = ""
    var fileSystem: String = ""

    var size: Int64 = 1
    var free: Int64 = 0

    var activity: stats = stats()
    var smart: smart_t? = nil

    public var percentage: Double {
        let total = self.size
        let free = self.free
        var usedSpace = total - free
        if usedSpace < 0 {
            usedSpace = 0
        }
        return Double(usedSpace) / Double(total)
    }

    public var popupState: Bool {
        Store.shared.bool(key: "Disk_\(self.uuid)_popup", defaultValue: true)
    }

    public func remote() -> String {
        return
            "\(self.uuid),\(self.size),\(self.size-self.free),\(self.free),\(self.activity.read),\(self.activity.write)"
    }
}

public class Disks: Codable, RemoteType {
    private var queue: DispatchQueue = DispatchQueue(
        label: "com.4ving.Mornits.Disk.SynchronizedArray")
    private var _array: [drive] = []
    public var array: [drive] {
        get { self.queue.sync { self._array } }
        set { self.queue.sync { self._array = newValue } }
    }

    enum CodingKeys: String, CodingKey {
        case array
    }

    required public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.array = try container.decode(Array<drive>.self, forKey: CodingKeys.array)
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(array, forKey: .array)
    }

    init() {}

    public var count: Int {
        var result = 0
        self.queue.sync { result = self._array.count }
        return result
    }

    // swiftlint:disable empty_count
    public var isEmpty: Bool {
        self.count == 0
    }
    // swiftlint:enable empty_count

    public func first(where predicate: (drive) -> Bool) -> drive? {
        return self.array.first(where: predicate)
    }

    public func index(where predicate: (drive) -> Bool) -> Int? {
        return self.array.firstIndex(where: predicate)
    }

    public func map<ElementOfResult>(_ transform: (drive) -> ElementOfResult?) -> [ElementOfResult]
    {
        return self.array.compactMap(transform)
    }

    public func reversed() -> [drive] {
        return self.array.reversed()
    }

    func forEach(_ body: (drive) -> Void) {
        self.array.forEach(body)
    }

    public func append(_ element: drive) {
        self.queue.sync {
            if !self._array.contains(where: { $0.BSDName == element.BSDName }) {
                self._array.append(element)
            }
        }
    }

    public func remove(at index: Int) {
        self.queue.sync {
            _ = self._array.remove(at: index)
        }
    }

    public func sort() {
        self.queue.sync {
            self._array.sort { $1.removable }
        }
    }

    func updateFreeSize(_ idx: Int, newValue: Int64) {
        self.queue.sync {
            if self._array.indices.contains(idx) {
                self._array[idx].free = newValue
            }
        }
    }

    func updateReadWrite(_ idx: Int, read: Int64, write: Int64) {
        self.queue.sync {
            if self._array.indices.contains(idx) {
                self._array[idx].activity.readBytes = read
                self._array[idx].activity.writeBytes = write
            }
        }
    }

    func updateRead(_ idx: Int, newValue: Int64) {
        self.queue.sync {
            if self._array.indices.contains(idx) {
                self._array[idx].activity.read = newValue
            }
        }
    }

    func updateWrite(_ idx: Int, newValue: Int64) {
        self.queue.sync {
            if self._array.indices.contains(idx) {
                self._array[idx].activity.write = newValue
            }
        }
    }

    func updateSMARTData(_ idx: Int, smart: smart_t?) {
        self.queue.sync {
            if self._array.indices.contains(idx) {
                self._array[idx].smart = smart
            }
        }
    }

    public func remote() -> Data? {
        var string = "\(self.array.count),"
        for (i, v) in self.array.enumerated() {
            string += v.remote()
            if i != self.array.count {
                string += ","
            }
        }
        string += "$"
        return string.data(using: .utf8)
    }
}

public struct Disk_process: Process_p, Codable {
    public var base: DataSizeBase {
        DataSizeBase(
            rawValue: Store.shared.string(
                key: "\(ModuleType.disk.stringValue)_base", defaultValue: "byte")) ?? .byte
    }

    public var pid: Int
    public var name: String
    public var icon: NSImage {
        if let app = NSRunningApplication(processIdentifier: pid_t(self.pid)) {
            return app.icon ?? Constants.defaultProcessIcon
        }
        return Constants.defaultProcessIcon
    }

    var read: Int
    var write: Int

    init(pid: Int, name: String, read: Int, write: Int) {
        self.pid = pid
        self.name = name
        self.read = read
        self.write = write

        if let app = NSRunningApplication(processIdentifier: pid_t(pid)) {
            if let name = app.localizedName {
                self.name = name
            }
        }
    }
}

public class Disk: Module {
    private let popupView: Popup = Popup(.disk)
    private let settingsView: DiskSettings = DiskSettings(.disk)
    private let portalView: Portal = Portal(.disk)
    private let notificationsView: Notifications = Notifications(.disk)

    private var capacityReader: CapacityReader?
    private var activityReader: ActivityReader?
    private var processReader: ProcessReader?

    private var selectedDisk: String = ""
    private var isLocalVisible: Bool = true

    private var textValue: String {
        Store.shared.string(
            key: "\(self.name)_textWidgetValue", defaultValue: "$capacity.free/$capacity.total")
    }

    private var systemWidgetsUpdatesState: Bool {
        Store.shared.bool(key: "systemWidgetsUpdates_state", defaultValue: true)
    }

    public init() {
        super.init(
            moduleType: .disk,
            popup: self.popupView,
            settings: self.settingsView,
            portal: self.portalView,
            notifications: self.notificationsView
        )
        guard self.available else { return }

        self.capacityReader = CapacityReader(.disk) { [weak self] value in
            if let value {
                self?.capacityCallback(value)
            }
        }
        self.activityReader = ActivityReader(.disk) { [weak self] value in
            if let value {
                self?.activityCallback(value)
            }
        }
        self.processReader = ProcessReader(.disk) { [weak self] value in
            if var list = value {
                if !RemoteServersManager.shared.localEnabled || !(self?.isLocalVisible ?? true) {
                    list.removeAll()
                } else {
                    for i in 0..<list.count {
                        list[i].name = "\(localizedString("Local")): \(list[i].name)"
                    }
                }

                RemoteServersManager.shared.servers.filter({ $0.enabled }).forEach { server in
                    if let data = RemoteServersManager.shared.data[server.id] {
                        // Check if any disk of this server is enabled in the widget
                        let isVisible = data.disks.contains { disk in
                            let uuid = "\(server.id.uuidString):\(disk.name)"
                            return Store.shared.bool(key: "Disk_state_\(uuid)", defaultValue: true)
                        }

                        if isVisible {
                            data.processes.forEach { p in
                                list.append(
                                    Disk_process(
                                        pid: p.pid, name: "\(server.name): \(p.name)", read: p.read,
                                        write: p.write))
                            }
                        }
                    }
                }

                list.sort { $0.read + $0.write > $1.read + $1.write }
                self?.popupView.processCallback(list)
            }
        }

        self.selectedDisk = Store.shared.string(
            key: "\(ModuleType.disk.stringValue)_disk", defaultValue: self.selectedDisk)

        self.settingsView.selectedDiskHandler = { [weak self] value in
            self?.selectedDisk = value
            self?.capacityReader?.read()
        }
        self.settingsView.callback = { [weak self] in
            self?.capacityReader?.read()
        }
        self.settingsView.setInterval = { [weak self] value in
            self?.capacityReader?.setInterval(value)
        }
        self.settingsView.callbackWhenUpdateNumberOfProcesses = { [weak self] in
            self?.popupView.numberOfProcessesUpdated()
            DispatchQueue.global(qos: .background).async {
                self?.processReader?.read()
            }
        }

        self.setReaders([self.capacityReader, self.activityReader, self.processReader])
    }

    private func capacityCallback(_ value: Disks) {
        guard self.enabled else { return }

        var hasVisibleLocal = false
        value.forEach { d in
            if Store.shared.bool(key: "Disk_state_\(d.mediaName)", defaultValue: d.root) {
                hasVisibleLocal = true
            }
        }
        self.isLocalVisible = hasVisibleLocal

        DispatchQueue.main.async(execute: {
            let combined = Disks()
            let filtered = Disks()

            if RemoteServersManager.shared.localEnabled {
                value.forEach { d in
                    combined.append(d)
                    if Store.shared.bool(key: "Disk_state_\(d.mediaName)", defaultValue: d.root) {
                        var localDisk = d
                        localDisk.mediaName = "\(localizedString("Local")): \(d.mediaName)"
                        filtered.append(localDisk)
                    }
                }
            }

            RemoteServersManager.shared.servers.filter({ $0.enabled }).forEach { server in
                if let data = RemoteServersManager.shared.data[server.id] {
                    data.disks.forEach { disk in
                        var d = drive()
                        d.mediaName = "\(server.name): \(disk.name)"
                        d.uuid = "\(server.id.uuidString):\(disk.name)"
                        d.BSDName = d.uuid
                        d.isNetwork = true
                        d.size = disk.size
                        d.free = disk.free

                        combined.append(d)
                        if Store.shared.bool(key: "Disk_state_\(d.uuid)", defaultValue: true) {
                            filtered.append(d)
                        }
                    }
                } else {
                    var d = drive()
                    d.mediaName = server.name
                    d.uuid = server.id.uuidString
                    d.BSDName = d.uuid
                    d.isNetwork = true
                    d.size = -1
                    d.free = -1

                    combined.append(d)
                    filtered.append(d)
                }
            }

            self.popupView.capacityCallback(filtered)
            self.settingsView.setList(combined)
        })

        var totalSize: Int64 = 0
        var totalFree: Int64 = 0
        var count: Int = 0

        // 1. Local Disks
        if RemoteServersManager.shared.localEnabled {
            value.forEach { d in
                if Store.shared.bool(key: "Disk_state_\(d.mediaName)", defaultValue: d.root) {
                    totalSize += d.size
                    totalFree += d.free
                    count += 1
                }
            }
        }

        // 2. Remote Disks
        RemoteServersManager.shared.servers.filter({ $0.enabled }).forEach { server in
            if let data = RemoteServersManager.shared.data[server.id] {
                data.disks.forEach { disk in
                    let id = "\(server.id.uuidString):\(disk.name)"
                    if Store.shared.bool(key: "Disk_state_\(id)", defaultValue: true) {
                        totalSize += disk.size
                        totalFree += disk.free
                        count += 1
                    }
                }
            }
        }

        var d = drive()
        if count > 0 {
            d.size = totalSize
            d.free = totalFree
        }

        self.portalView.utilizationCallback(d)
        self.notificationsView.utilizationCallback(d.percentage)

        self.menuBar.widgets.filter { $0.isActive }.forEach { (w: SWidget) in
            switch w.item {
            case let widget as Mini: widget.setValue(d.percentage)
            case let widget as BarChart: widget.setValue([[ColorValue(d.percentage)]])
            case let widget as MemoryWidget:
                widget.setValue(
                    (
                        DiskSize(d.free).getReadableMemory(),
                        DiskSize(d.size - d.free).getReadableMemory()
                    ), usedPercentage: d.percentage)
            case let widget as PieChart:
                widget.setValue([
                    circle_segment(value: d.percentage, color: NSColor.systemBlue)
                ])
            case let widget as TextWidget:
                var text = "\(self.textValue)"
                let pairs = TextWidget.parseText(text)
                pairs.forEach { pair in
                    var replacement: String? = nil

                    switch pair.key {
                    case "$capacity":
                        switch pair.value {
                        case "total": replacement = DiskSize(d.size).getReadableMemory()
                        case "used": replacement = DiskSize(d.size - d.free).getReadableMemory()
                        case "free": replacement = DiskSize(d.free).getReadableMemory()
                        default: return
                        }
                    case "$percentage":
                        var percentage: Int
                        switch pair.value {
                        case "used":
                            percentage = Int((Double(d.size - d.free) / Double(d.size)) * 100)
                        case "free": percentage = Int((Double(d.free) / Double(d.size)) * 100)
                        default: return
                        }
                        replacement = "\(percentage < 0 ? 0 : percentage)%"
                    default: return
                    }

                    if let replacement {
                        let key = pair.value.isEmpty ? pair.key : "\(pair.key).\(pair.value)"
                        text = text.replacingOccurrences(of: key, with: replacement)
                    }
                }
                widget.setValue(text)
            default: break
            }
        }

        if self.systemWidgetsUpdatesState {
            if #available(macOS 11.0, *) {
                if let blobData = try? JSONEncoder().encode(d) {
                    self.exportWidgetData(blobData, forKey: "Disk@CapacityReader")
                }
                WidgetCenter.shared.reloadTimelines(ofKind: Disk_entry.kind)
                WidgetCenter.shared.reloadTimelines(ofKind: "UnitedWidget")
            }
        }
    }

    private func activityCallback(_ value: Disks) {
        guard self.enabled else { return }

        DispatchQueue.main.async(execute: {
            self.popupView.activityCallback(value)
        })

        var read: Int64 = 0
        var write: Int64 = 0
        var count: Int = 0

        // 1. Local
        if RemoteServersManager.shared.localEnabled {
            value.forEach { d in
                if Store.shared.bool(key: "Disk_state_\(d.mediaName)", defaultValue: d.root) {
                    read += d.activity.read
                    write += d.activity.write
                    count += 1
                }
            }
        }

        // 2. Remote
        RemoteServersManager.shared.servers.filter({ $0.enabled }).forEach { server in
            if let data = RemoteServersManager.shared.data[server.id] {
                let isAnySelected = data.disks.contains(where: { disk in
                    let id = "\(server.id.uuidString):\(disk.name)"
                    return Store.shared.bool(key: "Disk_state_\(id)", defaultValue: false)
                })

                if isAnySelected {
                    // Sum up stats from selected physical disks
                    data.disks.forEach { disk in
                        let id = "\(server.id.uuidString):\(disk.name)"
                        let isSelected = Store.shared.bool(
                            key: "Disk_state_\(id)", defaultValue: false)

                        if isSelected {
                            read += disk.read
                            write += disk.write
                            count += 1
                        }
                    }
                }
            }
        }

        var d = drive()
        d.activity.read = read
        d.activity.write = write

        self.portalView.activityCallback(d)

        DispatchQueue.main.async(execute: {
            let filtered = Disks()

            if RemoteServersManager.shared.localEnabled {
                value.forEach { d in
                    if Store.shared.bool(key: "Disk_state_\(d.mediaName)", defaultValue: d.root) {
                        var localDisk = d
                        localDisk.mediaName = "\(localizedString("Local")): \(d.mediaName)"
                        filtered.append(localDisk)
                    }
                }
            }

            RemoteServersManager.shared.servers.filter({ $0.enabled }).forEach { server in
                if let data = RemoteServersManager.shared.data[server.id] {
                    data.disks.forEach { disk in
                        var d = drive()
                        d.mediaName = "\(server.name): \(disk.name)"
                        d.uuid = "\(server.id.uuidString):\(disk.name)"
                        d.BSDName = d.uuid
                        d.isNetwork = true

                        var act = stats()
                        act.read = disk.read
                        act.write = disk.write
                        act.readBytes = disk.totalRead
                        act.writeBytes = disk.totalWrite
                        d.activity = act

                        if Store.shared.bool(key: "Disk_state_\(d.uuid)", defaultValue: true) {
                            filtered.append(d)
                        }
                    }
                } else {
                    var d = drive()
                    d.mediaName = server.name
                    d.uuid = server.id.uuidString
                    d.BSDName = d.uuid
                    d.isNetwork = true

                    filtered.append(d)
                }
            }

            self.popupView.activityCallback(filtered)
        })

        self.menuBar.widgets.filter { $0.isActive }.forEach { (w: SWidget) in
            switch w.item {
            case let widget as SpeedWidget:
                widget.setValue(input: d.activity.read, output: d.activity.write)
            case let widget as NetworkChart:
                widget.setValue(upload: Double(d.activity.write), download: Double(d.activity.read))
                if self.capacityReader?.interval != 1 {
                    self.settingsView.setUpdateInterval(value: 1)
                }
            default: break
            }
        }
    }
}
