//
//  main.swift
//  Memory
//
//  Created by Serhiy Mytrovtsiy on 12/04/2020.
//  Using Swift 5.0.
//  Running on macOS 10.15.
//
//  Copyright © 2020 Serhiy Mytrovtsiy. All rights reserved.
//

import Cocoa
import Kit
import WidgetKit

public struct RAM_Usage: Codable, RemoteType {
    var total: Double
    var used: Double
    var free: Double

    var active: Double
    var inactive: Double
    var wired: Double
    var compressed: Double

    var app: Double
    var cache: Double

    var swap: Swap
    var pressure: Pressure

    var swapins: Int64
    var swapouts: Int64

    public var usage: Double {
        Double((self.total - self.free) / self.total)
    }

    public func remote() -> Data? {
        let string = "\(self.total),\(self.used),\(self.pressure.level),\(self.swap.used)$"
        return string.data(using: .utf8)
    }
}

public struct Swap: Codable {
    var total: Double
    var used: Double
    var free: Double
}

public struct Pressure: Codable {
    let level: Int
    let value: RAMPressure
}

public class RAM: Module {
    private let popupView: Popup
    private let settingsView: RAMSettings
    private let portalView: Portal
    private let notificationsView: Notifications

    private var usageReader: UsageReader? = nil
    private var processReader: ProcessReader? = nil

    private var splitValueState: Bool {
        return Store.shared.bool(key: "\(self.config.name)_splitValue", defaultValue: false)
    }
    private var appColor: NSColor {
        let color = SColor.secondBlue
        let key = Store.shared.string(key: "\(self.config.name)_appColor", defaultValue: color.key)
        if let c = SColor.fromString(key).additional as? NSColor {
            return c
        }
        return color.additional as! NSColor
    }
    private var wiredColor: NSColor {
        let color = SColor.secondOrange
        let key = Store.shared.string(
            key: "\(self.config.name)_wiredColor", defaultValue: color.key)
        if let c = SColor.fromString(key).additional as? NSColor {
            return c
        }
        return color.additional as! NSColor
    }
    private var compressedColor: NSColor {
        let color = SColor.pink
        let key = Store.shared.string(
            key: "\(self.config.name)_compressedColor", defaultValue: color.key)
        if let c = SColor.fromString(key).additional as? NSColor {
            return c
        }
        return color.additional as! NSColor
    }

    private var textValue: String {
        Store.shared.string(
            key: "\(self.name)_textWidgetValue",
            defaultValue: "$mem.used/$mem.total ($pressure.value)")
    }

    private var systemWidgetsUpdatesState: Bool {
        Store.shared.bool(key: "systemWidgetsUpdates_state", defaultValue: true)
    }

