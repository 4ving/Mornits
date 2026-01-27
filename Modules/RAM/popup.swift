//
//  popup.swift
//  Memory
//
//  Created by Serhiy Mytrovtsiy on 18/04/2020.
//  Using Swift 5.0.
//  Running on macOS 10.15.
//
//  Copyright © 2020 Serhiy Mytrovtsiy. All rights reserved.
//

import Cocoa
import Kit

internal class RAMInterfaceView: NSStackView {
    public var id: UUID?  // Nil for local
    public var isLocal: Bool { id == nil }
    public var name: String

    // UI Elements
    private var usageGauge: UsageGaugeView? = nil
    private var chart: LineChartView? = nil

    // Details Fields
    private var appField: NSTextField? = nil
    private var freeField: NSTextField? = nil

    private var appColorView: NSView? = nil
    private var freeColorView: NSView? = nil

    // Config
    private let dashboardHeight: CGFloat = 120

    private let detailsHeight: CGFloat = (22 * 2)
    private let processHeight: CGFloat = 22

    private var detailsState: Bool = true

    public var height: CGFloat {
        var h: CGFloat = self.dashboardHeight
        if self.detailsState {
            h += self.detailsHeight
        }
        return h
    }

    // Colors
    private var appColorState: SColor = .secondBlue
    private var appColor: NSColor {
        var value = NSColor.systemBlue
        if let color = self.appColorState.additional as? NSColor { value = color }
        return value
    }
    private var freeColorState: SColor = .lightGray
    private var freeColor: NSColor {
        self.freeColorState.additional as? NSColor ?? NSColor.systemBlue
    }

    private var viewContainer: NSStackView?
    private var detailsView: NSView?

