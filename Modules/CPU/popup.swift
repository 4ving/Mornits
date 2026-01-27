//
//  popup.swift
//  CPU
//
//  Created by Serhiy Mytrovtsiy on 15/04/2020.
//  Using Swift 5.0.
//  Running on macOS 10.15.
//
//  Copyright © 2020 Serhiy Mytrovtsiy. All rights reserved.
//

import Cocoa
import Kit

internal class Popup: PopupWrapper {
    private let moduleType: ModuleType
    private var interfaces: [CPUInterfaceView] = []
    private var processesView: NSView? = nil
    private var processes: ProcessesView? = nil
    private var localProcesses: [TopProcess] = []
    private var lastTopList: [TopProcess] = []

    private var numberOfProcesses: Int {
        Store.shared.int(key: "\(self.title)_processes", defaultValue: 8)
    }
    private var processHeight: CGFloat {
        (22 * CGFloat(self.numberOfProcesses))
            + (self.numberOfProcesses == 0 ? 0 : Constants.Popup.separatorHeight + 22)
    }

    public init(_ module: ModuleType) {
        self.moduleType = module
        super.init(module, frame: NSRect(x: 0, y: 0, width: Constants.Popup.width, height: 0))

        self.spacing = 0
        self.orientation = .vertical

        self.setupInterfaces()

        NotificationCenter.default.addObserver(
            self, selector: #selector(rebuildInterfaceList),
            name: .init("RemoteData_Settings_Updated"), object: nil)
        NotificationCenter.default.addObserver(
            self, selector: #selector(updateWindowSize),
            name: .init("\(self.title)_Interface_Resize"), object: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public override func updateLayer() {
        self.interfaces.forEach { $0.updateLayer() }
    }

    public override func appear() {
        self.interfaces.forEach { $0.appear() }
    }

    public override func disappear() {
        self.interfaces.forEach { $0.disappear() }
        self.processes?.setLock(false)
    }

    private func setupInterfaces() {
        self.interfaces.forEach { $0.removeFromSuperview() }
        self.interfaces = []

        if RemoteServersManager.shared.localEnabled {
            let local = CPUInterfaceView(title: self.title, type: self.moduleType)
            self.addArrangedSubview(local)
            self.interfaces.append(local)
        }

        // Remote
        for server in RemoteServersManager.shared.servers.filter({ $0.enabled }) {
            let view = CPUInterfaceView(
                title: self.title, type: self.moduleType, id: server.id, name: server.name)
            self.addArrangedSubview(view)
            self.interfaces.append(view)
        }

        self.setupProcesses()
        self.updateWindowSize()
    }

    private func setupProcesses() {
        self.processesView?.removeFromSuperview()
        self.processesView = nil
        self.processes = nil

        if self.numberOfProcesses == 0 { return }

        let view: NSView = NSView(
            frame: NSRect(x: 0, y: 0, width: Constants.Popup.width, height: self.processHeight))
        view.heightAnchor.constraint(equalToConstant: self.processHeight).isActive = true

        let separator = separatorView(
            localizedString("Top processes"),
            origin: NSPoint(x: 0, y: self.processHeight - Constants.Popup.separatorHeight),
            width: view.frame.width)
        let container: ProcessesView = ProcessesView(
            frame: NSRect(x: 0, y: 0, width: view.frame.width, height: separator.frame.origin.y),
            values: [(localizedString("Usage"), nil)],
            n: self.numberOfProcesses
        )
        self.processes = container

        view.addSubview(separator)
        view.addSubview(container)

        self.processesView = view
        self.addArrangedSubview(view)
    }

    @objc private func rebuildInterfaceList() {
        DispatchQueue.main.async {
            self.setupInterfaces()
        }
    }

    @objc private func updateWindowSize() {
        var h: CGFloat = 0
        for view in self.arrangedSubviews {
            if let v = view as? CPUInterfaceView {
                h += v.height
            } else if view == self.processesView {
                h += self.processHeight
            }
        }

        // Add spacing? NSStackView spacing is 0.

        if self.frame.size.height != h {
            self.setFrameSize(NSSize(width: Constants.Popup.width, height: h))
            self.sizeCallback?(self.frame.size)
        }
    }

    // MARK: - Callbacks

    public func loadCallback(_ value: CPU_Load) {
        // Update local
        DispatchQueue.main.async {
            self.interfaces.first(where: { $0.isLocal })?.update(value)
        }

        // Update remote
        DispatchQueue.main.async {
            for view in self.interfaces.filter({ !$0.isLocal }) {
                guard let id = view.id, let data = RemoteServersManager.shared.data[id] else {
                    continue
                }
                view.updateRemote(data)
            }
        }
    }

    public func temperatureCallback(_ value: Double?) {
        self.interfaces.first(where: { $0.isLocal })?.temperatureCallback(value)
    }

    public func frequencyCallback(_ value: CPU_Frequency?) {
        self.interfaces.first(where: { $0.isLocal })?.frequencyCallback(value)
    }

    public func limitCallback(_ value: CPU_Limit?) {
        self.interfaces.first(where: { $0.isLocal })?.limitCallback(value)
    }

    public func averageCallback(_ value: CPU_AverageLoad?) {
        self.interfaces.first(where: { $0.isLocal })?.averageCallback(value)
    }

    public func processCallback(_ list: [TopProcess]?) {
        guard let list else { return }

        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }
            if !(self.window?.isVisible ?? false) {
                return
            }

            let remoteData = RemoteServersManager.shared.data
            let servers = RemoteServersManager.shared.servers
            let limit = self.processes?.count ?? 5

            DispatchQueue.global(qos: .userInitiated).async {
                var combined: [TopProcess] = []

                // Add Local
                if RemoteServersManager.shared.localEnabled {
                    for p in list {
                        var newP = p
                        newP.name = "\(localizedString("Local")): \(p.name)"
                        combined.append(newP)
                    }
                }

                // Add Remote
                // Add Remote
                for (uuid, stats) in remoteData {
                    guard let server = servers.first(where: { $0.id == uuid }), server.enabled
                    else { continue }
                    let serverName = server.name

                    // Filter and Sort per server first to limit items
                    // We only need top `limit` from each server to guarantee Global Top `limit`.
                    let candidateProcs = stats.processes
                        .filter { $0.cpu > 0.001 }
                        .sorted(by: { $0.cpu > $1.cpu })
                        .prefix(limit)

                    for rp in candidateProcs {
                        let usage = rp.cpu * 100
                        combined.append(
                            TopProcess(
                                pid: rp.pid, name: "\(serverName): \(rp.name)", usage: usage)
                        )
                    }
                }

                // Sort
                combined.sort { $0.usage > $1.usage }

                let topList = Array(combined.prefix(limit))

                DispatchQueue.main.async {
                    // Diff check to avoid UI thrashing
                    if self.processes?.count != topList.count {
                        self.processes?.clear()
                    } else if self.lastTopList.count == topList.count {
                        var changed = false
                        for i in 0..<topList.count {
                            let p1 = self.lastTopList[i]
                            let p2 = topList[i]
                            if p1.pid != p2.pid || p1.name != p2.name
                                || abs(p1.usage - p2.usage) > 0.1
                            {
                                changed = true
                                break
                            }
                        }
                        if !changed { return }
                    }

                    self.lastTopList = topList

                    for i in 0..<topList.count {
                        let process = topList[i]
                        self.processes?.set(i, process, ["\(Int(process.usage))%"])
                    }
                }
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

        if let localSettings = self.interfaces.first(where: { $0.isLocal })?.settings() {
            view.addArrangedSubview(localSettings)
        }

        return view
    }

}

internal class CPUInterfaceView: NSStackView {
    public let id: UUID?
    private let name: String

    public var isLocal: Bool { self.id == nil }

    public var height: CGFloat {
        var h: CGFloat = self.dashboardHeight + self.chartHeight
        if self.detailsState {
            h += self.detailsHeight + self.averageHeight + self.frequencyHeight
        }
        return h
    }

    private let title: String
    private let dashboardHeight: CGFloat = 120
    private var chartHeight: CGFloat {
        let h: CGFloat = 120
        if !self.isLocal { return 70 }
        return h
    }
    private var detailsHeight: CGFloat {
        if !self.isLocal {
            return (22 * 4) + Constants.Popup.separatorHeight
        }
        var count: CGFloat = isARM ? 4 : 6
        if SystemKit.shared.device.info.cpu?.eCores != nil { count += 1 }
        if SystemKit.shared.device.info.cpu?.pCores != nil { count += 1 }
        return (22 * count) + Constants.Popup.separatorHeight
    }
    private var detailsState: Bool = true
    private let averageHeight: CGFloat = (22 * 3) + Constants.Popup.separatorHeight
    private var frequencyHeight: CGFloat {
        var count: CGFloat = 1
        if isLocal && isARM {
            if SystemKit.shared.device.info.cpu?.eCores != nil { count += 1 }
            if SystemKit.shared.device.info.cpu?.pCores != nil { count += 1 }
        }
        return (22 * count) + Constants.Popup.separatorHeight
    }

    private var systemField: NSTextField? = nil
    private var userField: NSTextField? = nil
    private var idleField: NSTextField? = nil
    private var shedulerLimitField: NSTextField? = nil
    private var speedLimitField: NSTextField? = nil
    private var eCoresField: NSTextField? = nil
    private var pCoresField: NSTextField? = nil
    private var uptimeField: NSTextField? = nil
    private var average1Field: NSTextField? = nil
    private var average5Field: NSTextField? = nil
    private var average15Field: NSTextField? = nil
    private var coresFreqField: NSTextField? = nil
    private var eCoresFreqField: NSTextField? = nil
    private var pCoresFreqField: NSTextField? = nil

    private var systemColorView: NSView? = nil
    private var userColorView: NSView? = nil
    private var idleColorView: NSView? = nil
    private var eCoresColorView: NSView? = nil
    private var pCoresColorView: NSView? = nil
    private var eCoresFreqColorView: NSView? = nil
    private var pCoresFreqColorView: NSView? = nil

    private var circle: PieChartView? = nil
    private var temperatureCircle: HalfCircleGraphView? = nil
    private var frequencyCircle: HalfCircleGraphView? = nil
    private var lineChart: LineChartView? = nil
    private var barChart: BarChartView? = nil

    private var detailsView: NSView? = nil
    private var averageView: NSView? = nil
    private var frequenciesView: NSView? = nil

    private var chartPrefSection: PreferencesSection? = nil
    private var sliderView: NSView? = nil

    private var initialized: Bool = false
    private var maxFreq: Double = 0
    private var lineChartHistory: Int = 180
    private var lineChartScale: Scale = .none
    private var lineChartFixedScale: Double = 1

    private var systemColorState: SColor = .secondRed
    private var systemColor: NSColor {
        self.systemColorState.additional as? NSColor ?? NSColor.systemRed
    }
    private var userColorState: SColor = .secondBlue
    private var userColor: NSColor {
        self.userColorState.additional as? NSColor ?? NSColor.systemBlue
    }
    private var idleColorState: SColor = .lightGray
    private var idleColor: NSColor {
        self.idleColorState.additional as? NSColor ?? NSColor.lightGray
    }
    private var chartColorState: SColor = .systemAccent
    private var chartColor: NSColor {
        self.chartColorState.additional as? NSColor ?? NSColor.systemBlue
    }
    private var eCoresColorState: SColor = .teal
    private var eCoresColor: NSColor {
        self.eCoresColorState.additional as? NSColor ?? NSColor.systemTeal
    }
    private var pCoresColorState: SColor = .indigo
    private var pCoresColor: NSColor {
        self.pCoresColorState.additional as? NSColor ?? NSColor.systemBlue
    }

    init(title: String, type: ModuleType, id: UUID? = nil, name: String? = nil) {
        self.title = title
        self.id = id
        self.name = name ?? Host.current().localizedName ?? localizedString("Local")

        super.init(frame: NSRect(x: 0, y: 0, width: Constants.Popup.width, height: 0))

        self.spacing = 0
        self.orientation = .vertical

        self.loadSettings()

        self.addArrangedSubview(self.initDashboard())
        self.addArrangedSubview(self.initChart())
        self.addArrangedSubview(self.initDetails())
        self.addArrangedSubview(self.initAverage())
        self.addArrangedSubview(self.initFrequency())

        self.updateCollapseState()
        self.updateHeight()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func loadSettings() {
        self.systemColorState = SColor.fromString(
            Store.shared.string(
                key: "\(self.title)_systemColor", defaultValue: self.systemColorState.key))
        self.userColorState = SColor.fromString(
            Store.shared.string(
                key: "\(self.title)_userColor", defaultValue: self.userColorState.key))
        self.idleColorState = SColor.fromString(
            Store.shared.string(
                key: "\(self.title)_idleColor", defaultValue: self.idleColorState.key))
        self.chartColorState = SColor.fromString(
            Store.shared.string(
                key: "\(self.title)_chartColor", defaultValue: self.chartColorState.key))
        self.eCoresColorState = SColor.fromString(
            Store.shared.string(
                key: "\(self.title)_eCoresColor", defaultValue: self.eCoresColorState.key))
        self.pCoresColorState = SColor.fromString(
            Store.shared.string(
                key: "\(self.title)_pCoresColor", defaultValue: self.pCoresColorState.key))
        self.lineChartHistory = Store.shared.int(
            key: "\(self.title)_lineChartHistory", defaultValue: self.lineChartHistory)
        self.lineChartScale = Scale.fromString(
            Store.shared.string(
                key: "\(self.title)_lineChartScale", defaultValue: self.lineChartScale.key))
        self.lineChartFixedScale =
            Double(Store.shared.int(key: "\(self.title)_lineChartFixedScale", defaultValue: 100))
            / 100

        if self.isLocal {
            self.detailsState = Store.shared.bool(
                key: "\(self.title)_details", defaultValue: self.detailsState)
        } else {
            // Separate state for remote? or share? Shared for now or default true.
        }
    }

    public override func updateLayer() {
        self.lineChart?.display()
    }

    public func appear() {
        self.uptimeField?.stringValue = self.uptimeValue()
    }

    public func disappear() {}

    public func updateHeight() {
        if self.frame.size.height != self.height {
            self.setFrameSize(NSSize(width: self.frame.width, height: self.height))
            NotificationCenter.default.post(
                name: .init("\(self.title)_Interface_Resize"), object: nil)
        }
    }

    private func uptimeValue() -> String {
        let form = DateComponentsFormatter()
        form.maximumUnitCount = 2
        form.unitsStyle = .full
        form.allowedUnits = [.day, .hour, .minute]
        var value = localizedString("Unknown")
        if let bootDate = SystemKit.shared.device.bootDate {
            if let duration = form.string(from: bootDate, to: Date()) {
                value = duration
            }
        }
        return value
    }

    // MARK: - Views Init

    private func initDashboard() -> NSView {
        let view: NSView = NSView(
            frame: NSRect(x: 0, y: 0, width: self.frame.width, height: self.dashboardHeight))
        view.heightAnchor.constraint(equalToConstant: view.bounds.height).isActive = true

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

        // Content
        let container = NSView(
            frame: NSRect(x: 0, y: 0, width: view.frame.width, height: self.dashboardHeight - 30))

        let usageSize = self.dashboardHeight - 22 - 20
        let usageX = (view.frame.width - usageSize) / 2

        let usage = NSView(
            frame: NSRect(
                x: usageX, y: (container.frame.height - usageSize) / 2, width: usageSize,
                height: usageSize))
        let temperature = NSView(
            frame: NSRect(
                x: (usageX - 50) / 2, y: (container.frame.height - 50) / 2 - 3, width: 50,
                height: 50))
        let frequency = NSView(
            frame: NSRect(
                x: (usageX + usageSize) + (usageX - 50) / 2, y: 0, width: 50,
                height: container.frame.height))

        self.circle = PieChartView(
            frame: NSRect(x: 0, y: 0, width: usage.frame.width, height: usage.frame.height),
            segments: [], drawValue: true)
        self.circle!.toolTip = localizedString("CPU usage")
        usage.addSubview(self.circle!)

        self.temperatureCircle = HalfCircleGraphView(
            frame: NSRect(
                x: 0, y: 0, width: temperature.frame.width, height: temperature.frame.height))
        self.temperatureCircle!.toolTip = localizedString("CPU temperature")
        (self.temperatureCircle! as NSView).isHidden = true
        temperature.addSubview(self.temperatureCircle!)

        self.frequencyCircle = HalfCircleGraphView(
            frame: NSRect(x: 0, y: 0, width: frequency.frame.width, height: frequency.frame.height))
        self.frequencyCircle!.toolTip = localizedString("CPU frequency")
        (self.frequencyCircle! as NSView).isHidden = true
        frequency.addSubview(self.frequencyCircle!)

        container.addSubview(temperature)
        container.addSubview(usage)
        container.addSubview(frequency)
        view.addSubview(container)

        return view
    }

    private func initChart() -> NSView {
        let view: NSStackView = NSStackView(
            frame: NSRect(x: 0, y: 0, width: self.frame.width, height: self.chartHeight))
        view.heightAnchor.constraint(equalToConstant: view.bounds.height).isActive = true
        view.orientation = .vertical
        view.spacing = 0

        let lineChartContainer: NSView = {
            let box: NSView = NSView(frame: NSRect(x: 0, y: 0, width: self.frame.width, height: 70))
            box.heightAnchor.constraint(equalToConstant: box.frame.height).isActive = true
            box.wantsLayer = true
            box.layer?.backgroundColor = NSColor.lightGray.withAlphaComponent(0.1).cgColor
            box.layer?.cornerRadius = 3

            let chartFrame = NSRect(x: 1, y: 0, width: box.frame.width, height: box.frame.height)
            self.lineChart = LineChartView(
                frame: chartFrame, num: self.lineChartHistory, scale: self.lineChartScale,
                fixedScale: self.lineChartFixedScale)
            self.lineChart?.color = self.chartColor
            box.addSubview(self.lineChart!)

            return box
        }()

        view.addArrangedSubview(lineChartContainer)

        if self.isLocal, let cores = SystemKit.shared.device.info.cpu?.logicalCores {
            let barChartContainer: NSView = {
                let box: NSView = NSView(
                    frame: NSRect(x: 0, y: 0, width: self.frame.width, height: 50))
                box.heightAnchor.constraint(equalToConstant: box.frame.height).isActive = true
                box.wantsLayer = true
                box.layer?.backgroundColor = NSColor.lightGray.withAlphaComponent(0.1).cgColor
                box.layer?.cornerRadius = 3

                let chart = BarChartView(
                    frame: NSRect(
                        x: Constants.Popup.spacing,
                        y: Constants.Popup.spacing,
                        width: view.frame.width - (Constants.Popup.spacing * 2),
                        height: box.frame.height - (Constants.Popup.spacing * 2)
                    ), num: Int(cores))
                self.barChart = chart

                box.addSubview(chart)
                return box
            }()
            view.addArrangedSubview(barChartContainer)
        }

        return view
    }

    private func initDetails() -> NSView {
        let view: NSView = NSView(
            frame: NSRect(x: 0, y: 0, width: self.frame.width, height: self.detailsHeight))
        view.heightAnchor.constraint(equalToConstant: view.bounds.height).isActive = true
        let separator = separatorView(
            localizedString("Details"),
            origin: NSPoint(x: 0, y: self.detailsHeight - Constants.Popup.separatorHeight),
            width: self.frame.width)
        let container: NSStackView = NSStackView(
            frame: NSRect(x: 0, y: 0, width: view.frame.width, height: separator.frame.origin.y))
        container.orientation = .vertical
        container.spacing = 0

        (self.systemColorView, _, self.systemField) = popupWithColorRow(
            container, color: self.systemColor, title: "\(localizedString("System")):", value: "")
        (self.userColorView, _, self.userField) = popupWithColorRow(
            container, color: self.userColor, title: "\(localizedString("User")):", value: "")
        (self.idleColorView, _, self.idleField) = popupWithColorRow(
            container, color: self.idleColor.withAlphaComponent(0.5),
            title: "\(localizedString("Idle")):", value: "")

        if self.isLocal && !isARM {
            self.shedulerLimitField =
                popupRow(container, title: "\(localizedString("Scheduler limit")):", value: "").1
            self.speedLimitField =
                popupRow(container, title: "\(localizedString("Speed limit")):", value: "").1
        }

        if self.isLocal, SystemKit.shared.device.info.cpu?.eCores != nil {
            (self.eCoresColorView, _, self.eCoresField) = popupWithColorRow(
                container, color: self.eCoresColor,
                title: "\(localizedString("Efficiency cores")):", value: "")
        }
        if self.isLocal, SystemKit.shared.device.info.cpu?.pCores != nil {
            (self.pCoresColorView, _, self.pCoresField) = popupWithColorRow(
                container, color: self.pCoresColor,
                title: "\(localizedString("Performance cores")):", value: "")
        }

        self.uptimeField =
            popupRow(container, title: "\(localizedString("Uptime")):", value: self.uptimeValue()).1
        self.uptimeField?.font = NSFont.systemFont(ofSize: 11, weight: .regular)

        view.addSubview(separator)
        view.addSubview(container)

        self.detailsView = view
        return view
    }

    private func initAverage() -> NSView {
        let view: NSView = NSView(
            frame: NSRect(x: 0, y: 0, width: self.frame.width, height: self.averageHeight))
        view.heightAnchor.constraint(equalToConstant: view.bounds.height).isActive = true
        let separator = separatorView(
            localizedString("Average load"),
            origin: NSPoint(x: 0, y: self.averageHeight - Constants.Popup.separatorHeight),
            width: self.frame.width)
        let container: NSStackView = NSStackView(
            frame: NSRect(x: 0, y: 0, width: view.frame.width, height: separator.frame.origin.y))
        container.orientation = .vertical
        container.spacing = 0

        self.average1Field =
            popupRow(container, title: "\(localizedString("1 minute")):", value: "").1
        self.average5Field =
            popupRow(container, title: "\(localizedString("5 minutes")):", value: "").1
        self.average15Field =
            popupRow(container, title: "\(localizedString("15 minutes")):", value: "").1

        view.addSubview(separator)
        view.addSubview(container)

        self.averageView = view
        return view
    }

    private func initFrequency() -> NSView {
        let view: NSView = NSView(
            frame: NSRect(x: 0, y: 0, width: self.frame.width, height: self.frequencyHeight))
        view.heightAnchor.constraint(equalToConstant: view.bounds.height).isActive = true
        let separator = separatorView(
            localizedString("Frequency"),
            origin: NSPoint(x: 0, y: self.frequencyHeight - Constants.Popup.separatorHeight),
            width: self.frame.width)
        let container: NSStackView = NSStackView(
            frame: NSRect(x: 0, y: 0, width: view.frame.width, height: separator.frame.origin.y))
        container.orientation = .vertical
        container.spacing = 0

        self.coresFreqField =
            popupRow(container, title: "\(localizedString("All cores")):", value: "").1

        if self.isLocal, isARM {
            if SystemKit.shared.device.info.cpu?.eCores != nil {
                (self.eCoresFreqColorView, _, self.eCoresFreqField) = popupWithColorRow(
                    container, color: self.eCoresColor,
                    title: "\(localizedString("Efficiency cores")):", value: "")
            }
            if SystemKit.shared.device.info.cpu?.pCores != nil {
                (self.pCoresFreqColorView, _, self.pCoresFreqField) = popupWithColorRow(
                    container, color: self.pCoresColor,
                    title: "\(localizedString("Performance cores")):", value: "")
            }
        }

        view.addSubview(separator)
        view.addSubview(container)

        self.frequenciesView = view
        return view
    }

    // MARK: - Updates

    public func update(_ value: CPU_Load) {
        if (self.window?.isVisible ?? false) || !self.initialized {
            self.systemField?.stringValue = "\(Int(value.systemLoad.rounded(toPlaces: 2) * 100))%"
            self.userField?.stringValue = "\(Int(value.userLoad.rounded(toPlaces: 2) * 100))%"
            self.idleField?.stringValue = "\(Int(value.idleLoad.rounded(toPlaces: 2) * 100))%"

            let totalUsage = value.systemLoad + value.userLoad
            self.circle?.toolTip =
                "\(localizedString("CPU usage")): \(Int(totalUsage.rounded(toPlaces: 2) * 100))%"
            self.circle?.setValue(totalUsage)
            self.circle?.setSegments([
                circle_segment(value: value.systemLoad, color: self.systemColor),
                circle_segment(value: value.userLoad, color: self.userColor),
            ])
            self.circle?.setNonActiveSegmentColor(self.idleColor)

            if let field = self.eCoresField, let usage = value.usageECores {
                field.stringValue = "\(Int(usage * 100))%"
            }
            if let field = self.pCoresField, let usage = value.usagePCores {
                field.stringValue = "\(Int(usage * 100))%"
            }

            var usagePerCore: [ColorValue] = []
            if let cores = SystemKit.shared.device.info.cpu?.cores,
                cores.count == value.usagePerCore.count
            {
                for i in 0..<value.usagePerCore.count {
                    usagePerCore.append(
                        ColorValue(
                            value.usagePerCore[i],
                            color: cores[i].type == .efficiency
                                ? self.eCoresColor : self.pCoresColor))
                }
            } else {
                for i in 0..<value.usagePerCore.count {
                    usagePerCore.append(
                        ColorValue(value.usagePerCore[i], color: NSColor.systemBlue))
                }
            }
            self.barChart?.setValues(usagePerCore)

            self.initialized = true
        }
        self.lineChart?.addValue(value.systemLoad + value.userLoad)
    }

    public func updateRemote(_ stats: RemoteStats) {
        let cpuUsage = stats.cpu ?? 0
        self.lineChart?.addValue(cpuUsage)

        if (self.window?.isVisible ?? false) || !self.initialized {
            self.circle?.setValue(cpuUsage)
            self.circle?.toolTip =
                "\(localizedString("CPU usage")): \(Int(cpuUsage.rounded(toPlaces: 2) * 100))%"
            self.circle?.setNonActiveSegmentColor(self.idleColor)

            if let details = stats.cpuDetails {
                self.circle?.setSegments([
                    circle_segment(value: details.system, color: self.systemColor),
                    circle_segment(value: details.user, color: self.userColor),
                ])

                self.systemField?.stringValue = "\(Int(details.system.rounded(toPlaces: 2) * 100))%"
                self.userField?.stringValue = "\(Int(details.user.rounded(toPlaces: 2) * 100))%"
                self.idleField?.stringValue = "\(Int(details.idle.rounded(toPlaces: 2) * 100))%"
            } else {
                // Fallback if detail missing
                self.circle?.setSegments([circle_segment(value: cpuUsage, color: self.chartColor)])
            }

            if let load = stats.loadAvg {
                self.average1Field?.stringValue = String(format: "%.2f", load.load1)
                self.average5Field?.stringValue = String(format: "%.2f", load.load5)
                self.average15Field?.stringValue = String(format: "%.2f", load.load15)
            }

            if let freq = stats.frequency {
                self.coresFreqField?.stringValue = "\(Int(freq)) MHz"
                if let view = self.frequencyCircle {
                    view.isHidden = false
                    // Determine max freq? For now dynamic or fixed max?
                    // Let's update maxFreq dynamic
                    if freq > self.maxFreq { self.maxFreq = freq }
                    let p = (100 * freq) / (self.maxFreq == 0 ? 1 : self.maxFreq)
                    view.setValue(p)
                    view.setText("\((freq / 1000).rounded(toPlaces: 2))")
                }
            }

            if let temp = stats.temperature {
                if let view = self.temperatureCircle, (view as NSView).isHidden {
                    view.isHidden = false
                }
                self.temperatureCircle?.toolTip =
                    "\(localizedString("CPU temperature")): \(temperature(temp))"
                self.temperatureCircle?.setValue(temp)
                self.temperatureCircle?.setText(temperature(temp))
            }

            if let uptime = stats.uptime {
                self.uptimeField?.stringValue = self.uptimeString(from: uptime)
            }

            self.initialized = true
        }
    }

    private static let uptimeFormatter: DateComponentsFormatter = {
        let form = DateComponentsFormatter()
        form.maximumUnitCount = 2
        form.unitsStyle = .full
        form.allowedUnits = [.day, .hour, .minute]
        return form
    }()

    private func uptimeString(from seconds: TimeInterval) -> String {
        return Self.uptimeFormatter.string(from: seconds) ?? localizedString("Unknown")
    }

    public func temperatureCallback(_ value: Double?) {
        guard let value else { return }
        DispatchQueue.main.async(execute: {
            if self.window?.isVisible ?? false {
                if let view = self.temperatureCircle, (view as NSView).isHidden {
                    view.isHidden = false
                }
                self.temperatureCircle?.toolTip =
                    "\(localizedString("CPU temperature")): \(temperature(value))"
                self.temperatureCircle?.setValue(value)
                self.temperatureCircle?.setText(temperature(value))
            }
        })
    }

    public func frequencyCallback(_ value: CPU_Frequency?) {
        guard let value else { return }
        DispatchQueue.main.async(execute: {
            if self.window?.isVisible ?? false {
                if value.value > self.maxFreq { self.maxFreq = value.value }
                self.coresFreqField?.stringValue = "\(Int(value.value)) MHz"
                if let circle = self.frequencyCircle {
                    circle.isHidden = false
                    circle.setValue((100 * value.value) / self.maxFreq)
                    circle.setText("\((value.value/1000).rounded(toPlaces: 2))")
                }
                self.eCoresFreqField?.stringValue = "\(Int(value.eCore)) MHz"
                self.pCoresFreqField?.stringValue = "\(Int(value.pCore)) MHz"
            }
        })
    }

    public func limitCallback(_ value: CPU_Limit?) {
        guard let value else { return }
        DispatchQueue.main.async(execute: {
            if self.window?.isVisible ?? false {
                self.shedulerLimitField?.stringValue = "\(value.scheduler)%"
                self.speedLimitField?.stringValue = "\(value.speed)%"
            }
        })
    }

    public func averageCallback(_ value: CPU_AverageLoad?) {
        guard let value else { return }
        DispatchQueue.main.async(execute: {
            if self.window?.isVisible ?? false {
                self.average1Field?.stringValue = "\(value.load1)"
                self.average5Field?.stringValue = "\(value.load5)"
                self.average15Field?.stringValue = "\(value.load15)"
            }
        })
    }

    // MARK: - Actions

    @objc private func toggleDetails() {
        self.detailsState = !self.detailsState
        if self.isLocal {
            Store.shared.set(key: "\(self.title)_details", value: self.detailsState)
        }
        self.updateCollapseState()
        self.updateHeight()
    }

    private func updateCollapseState() {
        self.detailsView?.isHidden = !self.detailsState
        self.averageView?.isHidden = !self.detailsState
        self.frequenciesView?.isHidden = !self.detailsState
    }

    // MARK: - Settings

    public func settings() -> NSView? {
        let view = SettingsContainerView()
        // Pass through other settings...
        // For brevity assuming standard color/chart settings logic is handled here or by Popup.
        // Actually Popup.settings() delegates here.
        // We need to implement the settings UI and actions here.
        // Since I'm rewriting, I'll copy the settings implementation from original Popup, adjusted for 'self'.

        view.addArrangedSubview(
            PreferencesSection([
                PreferencesRow(
                    localizedString("System color"),
                    component: selectView(
                        action: #selector(self.toggleSystemColor),
                        items: SColor.allColors,
                        selected: self.systemColorState.key
                    )),
                PreferencesRow(
                    localizedString("User color"),
                    component: selectView(
                        action: #selector(self.toggleUserColor),
                        items: SColor.allColors,
                        selected: self.userColorState.key
                    )),
                PreferencesRow(
                    localizedString("Idle color"),
                    component: selectView(
                        action: #selector(self.toggleIdleColor),
                        items: SColor.allColors,
                        selected: self.idleColorState.key
                    )),
            ]))

        view.addArrangedSubview(
            PreferencesSection([
                PreferencesRow(
                    localizedString("Efficiency cores color"),
                    component: selectView(
                        action: #selector(self.toggleECoresColor),
                        items: SColor.allColors,
                        selected: self.eCoresColorState.key
                    )),
                PreferencesRow(
                    localizedString("Performance cores color"),
                    component: selectView(
                        action: #selector(self.togglePCoresColor),
                        items: SColor.allColors,
                        selected: self.pCoresColorState.key
                    )),
            ]))

        self.sliderView = sliderView(
            action: #selector(self.toggleLineChartFixedScale),
            value: Int(self.lineChartFixedScale * 100),
            initialValue: "\(Int(self.lineChartFixedScale * 100)) %"
        )
        self.chartPrefSection = PreferencesSection([
            PreferencesRow(
                localizedString("Chart color"),
                component: selectView(
                    action: #selector(self.toggleChartColor),
                    items: SColor.allColors,
                    selected: self.chartColorState.key
                )),
            PreferencesRow(
                localizedString("Chart history"),
                component: selectView(
                    action: #selector(self.toggleLineChartHistory),
                    items: LineChartHistory,
                    selected: "\(self.lineChartHistory)"
                )),
            PreferencesRow(
                localizedString("Main chart scaling"),
                component: selectView(
                    action: #selector(self.toggleLineChartScale),
                    items: Scale.allCases,
                    selected: self.lineChartScale.key
                )),
            PreferencesRow(localizedString("Scale value"), component: self.sliderView!),
        ])
        view.addArrangedSubview(self.chartPrefSection!)
        self.chartPrefSection?.setRowVisibility(3, newState: self.lineChartScale == .fixed)

        return view
    }

    @objc private func toggleSystemColor(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String,
            let newValue = SColor.allColors.first(where: { $0.key == key })
        else { return }
        self.systemColorState = newValue
        Store.shared.set(key: "\(self.title)_systemColor", value: key)
        self.systemColorView?.layer?.backgroundColor = (newValue.additional as? NSColor)?.cgColor
    }
    @objc private func toggleUserColor(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String,
            let newValue = SColor.allColors.first(where: { $0.key == key })
        else { return }
        self.userColorState = newValue
        Store.shared.set(key: "\(self.title)_userColor", value: key)
        self.userColorView?.layer?.backgroundColor = (newValue.additional as? NSColor)?.cgColor
    }
    @objc private func toggleIdleColor(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String,
            let newValue = SColor.allColors.first(where: { $0.key == key })
        else { return }
        self.idleColorState = newValue
        Store.shared.set(key: "\(self.title)_idleColor", value: key)
        self.idleColorView?.layer?.backgroundColor = (newValue.additional as? NSColor)?.cgColor
    }
    @objc private func toggleChartColor(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String,
            let newValue = SColor.allColors.first(where: { $0.key == key })
        else { return }
        self.chartColorState = newValue
        Store.shared.set(key: "\(self.title)_chartColor", value: key)
        self.lineChart?.color = (newValue.additional as? NSColor) ?? NSColor.systemBlue
    }
    @objc private func toggleECoresColor(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String,
            let newValue = SColor.allColors.first(where: { $0.key == key })
        else { return }
        self.eCoresColorState = newValue
        Store.shared.set(key: "\(self.title)_eCoresColor", value: key)
        if let color = (newValue.additional as? NSColor) {
            self.eCoresColorView?.layer?.backgroundColor = color.cgColor
            self.eCoresFreqColorView?.layer?.backgroundColor = color.cgColor
        }
    }
    @objc private func togglePCoresColor(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String,
            let newValue = SColor.allColors.first(where: { $0.key == key })
        else { return }
        self.pCoresColorState = newValue
        Store.shared.set(key: "\(self.title)_pCoresColor", value: key)
        if let color = (newValue.additional as? NSColor) {
            self.pCoresColorView?.layer?.backgroundColor = color.cgColor
            self.pCoresFreqColorView?.layer?.backgroundColor = color.cgColor
        }
    }
    @objc private func toggleLineChartHistory(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String, let value = Int(key) else { return }
        self.lineChartHistory = value
        Store.shared.set(key: "\(self.title)_lineChartHistory", value: value)
        self.lineChart?.reinit(self.lineChartHistory)
    }
    @objc private func toggleLineChartScale(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String,
            let value = Scale.allCases.first(where: { $0.key == key })
        else { return }
        self.chartPrefSection?.setRowVisibility(3, newState: value == .fixed)
        self.lineChartScale = value
        self.lineChart?.setScale(self.lineChartScale, fixedScale: self.lineChartFixedScale)
        Store.shared.set(key: "\(self.title)_lineChartScale", value: key)
    }
    @objc private func toggleLineChartFixedScale(_ sender: NSSlider) {
        let value = Int(sender.doubleValue)
        if let field = self.sliderView?.subviews.first(where: { $0 is NSTextField }),
            let view = field as? NSTextField
        {
            view.stringValue = "\(value) %"
        }
        self.lineChartFixedScale = sender.doubleValue / 100
        self.lineChart?.setScale(self.lineChartScale, fixedScale: self.lineChartFixedScale)
        Store.shared.set(key: "\(self.title)_lineChartFixedScale", value: value)
    }
}