    public init() {
        self.settingsView = RAMSettings(.RAM)
        self.popupView = Popup(.RAM)
        self.portalView = Portal(.RAM)
        self.notificationsView = Notifications(.RAM)

        super.init(
            moduleType: .RAM,
            popup: self.popupView,
            settings: self.settingsView,
            portal: self.portalView,
            notifications: self.notificationsView
        )
        guard self.available else { return }

        self.settingsView.callback = { [weak self] in
            self?.usageReader?.read()
        }
        self.settingsView.setInterval = { [weak self] value in
            self?.processReader?.read()
            self?.usageReader?.setInterval(value)
        }
        self.settingsView.setTopInterval = { [weak self] value in
            self?.processReader?.setInterval(value)
        }

        self.usageReader = UsageReader(.RAM) { [weak self] value in
            self?.loadCallback(value)
        }
        self.processReader = ProcessReader(.RAM) { [weak self] value in
            if let list = value {
                self?.popupView.processCallback(list)
            }
        }

        self.settingsView.callbackWhenUpdateNumberOfProcesses = { [weak self] in
            self?.popupView.numberOfProcessesUpdated()
            DispatchQueue.global(qos: .background).async {
                self?.processReader?.read()
            }
        }

        self.setReaders([self.usageReader, self.processReader])

        NotificationCenter.default.addObserver(
            self, selector: #selector(self.remoteUpdate), name: .init("RemoteData_Updated"),
            object: nil)
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func remoteUpdate() {
        self.portalView.callback(self.portalUsage())
        self.updateWidgets()
    }

    private var lastLocalUsage: RAM_Usage? = nil

    private func loadCallback(_ raw: RAM_Usage?) {
        guard let value = raw, self.enabled else { return }

        self.lastLocalUsage = value
        self.popupView.loadCallback(value)
        self.portalView.callback(self.portalUsage(value))
        self.notificationsView.loadCallback(value)

        self.updateWidgets()
    }

    // Aggregates local and remote usage for the Portal
    private func portalUsage(_ local: RAM_Usage? = nil) -> RAM_Usage {
        var list: [RAM_Usage] = []

        if let local = local ?? self.lastLocalUsage {
            if RemoteServersManager.shared.localEnabled {
                list.append(local)
            }
        }

        let servers = RemoteServersManager.shared.servers.filter({ $0.enabled })
        for server in servers {
            if let data = RemoteServersManager.shared.data[server.id] {
                // Construct a partial RAM_Usage from RemoteData
                // RemoteData has ramTotal and ramUsed in Int64 bytes. RAM_Usage uses Double.
                // We treat all remote used memory as "App" memory for the breakdown since we don't have details.
                let total = Double(data.ramTotal)
                let used = Double(data.ramUsed)
                let free = total - used

                let usage = RAM_Usage(
                    total: total,
                    used: used,
                    free: free,
                    active: 0,
                    inactive: 0,
                    wired: 0,
                    compressed: 0,
                    app: used,  // Attribute to App
                    cache: 0,
                    swap: Swap(total: 0, used: 0, free: 0),
                    pressure: Pressure(level: 0, value: .normal),
                    swapins: 0,
                    swapouts: 0
                )
                list.append(usage)
            }
        }

        guard !list.isEmpty else {
            return local
                ?? RAM_Usage(
                    total: 0, used: 0, free: 0, active: 0, inactive: 0, wired: 0, compressed: 0,
                    app: 0, cache: 0, swap: Swap(total: 0, used: 0, free: 0),
                    pressure: Pressure(level: 0, value: .normal), swapins: 0, swapouts: 0)
        }

        if list.count == 1 {
            return list.first!
        }

        // Sum up
        var total: Double = 0
        var used: Double = 0
        var free: Double = 0
        var active: Double = 0
        var inactive: Double = 0
        var wired: Double = 0
        var compressed: Double = 0
        var app: Double = 0
        var cache: Double = 0

        for item in list {
            total += item.total
            used += item.used
            free += item.free
            active += item.active
            inactive += item.inactive
            wired += item.wired
            compressed += item.compressed
            app += item.app
            cache += item.cache
        }

        // Use local swap/pressure if available (or first item's)
        let swap = list.first?.swap ?? Swap(total: 0, used: 0, free: 0)
        let pressure = list.first?.pressure ?? Pressure(level: 0, value: .normal)

        return RAM_Usage(
            total: total,
            used: used,
            free: free,
            active: active,
            inactive: inactive,
            wired: wired,
            compressed: compressed,
            app: app,
            cache: cache,
            swap: swap,
            pressure: pressure,
            swapins: 0,
            swapouts: 0
        )
    }

    private func updateWidgets() {
        guard let value = self.lastLocalUsage else { return }

        // Aggregation logic for widgets
        var totalPercent: Double = 0
        var count: Double = 0

        if RemoteServersManager.shared.localEnabled {
            totalPercent += value.usage
            count += 1
        }

        let servers = RemoteServersManager.shared.servers.filter({ $0.enabled })
        for server in servers {
            if let data = RemoteServersManager.shared.data[server.id], let ram = data.ram {
                totalPercent += ram
                count += 1
            }
        }

        var categoryValue = value
        if count > 0 {
            let avg = totalPercent / count
            categoryValue.used = value.total * avg
            categoryValue.free = value.total - categoryValue.used

            // Re-calculate app/wired/compressed proportions based on new used?
            // Or just scale them?
            // The widget usually only uses .usage percentage or total Used string.
            // If the widget uses 'value.app', it might look weird if we don't scale it.
            // But strict "usage" percentage is what matters most for bar charts/gauges.
            // Let's just update 'used' and 'free' which drives 'usage' property.
        } else if !RemoteServersManager.shared.localEnabled {
            // No local, no remote -> 0 usage? or keep as is?
            // If local is disabled and no servers, usage should probably be 0 or empty.
            categoryValue.used = 0
            categoryValue.free = value.total
        }

        let total: Double = categoryValue.total == 0 ? 1 : categoryValue.total
        self.menuBar.widgets.filter { $0.isActive }.forEach { (w: SWidget) in
            switch w.item {
            case let widget as Mini:
                widget.setValue(categoryValue.usage)
                widget.setPressure(categoryValue.pressure.value)
            case let widget as LineChart:
                widget.setValue(categoryValue.usage)
                widget.setPressure(categoryValue.pressure.value)
            case let widget as BarChart:
                if self.splitValueState {
                    widget.setValue([
                        [
                            ColorValue(categoryValue.app / total, color: self.appColor),
                            ColorValue(categoryValue.wired / total, color: self.wiredColor),
                            ColorValue(
                                categoryValue.compressed / total, color: self.compressedColor),
                        ]
                    ])
                } else {
                    widget.setValue([[ColorValue(categoryValue.usage)]])
                    widget.setColorZones((0.8, 0.95))
                    widget.setPressure(categoryValue.pressure.value)
                }
            case let widget as PieChart:
                widget.setValue([
                    circle_segment(value: categoryValue.app / total, color: self.appColor),
                    circle_segment(value: categoryValue.wired / total, color: self.wiredColor),
                    circle_segment(
                        value: categoryValue.compressed / total, color: self.compressedColor),
                ])
            case let widget as MemoryWidget:
                let free = Units(bytes: Int64(categoryValue.free)).getReadableMemory(style: .memory)
                let used = Units(bytes: Int64(categoryValue.used)).getReadableMemory(style: .memory)
                widget.setValue((free, used), usedPercentage: categoryValue.usage)
                widget.setPressure(categoryValue.pressure.value)
            case let widget as Tachometer:
                widget.setValue([
                    circle_segment(value: categoryValue.app / total, color: self.appColor),
                    circle_segment(value: categoryValue.wired / total, color: self.wiredColor),
                    circle_segment(
                        value: categoryValue.compressed / total, color: self.compressedColor),
                ])
            case let widget as TextWidget:
                var text = "\(self.textValue)"
                let pairs = TextWidget.parseText(text)
                pairs.forEach { pair in
                    var replacement: String? = nil

                    switch pair.key {
                    case "$mem":
                        switch pair.value {
                        case "total":
                            replacement = Units(bytes: Int64(categoryValue.total))
                                .getReadableMemory(style: .memory)
                        case "used":
                            replacement = Units(bytes: Int64(categoryValue.used)).getReadableMemory(
                                style: .memory)
                        case "free":
                            replacement = Units(bytes: Int64(categoryValue.free)).getReadableMemory(
                                style: .memory)
                        case "active":
                            replacement = Units(bytes: Int64(categoryValue.active))
                                .getReadableMemory(style: .memory)
                        case "inactive":
                            replacement = Units(bytes: Int64(categoryValue.inactive))
                                .getReadableMemory(style: .memory)
                        case "wired":
                            replacement = Units(bytes: Int64(categoryValue.wired))
                                .getReadableMemory(style: .memory)
                        case "compressed":
                            replacement = Units(bytes: Int64(categoryValue.compressed))
                                .getReadableMemory(style: .memory)
                        case "app":
                            replacement = Units(bytes: Int64(categoryValue.app)).getReadableMemory(
                                style: .memory)
                        case "cache":
                            replacement = Units(bytes: Int64(categoryValue.cache))
                                .getReadableMemory(style: .memory)
                        case "swapins": replacement = "\(categoryValue.swapins)"
                        case "swapouts": replacement = "\(categoryValue.swapouts)"
                        default: return
                        }
                    case "$swap":
                        switch pair.value {
                        case "total":
                            replacement = Units(bytes: Int64(categoryValue.swap.total))
                                .getReadableMemory(style: .memory)
                        case "used":
                            replacement = Units(bytes: Int64(categoryValue.swap.used))
                                .getReadableMemory(style: .memory)
                        case "free":
                            replacement = Units(bytes: Int64(categoryValue.swap.free))
                                .getReadableMemory(style: .memory)
                        default: return
                        }
                    case "$pressure":
                        switch pair.value {
                        case "level": replacement = "\(categoryValue.pressure.level)"
                        case "value": replacement = categoryValue.pressure.value.rawValue
                        default: return
                        }
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
                if isWidgetActive(self.userDefaults, [RAM_entry.kind, "UnitedWidget"]),
                    let blobData = try? JSONEncoder().encode(categoryValue)
                {
                    self.userDefaults?.set(blobData, forKey: "RAM@UsageReader")
                }
                WidgetCenter.shared.reloadTimelines(ofKind: RAM_entry.kind)
                WidgetCenter.shared.reloadTimelines(ofKind: "UnitedWidget")
            }
        }
    }
}