    public init(id: UUID?, name: String) {
        self.id = id
        self.name = name

        super.init(frame: NSRect(x: 0, y: 0, width: Constants.Popup.width, height: 0))

        self.orientation = .vertical
        self.spacing = 0
        self.wantsLayer = true

        let key = self.isLocal ? "RAM_details" : "RAM_\(self.id?.uuidString ?? "")_details"
        self.detailsState = Store.shared.bool(key: key, defaultValue: true)

        self.loadColors()

        self.initDashboard()
        self.initDetails()
        self.updateCollapseState()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func loadColors() {
        self.appColorState = SColor.fromString(
            Store.shared.string(key: "RAM_appColor", defaultValue: self.appColorState.key))
        self.freeColorState = SColor.fromString(
            Store.shared.string(key: "RAM_freeColor", defaultValue: self.freeColorState.key))
    }

    public func reloadColors() {
        self.loadColors()

        if let view = self.appColorView {
            view.layer?.backgroundColor = self.appColor.cgColor
        }
        if let view = self.freeColorView {
            view.layer?.backgroundColor = self.freeColor.withAlphaComponent(0.5).cgColor
        }

        if let gauge = self.usageGauge {
            gauge.usedColor = self.appColor
            gauge.freeColor = self.freeColor.withAlphaComponent(0.5)
        }

        if let chart = self.chart {
            chart.color = self.appColor
            chart.needsDisplay = true
        }
    }

    private func initDashboard() {
        let view = NSView(
            frame: NSRect(x: 0, y: 0, width: Constants.Popup.width, height: self.dashboardHeight))
        view.heightAnchor.constraint(equalToConstant: self.dashboardHeight).isActive = true

        // Header
        let header = NSView(
            frame: NSRect(x: 0, y: self.dashboardHeight - 30, width: view.frame.width, height: 30))

        let label = LabelField(
            frame: NSRect(x: 0, y: (30 - 15) / 2, width: view.frame.width, height: 15), self.name)
        label.font = NSFont.systemFont(ofSize: 12, weight: .medium)
        label.textColor = .secondaryLabelColor
        label.alignment = .center

        let button = NSButtonWithPadding()
        button.frame = CGRect(x: view.frame.width - 18, y: 6, width: 18, height: 18)
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.imageScaling = NSImageScaling.scaleAxesIndependently
        button.contentTintColor = .lightGray
        button.action = #selector(self.toggleDetails)
        button.target = self
        button.toolTip = localizedString("Details")
        button.image = Bundle(for: Module.self).image(forResource: "tune")!

        header.addSubview(label)

        header.addSubview(button)

        view.addSubview(header)

        // Circles Container
        let container = NSView(
            frame: NSRect(x: 0, y: 0, width: view.frame.width, height: self.dashboardHeight - 30))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.lightGray.withAlphaComponent(0.1).cgColor
        container.layer?.cornerRadius = 3

        let centralWidth: CGFloat = container.frame.height - 20
        let sideWidth: CGFloat =
            (view.frame.width - centralWidth - (Constants.Popup.margins * 2)) / 2

        // Usage Gauge (Left side where PressureView was)
        let leftGaugeX = (sideWidth - 60) / 2

        self.usageGauge = UsageGaugeView(
            frame: NSRect(x: leftGaugeX, y: 20, width: 60, height: 50))
        self.usageGauge!.toolTip = localizedString("Memory usage")
        self.usageGauge!.usedColor = self.appColor
        self.usageGauge!.freeColor = self.freeColor.withAlphaComponent(0.5)
        view.addSubview(self.usageGauge!)

        // Chart
        let chartX = leftGaugeX + 60 + (Constants.Popup.margins * 2)
        let chartWidth = view.frame.width - chartX - (Constants.Popup.margins)
        self.chart = LineChartView(
            frame: NSRect(x: chartX, y: 10, width: chartWidth, height: container.frame.height - 20),
            num: 60, suffix: "%", color: self.appColor, scale: .linear, fixedScale: 1
        )
        self.chart!.toolTip = localizedString("Usage history")
        view.addSubview(self.chart!)

        view.addSubview(container)

        self.addArrangedSubview(view)
    }

    private func initDetails() {
        let view = NSView(
            frame: NSRect(x: 0, y: 0, width: Constants.Popup.width, height: self.detailsHeight))
        view.heightAnchor.constraint(equalToConstant: self.detailsHeight).isActive = true

        let container = NSStackView(
            frame: NSRect(x: 0, y: 0, width: view.frame.width, height: self.detailsHeight))
        container.orientation = .vertical
        container.spacing = 0

        (self.appColorView, _, self.appField) = popupWithColorRow(
            container, color: self.appColor, title: "\(localizedString("Used")):", value: "")
        (self.freeColorView, _, self.freeField) = popupWithColorRow(
            container, color: self.freeColor.withAlphaComponent(0.5),
            title: "\(localizedString("Free")):", value: "")

        view.addSubview(container)

        self.detailsView = view
        self.addArrangedSubview(view)
    }

    @objc private func toggleDetails() {
        self.detailsState = !self.detailsState
        let key = self.isLocal ? "RAM_details" : "RAM_\(self.id?.uuidString ?? "")_details"
        Store.shared.set(key: key, value: self.detailsState)

        self.updateCollapseState()
        NotificationCenter.default.post(name: .init("RAM_Interface_Resize"), object: nil)
    }

    private func updateCollapseState() {
        self.detailsView?.isHidden = !self.detailsState
    }

    public func update(value: RAM_Usage) {
        if self.isLocal {
            self.appField?.stringValue = Units(bytes: Int64(value.used)).getReadableMemory(
                style: .memory)
            self.freeField?.stringValue = Units(bytes: Int64(value.free)).getReadableMemory(
                style: .memory)

            self.usageGauge?.setValue(value.usage)
            self.usageGauge?.toolTip =
                "\(localizedString("Memory usage")): \(Int(value.usage * 100))%"

            self.chart?.addValue(value.usage)
        }
    }

    public func updateRemote(used: Int64, total: Int64) {
        let percentage = Double(used) / Double(total)
        self.usageGauge?.setValue(percentage)
        self.usageGauge?.toolTip = "\(localizedString("Memory usage")): \(Int(percentage * 100))%"

        self.appField?.stringValue = Units(bytes: used).getReadableMemory(style: .memory)
        self.freeField?.stringValue = Units(bytes: total - used).getReadableMemory(style: .memory)

        self.chart?.addValue(percentage)
    }

}

internal class Popup: PopupWrapper {
    private var stackView: NSStackView!
    private var interfaces: [RAMInterfaceView] = []

    private var processes: ProcessesView? = nil
    private var processesView: NSView? = nil

    private var localProcesses: [TopProcess] = []
    // Identify remote processes by server ID to avoid stale data
    private var remoteProcesses: [UUID: [RemoteProcess]] = [:]

    private let processHeight: CGFloat = 22
    private var numberOfProcesses: Int {
        Store.shared.int(key: "RAM_processes", defaultValue: 8)
    }
    private var processesHeight: CGFloat {
        (self.processHeight * CGFloat(self.numberOfProcesses))
            + (self.numberOfProcesses == 0 ? 0 : Constants.Popup.separatorHeight + 22)
    }

    public init(_ module: ModuleType) {
        super.init(module, frame: NSRect(x: 0, y: 0, width: Constants.Popup.width, height: 0))

        self.stackView = NSStackView()
        self.stackView.orientation = .vertical
        self.stackView.spacing = Constants.Popup.spacing

        self.addSubview(self.stackView)

        self.setupInterfaces()

        NotificationCenter.default.addObserver(
            self, selector: #selector(rebuildInterfaceList),
            name: .init("RemoteData_Settings_Updated"),
            object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(updateWindowSize), name: .init("RAM_Interface_Resize"),
            object: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    private func setupInterfaces() {
        self.interfaces.forEach { $0.removeFromSuperview() }
        self.interfaces.removeAll()

        if RemoteServersManager.shared.localEnabled {
            let name = Host.current().localizedName ?? localizedString("Local")
            let view = RAMInterfaceView(id: nil, name: name)
            self.interfaces.append(view)
            self.stackView.addArrangedSubview(view)
        }

        for server in RemoteServersManager.shared.servers.filter({ $0.enabled }) {
            let view = RAMInterfaceView(id: server.id, name: server.name)
            self.interfaces.append(view)
            self.stackView.addArrangedSubview(view)
        }

        self.setupProcesses()

        self.updateWindowSize()
    }

    private func setupProcesses() {
        self.processesView?.removeFromSuperview()
        self.processesView = nil
        self.processes = nil

        if self.numberOfProcesses == 0 { return }

        let view = NSView(
            frame: NSRect(x: 0, y: 0, width: Constants.Popup.width, height: self.processesHeight))
        view.heightAnchor.constraint(equalToConstant: self.processesHeight).isActive = true

        let separator = separatorView(
            localizedString("Top processes"),
            origin: NSPoint(x: 0, y: self.processesHeight - Constants.Popup.separatorHeight),
            width: view.frame.width
        )
        let container = ProcessesView(
            frame: NSRect(x: 0, y: 0, width: view.frame.width, height: separator.frame.origin.y),
            values: [(localizedString("Usage"), nil)],
            n: self.numberOfProcesses
        )
        self.processes = container

        view.addSubview(separator)
        view.addSubview(container)

        // Custom identifier to recognizing it in resize loop?
        // Or just check type. It is NSView, not RAMInterfaceView.
        self.processesView = view
        self.stackView.addArrangedSubview(view)
    }

    @objc private func rebuildInterfaceList() {
        DispatchQueue.main.async {
            self.setupInterfaces()
        }
    }

    @objc private func updateWindowSize() {
        var height: CGFloat = 0
        for view in self.stackView.arrangedSubviews {
            if let v = view as? RAMInterfaceView {
                height += v.height
            } else if view == self.processesView {
                height += self.processesHeight
            }
        }
        height +=
            CGFloat(max(0, self.stackView.arrangedSubviews.count - 1)) * self.stackView.spacing

        if self.frame.height != height {
            self.setFrameSize(NSSize(width: Constants.Popup.width, height: height))
            self.stackView.setFrameSize(NSSize(width: Constants.Popup.width, height: height))
            self.sizeCallback?(self.frame.size)
        }
    }

    public override func updateLayer() {}

    public func loadCallback(_ value: RAM_Usage) {
        DispatchQueue.main.async {
            if let localView = self.interfaces.first(where: { $0.isLocal }) {
                localView.update(value: value)
            }
        }

        // Update remote
        DispatchQueue.main.async {
            // Update remote views and data
            for view in self.interfaces.filter({ !$0.isLocal }) {
                guard let id = view.id, let data = RemoteServersManager.shared.data[id] else {
                    continue
                }
                view.updateRemote(used: data.ramUsed, total: data.ramTotal)
                self.remoteProcesses[id] = data.processes
            }

            // Clean up stale remote processes
            let activeIDs = self.interfaces.compactMap { $0.id }
            self.remoteProcesses = self.remoteProcesses.filter { activeIDs.contains($0.key) }

            self.mergeProcesses()
        }
    }

    public func processCallback(_ list: [TopProcess]) {
        self.localProcesses = list
        self.mergeProcesses()
    }

    private func mergeProcesses() {
        DispatchQueue.main.async {
            guard let container = self.processes else { return }

            var list: [(process: MergedProcess, usage: Int64, value: String)] = []

            // Add local
            if RemoteServersManager.shared.localEnabled {
                for p in self.localProcesses {
                    let name = "\(localizedString("Local")): \(p.name)"
                    let usage = Int64(p.usage)
                    let val = Units(bytes: usage).getReadableMemory(style: .memory)
                    let mp = MergedProcess(pid: p.pid, name: name, icon: p.icon)
                    list.append((mp, usage, val))
                }
            }

            // Add remote
            for (id, procs) in self.remoteProcesses {
                let serverName =
                    RemoteServersManager.shared.servers.first(where: { $0.id == id })?.name
                    ?? "Remote"
                for p in procs {
                    let name = "\(serverName): \(p.name)"
                    let usage = Int64(p.ram)
                    let val = Units(bytes: usage).getReadableMemory(style: .memory)
                    let mp = MergedProcess(
                        pid: p.pid, name: name, icon: Constants.defaultProcessIcon)
                    list.append((mp, usage, val))
                }
            }

            // Sort and clamp
            list.sort(by: { $0.usage > $1.usage })
            let top = Array(list.prefix(self.numberOfProcesses))

            if top.count != container.count { container.clear() }
            for i in 0..<top.count {
                let item = top[i]
                container.set(i, item.process, [item.value])
            }
        }
    }

    public func numberOfProcessesUpdated() {
        DispatchQueue.main.async {
            self.setupProcesses()
            self.updateWindowSize()
        }
    }

    // MARK: - Settings

    public override func settings() -> NSView? {
        let view = SettingsContainerView()

        view.addArrangedSubview(
            PreferencesSection([
                PreferencesRow(
                    localizedString("Keyboard shortcut"),
                    component: KeyboardShartcutView(
                        callback: self.setKeyboardShortcut,
                        value: self.keyboardShortcut
                    ))
            ]))

        view.addArrangedSubview(
            PreferencesSection([
                PreferencesRow(
                    localizedString("Used color"),
                    component: selectView(
                        action: #selector(toggleAppColor),
                        items: SColor.allColors,
                        selected: SColor.fromString(
                            Store.shared.string(
                                key: "RAM_appColor", defaultValue: SColor.secondBlue.key)
                        ).key
                    )),
                PreferencesRow(
                    localizedString("Free color"),
                    component: selectView(
                        action: #selector(toggleFreeColor),
                        items: SColor.allColors,
                        selected: SColor.fromString(
                            Store.shared.string(
                                key: "RAM_freeColor", defaultValue: SColor.lightGray.key)
                        ).key
                    )),
            ]))

        return view
    }

    @objc private func toggleAppColor(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        Store.shared.set(key: "RAM_appColor", value: key)
        self.interfaces.forEach { $0.reloadColors() }
    }
    @objc private func toggleFreeColor(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String else { return }
        Store.shared.set(key: "RAM_freeColor", value: key)
        self.interfaces.forEach { $0.reloadColors() }
    }
}

public class UsageGaugeView: NSView {
    public var usedColor: NSColor = .systemRed
    public var freeColor: NSColor = .systemBlue

    private var value: Double = 0

    public override init(frame: NSRect) {
        super.init(frame: frame)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func draw(_ rect: CGRect) {
        let arcWidth: CGFloat = 7.0
        let centerPoint = CGPoint(x: self.frame.width / 2, y: self.frame.height / 2)
        let radius = (min(self.frame.width, self.frame.height) - arcWidth) / 2

        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.setShouldAntialias(true)

        context.setLineWidth(arcWidth)
        context.setLineCap(.round)

        let startAngle: CGFloat = -(1 / 4) * CGFloat.pi
        // Total sweep 270 degrees (1.5 pi or 6/4 pi)
        let totalSweep: CGFloat = (7 / 4) * CGFloat.pi - (1 / 4) * CGFloat.pi
        let endCircle: CGFloat = totalSweep  // Used in loop to calculate segment arc length



        context.saveGState()
        context.translateBy(x: self.frame.width, y: 0)
        context.scaleBy(x: -1, y: 1)

        let val = max(0, min(1, self.value))

        // Draw Used Segment (Start to Current)
        let endUsed = startAngle + (CGFloat(val) * endCircle)
        context.setStrokeColor(self.usedColor.cgColor)
        context.addArc(
            center: centerPoint, radius: radius, startAngle: startAngle, endAngle: endUsed,
            clockwise: false)
        context.strokePath()

        // Draw Free Segment (Current to End)
        // Ensure we don't draw if full
        if val < 1 {
            let endFree = startAngle + endCircle  // Total end
            context.setStrokeColor(self.freeColor.cgColor)
            context.addArc(
                center: centerPoint, radius: radius, startAngle: endUsed, endAngle: endFree,
                clockwise: false)
            context.strokePath()
        }

        context.restoreGState()


        let needlePath = NSBezierPath()

        // Calculate angle for needle
        // Visual range: -225 deg (Start) to +45 deg (End) if passing clockwise?
        // Wait, PressureView segments start at -1/4 pi (-45 deg).
        // scale(-1, 1) flips X.
        // So visually on screen (without flip):
        // Start (left side): 225 deg?
        // End (right side): -45 deg?

        // Let's use simple logic: Map 0..1 to StartAngle..EndAngle (in context space).
        // Since we are NOT flipping X for the needle here (or should we?), let's calculate in standard space or apply same transform.
        // PressureView puts needle code AFTER restoreGState(). So it draws in standard coords.
        // Segments were drawn flipped.
        // StartAngle (flipped context): -45 deg.
        // Visual Start (Standard coords): 180 - (-45) = 225 deg?

        // Let's rely on standard Angles.
        // Gauge typical: 135 deg to 45 deg (clockwise) ?

        // Let's approximate:
        // 0% -> Bottom Left
        // 100% -> Bottom Right


        // Let's just use linear interpolation between two known visual angles.
        // Start: 225 degrees (5/4 pi)
        // End: -45 degrees (-1/4 pi)
        // Range: 270 degrees (3/2 pi) clockwise.

        let visualStart = (5 / 4) * CGFloat.pi  // 225 deg
        let visualTotal = -(3 / 2) * CGFloat.pi  // -270 deg (clockwise)

        let angle = visualStart + (val * visualTotal)

        // Draw needle logic (simplified relative to PressureView's specific shape)
        let needleLen = (min(self.bounds.width, self.bounds.height) / 2) - 4
        let cx = self.bounds.width / 2
        let cy = self.bounds.height / 2

        let tipX = cx + needleLen * cos(angle)
        let tipY = cy + needleLen * sin(angle)

        let baseWidth: CGFloat = 3
        let baseAngle1 = angle + CGFloat.pi / 2
        let baseAngle2 = angle - CGFloat.pi / 2

        let base1X = cx + baseWidth * cos(baseAngle1)
        let base1Y = cy + baseWidth * sin(baseAngle1)
        let base2X = cx + baseWidth * cos(baseAngle2)
        let base2Y = cy + baseWidth * sin(baseAngle2)

        needlePath.move(to: CGPoint(x: base1X, y: base1Y))
        needlePath.line(to: CGPoint(x: tipX, y: tipY))
        needlePath.line(to: CGPoint(x: base2X, y: base2Y))
        needlePath.close()

        (isDarkMode ? NSColor.white : NSColor.black).setFill()
        needlePath.fill()

        // Center dot
        let dot = NSBezierPath(
            ovalIn: NSRect(
                x: cx - baseWidth, y: cy - baseWidth, width: baseWidth * 2, height: baseWidth * 2))
        dot.fill()

        // Draw Percentage Text



        // Adjust Y to be below center or inside the arc at bottom?
        // Center is h/2. Radius is ~25.
        // Let's place it at the bottom center of the gauge to avoid overlapping with needle base if possible.
        // User asked "Below the needle", which usually means bottom center of the circle.
        // Let's adjust Y position.



        // Center alignment manually or rely onrect.
        // Let's create a centered paragraph style
        let style = NSMutableParagraphStyle()
        style.alignment = .center
        let centeredAttributes = [
            NSAttributedString.Key.font: NSFont.systemFont(ofSize: 9, weight: .medium),
            NSAttributedString.Key.foregroundColor: isDarkMode ? NSColor.white : NSColor.textColor,
            NSAttributedString.Key.paragraphStyle: style,
        ]

        let percentageStr = NSAttributedString(
            string: "\(Int(self.value * 100))%", attributes: centeredAttributes)
        percentageStr.draw(
            in: CGRect(x: 0, y: (self.frame.height / 2) - 15, width: self.frame.width, height: 12))
    }

    public func setValue(_ newValue: Double) {
        self.value = newValue
        if self.window?.isVisible ?? true {
            self.display()
        }
    }
}

private struct MergedProcess: Process_p {
    var pid: Int
    var name: String
    var icon: NSImage
}
