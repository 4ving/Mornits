//
//  popup.swift
//  Net
//
//  Created by Serhiy Mytrovtsiy on 24/05/2020.
//  Using Swift 5.0.
//  Running on macOS 10.15.
//
//  Copyright © 2020 Serhiy Mytrovtsiy. All rights reserved.
//

import Cocoa
import Kit

internal class NetworkInterfaceView: NSStackView {
    public var id: String

    // UI Elements
    private var chart: NetworkChartView?
    private var detailsView: NSStackView?

    private var uploadContainerView: NSView?
    private var uploadView: NSView?
    private var uploadValueField: NSTextField?
    private var uploadUnitField: NSTextField?
    private var uploadStateView: ColorView?

    private var downloadContainerView: NSView?
    private var downloadView: NSView?
    private var downloadValueField: NSTextField?
    private var downloadUnitField: NSTextField?
    private var downloadStateView: ColorView?

    private var totalUploadField: ValueField?
    private var totalDownloadField: ValueField?
    private var totalUploadLabel: LabelField?
    private var totalDownloadLabel: LabelField?

    private var latencyField: ValueField?
    private var detailsPublicIPField: ValueField?

    private var uploadColorView: NSView?
    private var downloadColorView: NSView?

    private var uploadColor: NSColor
    private var downloadColor: NSColor
    private var chartHistory: Int
    private var chartScale: Scale
    private var chartFixedScale: Int
    private var chartFixedScaleSize: SizeUnit
    private var reverseOrder: Bool
    private var base: DataSizeBase
    private var detailsState: Bool = false  // Collapse state

    // State
    private var uploadValue: Int64 = 0
    private var downloadValue: Int64 = 0
    private var isLocal: Bool = false

    init(
        id: String,
        width: CGFloat,
        uploadColor: NSColor,
        downloadColor: NSColor,
        chartHistory: Int,
        chartScale: Scale,
        chartFixedScale: Int,
        chartFixedScaleSize: SizeUnit,
        reverseOrder: Bool,
        base: DataSizeBase
    ) {
        self.id = id
        self.uploadColor = uploadColor
        self.downloadColor = downloadColor
        self.chartHistory = chartHistory
        self.chartScale = chartScale
        self.chartFixedScale = chartFixedScale
        self.chartFixedScaleSize = chartFixedScaleSize
        self.reverseOrder = reverseOrder
        self.base = base

        super.init(frame: NSRect(x: 0, y: 0, width: width, height: 0))

        self.orientation = .vertical
        self.spacing = 0

        self.detailsState = Store.shared.bool(
            key: "Network_interface_details_\(self.id)", defaultValue: true)

        self.initChart()
        self.initDetails()

        self.updateCollapseState()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func initChart() {
        let view = NSView(
            frame: NSRect(
                x: 0, y: 0, width: self.frame.width, height: 90 + Constants.Popup.separatorHeight))
        let c = view.heightAnchor.constraint(equalToConstant: view.bounds.height)
        c.priority = NSLayoutConstraint.Priority(999)
        c.isActive = true

        let row = NSView(
            frame: NSRect(
                x: 0, y: 90, width: self.frame.width, height: Constants.Popup.separatorHeight))

        let button = NSButtonWithPadding()
        button.frame = CGRect(x: view.frame.width - 18, y: 6, width: 18, height: 18)
        button.bezelStyle = .regularSquare
        button.isBordered = false
        button.imageScaling = NSImageScaling.scaleAxesIndependently
        button.contentTintColor = .lightGray
        button.action = #selector(self.toggleDetails)
        button.target = self
        button.toolTip = localizedString("Details")
        // Use a different icon or rotate it for collapse state
        button.image = Bundle(for: Module.self).image(forResource: "tune")!

        // Title logic: will be updated with interface name later or set initially
        row.addSubview(separatorView(localizedString("Usage history"), width: self.frame.width))
        row.addSubview(button)

        let container = NSView(frame: NSRect(x: 0, y: 0, width: self.frame.width, height: 90))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.lightGray.withAlphaComponent(0.1).cgColor
        container.layer?.cornerRadius = 3

        let chart = NetworkChartView(
            frame: NSRect(
                x: 0, y: 1, width: container.frame.width, height: container.frame.height - 2),
            num: self.chartHistory, reversedOrder: self.reverseOrder,
            outColor: self.uploadColor, inColor: self.downloadColor,
            scale: self.chartScale,
            fixedScale: Double(self.chartFixedScaleSize.toBytes(self.chartFixedScale))
        )
        chart.base = self.base
        container.addSubview(chart)
        self.chart = chart

        view.addSubview(row)
        view.addSubview(container)

        self.addArrangedSubview(view)
    }

    private func initDetails() {
        let view = NSStackView(frame: NSRect(x: 0, y: 0, width: self.frame.width, height: 0))
        view.orientation = .vertical
        view.spacing = 0

        // Separator logic? Maybe unnecessary if we just stack info below chart.
        // But we want "Total Upload/Download" like before.

        let totalUpload = popupWithColorRow(
            view, color: self.uploadColor, title: "\(localizedString("Total upload")):", value: "0")
        let totalDownload = popupWithColorRow(
            view, color: self.downloadColor, title: "\(localizedString("Total download")):",
            value: "0")

        self.uploadColorView = totalUpload.0
        self.totalUploadLabel = totalUpload.1
        self.totalUploadField = totalUpload.2

        self.downloadColorView = totalDownload.0
        self.totalDownloadLabel = totalDownload.1
        self.totalDownloadField = totalDownload.2

        // Latency is usually global or primary. If remote, we might have ping?
        // Currently `Network_Usage` doesn't have latency for remote.
        // So Latency field implies ConnectivityReader support.
        // We will add it but hide it if not available.
        self.latencyField = popupRow(view, title: "\(localizedString("Latency")):", value: "0 ms").1
        self.detailsPublicIPField =
            popupRow(
                view, title: "\(localizedString("Public IP")):", value: localizedString("Unknown")
            )
            .1

        self.detailsView = view
        self.addArrangedSubview(view)
    }

    @objc private func toggleDetails() {
        self.detailsState = !self.detailsState
        Store.shared.set(key: "Network_interface_details_\(self.id)", value: self.detailsState)
        self.updateCollapseState()
        // Notify parent to recalculate height?
        // NSStackView usually handles resizing, but parent Popup might need `recalculateHeight()` called.
        // We can post a notification or use a callback.
        NotificationCenter.default.post(name: .init("Network_Interface_Resize"), object: nil)
    }

    private func updateCollapseState() {
        self.detailsView?.isHidden = !self.detailsState
    }

    public func update(usage: Network_Usage) {
        // Update data
        self.chart?.addValue(
            upload: Double(usage.bandwidth.upload), download: Double(usage.bandwidth.download))

        self.totalUploadField?.stringValue = Units(bytes: usage.total.upload).getReadableMemory()
        self.totalDownloadField?.stringValue = Units(bytes: usage.total.download)
            .getReadableMemory()

        // Public IP Update
        // Public IP Update
        self.updateDetailsPublicIP(usage)

        // Interface Name Update in Header
        if let subviews = self.subviews.first?.subviews,
            let row = subviews.first(where: { $0.frame.height == Constants.Popup.separatorHeight })
        {
            // Find separator view and update label
            // This is hacky. `separatorView` creates a NSTextField.
            // But we can just replace the title view if needed or store it.
            // Ideally `separatorView` returns the field.
            // For now, let's just accept static title "Usage history" or try to find it.

            // Wait, the user wants "server name ... to the left of usage history".
            // Since `separatorView` is a simple helper, maybe I should traverse subviews.
            row.subviews.first(where: { $0 is NSTextField })?.removeFromSuperview()
            // Re-add? No, separatorView returns a NSView container usually?
            // Helper `separatorView` returns `NSView` with a line and a label.

            // Let's assume for now we keep "Usage History" but we want to prepend Name.
            // Actually, `Network_Usage` has `interface.displayName`.
            let name = usage.interface?.displayName ?? localizedString("Unknown")
            let title = "\(name)"

            // Update the label if I can find it.
            // Accessing internal structure of separatorView return is tricky without seeing helper.
            // Assuming I can replace the whole separator?
            if let sep = row.subviews.first(where: { $0.frame.width == self.frame.width }) {
                sep.removeFromSuperview()
                row.addSubview(
                    separatorView(title, width: self.frame.width), positioned: .below,
                    relativeTo: nil)
            }
        }

    }

    public func updateLatency(_ value: Double) {
        self.latencyField?.stringValue = "\(Int(value)) ms"
    }

    public func updateDetailsPublicIP(_ usage: Network_Usage) {
        if let ip = usage.raddr.v4, !ip.isEmpty {
            var value = ip
            if let cc = usage.raddr.countryCode, !cc.isEmpty {
                value += " (\(cc))"
            }
            self.detailsPublicIPField?.stringValue = value
        } else {
            self.detailsPublicIPField?.stringValue = localizedString("Unknown")
        }
    }

    public func setColors(_ upload: NSColor, _ download: NSColor) {
        self.uploadColor = upload
        self.downloadColor = download
        self.chart?.setColors(in: download, out: upload)
        self.uploadStateView?.setColor(upload)
        self.downloadStateView?.setColor(download)
        self.uploadColorView?.layer?.backgroundColor = upload.cgColor
        self.downloadColorView?.layer?.backgroundColor = download.cgColor
    }

    public func setScale(_ scale: Scale, _ fixed: Int) {
        self.chartScale = scale
        self.chartFixedScale = fixed
        self.chart?.setScale(scale, Double(fixed))
    }

    public func setReverseOrder(_ reverse: Bool) {
        self.reverseOrder = reverse
        self.chart?.setReverseOrder(reverse)
    }

    public func setHistory(_ history: Int) {
        self.chartHistory = history
        self.chart?.reinit(history)
    }

    public func setBase(_ base: DataSizeBase) {
        self.base = base
        self.chart?.base = base
    }
}

// swiftlint:disable:next type_body_length
internal class Popup: PopupWrapper {
    private var stackView: NSStackView!
    private var interfaceViews: [String: NetworkInterfaceView] = [:]

    private var processesView: NSView? = nil
    private var processes: ProcessesView? = nil

    private var connectivityChart: GridChartView? = nil
    private var connectivityView: NSView? = nil
    private var latencyField: ValueField? = nil  // Global latency? Or rely on primary interface?

    // Global Settings
    private var reverseOrderState: Bool = false
    private var chartHistory: Int = 180
    private var chartScale: Scale = .none
    private var chartFixedScale: Int = 12
    private var chartFixedScaleSize: SizeUnit = .MB
    private var publicIPState: Bool = true
    private var interfaceDetailsState: Bool = false

    private var base: DataSizeBase {
        DataSizeBase(rawValue: Store.shared.string(key: "\(self.title)_base", defaultValue: "byte"))
            ?? .byte
    }
    private var numberOfProcesses: Int {
        Store.shared.int(key: "\(self.title)_processes", defaultValue: 8)
    }

    private var downloadColorState: SColor = .secondBlue
    private var downloadColor: NSColor {
        var value = NSColor.systemBlue
        if let color = self.downloadColorState.additional as? NSColor { value = color }
        return value
    }
    private var uploadColorState: SColor = .secondRed
    private var uploadColor: NSColor {
        var value = NSColor.systemRed
        if let color = self.uploadColorState.additional as? NSColor { value = color }
        return value
    }

    public init(_ module: ModuleType) {
        super.init(module, frame: NSRect(x: 0, y: 0, width: Constants.Popup.width, height: 0))

        self.orientation = .vertical
        self.spacing = 0

        self.downloadColorState = SColor.fromString(
            Store.shared.string(
                key: "\(self.title)_downloadColor", defaultValue: self.downloadColorState.key))
        self.uploadColorState = SColor.fromString(
            Store.shared.string(
                key: "\(self.title)_uploadColor", defaultValue: self.uploadColorState.key))
        self.reverseOrderState = Store.shared.bool(
            key: "\(self.title)_reverseOrder", defaultValue: self.reverseOrderState)
        self.chartHistory = Store.shared.int(
            key: "\(self.title)_chartHistory", defaultValue: self.chartHistory)
        self.chartScale = Scale.fromString(
            Store.shared.string(key: "\(self.title)_chartScale", defaultValue: self.chartScale.key))
        self.chartFixedScale = Store.shared.int(
            key: "\(self.title)_chartFixedScale", defaultValue: self.chartFixedScale)
        self.chartFixedScaleSize = SizeUnit.fromString(
            Store.shared.string(
                key: "\(self.title)_chartFixedScaleSize", defaultValue: self.chartFixedScaleSize.key
            ))
        self.publicIPState = Store.shared.bool(
            key: "\(self.title)_publicIP", defaultValue: self.publicIPState)

        self.stackView = NSStackView()
        self.stackView.orientation = .vertical
        self.stackView.spacing = 0
        self.addArrangedSubview(self.stackView)

        self.addArrangedSubview(self.initConnectivityChart())
        self.addArrangedSubview(self.initProcesses())

        DispatchQueue.main.async {
            self.recalculateHeight()
        }

        NotificationCenter.default.addObserver(
            self, selector: #selector(self.resizeCallback), name: .init("Network_Interface_Resize"),
            object: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    @objc private func resizeCallback() {
        self.recalculateHeight()
    }

    private func recalculateHeight() {
        let h = self.heightForView(self)
        if self.frame.size.height != h {
            self.setFrameSize(NSSize(width: self.frame.width, height: h))
            self.sizeCallback?(self.frame.size)
        }
    }

    private func heightForView(_ view: NSView) -> CGFloat {
        var h: CGFloat = view.fittingSize.height
        if h == 0 {
            if let stack = view as? NSStackView {
                for v in stack.arrangedSubviews {
                    if v.isHidden { continue }
                    h += heightForView(v)
                }
                h += stack.edgeInsets.top + stack.edgeInsets.bottom
                h +=
                    CGFloat(max(0, stack.arrangedSubviews.filter { !$0.isHidden }.count - 1))
                    * stack.spacing
            } else {
                h = view.bounds.height
            }
        }
        return h
    }

    public func usageCallback(_ list: [Network_Usage]) {
        var activeIDs: [String] = []

        DispatchQueue.main.async {
            if list.isEmpty {
                self.interfaceViews.values.forEach {
                    self.stackView.removeArrangedSubview($0)
                    $0.removeFromSuperview()
                }
                self.interfaceViews.removeAll()
                self.recalculateHeight()
                return
            }

            for usage in list {
                let id = usage.interface?.BSDName ?? "local"
                activeIDs.append(id)

                if let view = self.interfaceViews[id] {
                    view.update(usage: usage)
                    if let latency = usage.latency {
                        view.updateLatency(latency)
                    }
                } else {
                    let view = NetworkInterfaceView(
                        id: id,
                        width: self.frame.width,
                        uploadColor: self.uploadColor,
                        downloadColor: self.downloadColor,
                        chartHistory: self.chartHistory,
                        chartScale: self.chartScale,
                        chartFixedScale: self.chartFixedScale,
                        chartFixedScaleSize: self.chartFixedScaleSize,
                        reverseOrder: self.reverseOrderState,
                        base: self.base
                    )
                    self.stackView.addArrangedSubview(view)
                    self.interfaceViews[id] = view
                    view.update(usage: usage)
                    if let latency = usage.latency {
                        view.updateLatency(latency)
                    }
                }
            }

            // Remove old views
            let views = self.stackView.arrangedSubviews.filter { $0 is NetworkInterfaceView }.map {
                $0 as! NetworkInterfaceView
            }
            views.forEach { view in
                if !activeIDs.contains(view.id) {
                    self.stackView.removeArrangedSubview(view)
                    view.removeFromSuperview()
                    self.interfaceViews.removeValue(forKey: view.id)
                }
            }

            DispatchQueue.main.async {
                self.recalculateHeight()
            }
        }
    }

    public func processCallback(_ list: [Network_Process]) {
        DispatchQueue.main.async(execute: {
            if !(self.window?.isVisible ?? false) && self.processes != nil {
                return
            }
            let list = list.map { $0 }
            if list.count != self.processes?.count { self.processes?.clear() }

            for i in 0..<list.count {
                let process = list[i]
                let upload = Units(bytes: Int64(process.upload)).getReadableSpeed(base: self.base)
                let download = Units(bytes: Int64(process.download)).getReadableSpeed(
                    base: self.base)
                self.processes?.set(i, process, [download, upload])
            }

            // Re-add processes view if needed
            if self.processes == nil {
                self.processesView?.removeFromSuperview()
                self.addArrangedSubview(self.initProcesses())
            }
        })
    }

    public func connectivityCallback(_ value: Network_Connectivity) {
        DispatchQueue.main.async {
            if let chart = self.connectivityChart {
                chart.addValue(value.status)
            }

            self.interfaceViews.forEach { (id, view) in
                // Only update latency for local interfaces (no colon in ID)
                if !id.contains(":") {
                    view.updateLatency(value.latency)
                }
            }
        }
    }

    private func initConnectivityChart() -> NSView {
        let view: NSView = NSView(
            frame: NSRect(
                x: 0, y: 0, width: self.frame.width, height: 30 + Constants.Popup.separatorHeight))
        let c = view.heightAnchor.constraint(equalToConstant: view.bounds.height)
        c.priority = NSLayoutConstraint.Priority(999)
        c.isActive = true
        let separator = separatorView(
            "\(localizedString("Local")):\(localizedString("Connectivity history"))",
            origin: NSPoint(x: 0, y: 30),
            width: self.frame.width)
        let container: NSView = NSView(
            frame: NSRect(x: 0, y: 0, width: self.frame.width, height: separator.frame.origin.y))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.lightGray.withAlphaComponent(0.1).cgColor
        container.layer?.cornerRadius = 3

        let chart = GridChartView(
            frame: NSRect(
                x: 0, y: 1, width: container.frame.width, height: container.frame.height - 2),
            grid: (30, 3))
        container.addSubview(chart)
        self.connectivityChart = chart

        view.addSubview(separator)
        view.addSubview(container)

        self.connectivityView = view
        return view
    }

    public func resetConnectivityView() {}

    public func numberOfProcessesUpdated() {
        DispatchQueue.main.async {
            self.processesView?.removeFromSuperview()
            self.processesView = nil
            self.processes = nil
            self.addArrangedSubview(self.initProcesses())
            self.recalculateHeight()
        }
    }

    private func initProcesses() -> NSView {
        if self.numberOfProcesses == 0 {
            let v = NSView()
            self.processesView = v
            return v
        }

        let height = (22 * CGFloat(self.numberOfProcesses)) + Constants.Popup.separatorHeight + 22
        let view: NSView = NSView(
            frame: NSRect(x: 0, y: 0, width: self.frame.width, height: height))
        let c = view.heightAnchor.constraint(equalToConstant: height)
        c.priority = NSLayoutConstraint.Priority(999)
        c.isActive = true
        let separator = separatorView(
            "\(localizedString("Local")):\(localizedString("Top processes"))",
            origin: NSPoint(x: 0, y: height - Constants.Popup.separatorHeight),
            width: self.frame.width)
        let container: ProcessesView = ProcessesView(
            frame: NSRect(x: 0, y: 0, width: self.frame.width, height: separator.frame.origin.y),
            values: [
                (localizedString("Downloading"), self.downloadColor),
                (localizedString("Uploading"), self.uploadColor),
            ],
            n: self.numberOfProcesses
        )
        self.processes = container
        view.addSubview(separator)
        view.addSubview(container)
        self.processesView = view
        return view
    }

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
                    localizedString("Color of download"),
                    component: selectView(
                        action: #selector(self.toggleDownloadColor),
                        items: SColor.allColors,
                        selected: self.downloadColorState.key
                    )),
                PreferencesRow(
                    localizedString("Color of upload"),
                    component: selectView(
                        action: #selector(self.toggleUploadColor),
                        items: SColor.allColors,
                        selected: self.uploadColorState.key
                    )),
            ]))

        view.addArrangedSubview(
            PreferencesSection([
                PreferencesRow(
                    localizedString("Reverse order"),
                    component: switchView(
                        action: #selector(self.toggleReverseOrder),
                        state: self.reverseOrderState
                    ))
            ]))

        let chartPrefSection = PreferencesSection([
            PreferencesRow(
                localizedString("Chart history"),
                component: selectView(
                    action: #selector(self.togglechartHistory),
                    items: LineChartHistory,
                    selected: "\(self.chartHistory)"
                )),
            PreferencesRow(
                localizedString("Main chart scaling"),
                component: selectView(
                    action: #selector(self.toggleChartScale),
                    items: Scale.allCases,
                    selected: self.chartScale.key
                )),
            PreferencesRow(
                localizedString("Scale value"),
                component: StepperInput(
                    self.chartFixedScale, range: NSRange(location: 1, length: 1023),
                    unit: self.chartFixedScaleSize.key, units: SizeUnit.allCases,
                    callback: self.toggleFixedScale, unitCallback: self.toggleFixedScaleSize
                )),
        ])
        view.addArrangedSubview(chartPrefSection)
        chartPrefSection.setRowVisibility(2, newState: self.chartScale == .fixed)

        view.addArrangedSubview(
            PreferencesSection([
                PreferencesRow(
                    localizedString("Public IP"),
                    component: switchView(
                        action: #selector(self.togglePublicIP),
                        state: self.publicIPState
                    ))
            ]))

        return view
    }

    @objc private func toggleUploadColor(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String,
            let newValue = SColor.allColors.first(where: { $0.key == key })
        else { return }
        self.uploadColorState = newValue
        Store.shared.set(key: "\(self.title)_uploadColor", value: key)
        if let color = newValue.additional as? NSColor {
            self.interfaceViews.values.forEach { $0.setColors(color, self.downloadColor) }
            self.processes?.setColor(1, color)
        }
    }
    @objc private func toggleDownloadColor(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String,
            let newValue = SColor.allColors.first(where: { $0.key == key })
        else { return }
        self.downloadColorState = newValue
        Store.shared.set(key: "\(self.title)_downloadColor", value: key)
        if let color = newValue.additional as? NSColor {
            self.interfaceViews.values.forEach { $0.setColors(self.uploadColor, color) }
            self.processes?.setColor(0, color)
        }
    }
    @objc private func toggleReverseOrder(_ sender: NSControl) {
        self.reverseOrderState = controlState(sender)
        Store.shared.set(key: "\(self.title)_reverseOrder", value: self.reverseOrderState)
        self.interfaceViews.values.forEach { $0.setReverseOrder(self.reverseOrderState) }
    }
    @objc private func togglechartHistory(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String, let value = Int(key) else { return }
        self.chartHistory = value
        Store.shared.set(key: "\(self.title)_chartHistory", value: value)
        self.interfaceViews.values.forEach { $0.setHistory(value) }
    }
    @objc private func toggleChartScale(_ sender: NSMenuItem) {
        guard let key = sender.representedObject as? String,
            let value = Scale.allCases.first(where: { $0.key == key })
        else { return }
        self.chartScale = value
        Store.shared.set(key: "\(self.title)_chartScale", value: key)
        self.interfaceViews.values.forEach { $0.setScale(value, self.chartFixedScale) }
    }
    @objc private func togglePublicIP(_ sender: NSControl) {
        self.publicIPState = controlState(sender)
        Store.shared.set(key: "\(self.title)_publicIP", value: self.publicIPState)
        // Need to notify interfaces?
        // Interfaces read from store? No, they don't know global "publicIPState".
        // It's a bit mixed. `initAddress` handles public IP.
        // We probably need a method `togglePublicIP` on view.
    }
    @objc private func toggleFixedScale(_ newValue: Int) {
        self.chartFixedScale = newValue
        Store.shared.set(key: "\(self.title)_chartFixedScale", value: newValue)
        self.interfaceViews.values.forEach { $0.setScale(self.chartScale, newValue) }
    }
    private func toggleFixedScaleSize(_ newValue: KeyValue_p) {
        guard let newUnit = newValue as? SizeUnit else { return }
        self.chartFixedScaleSize = newUnit
        Store.shared.set(
            key: "\(self.title)_chartFixedScaleSize", value: self.chartFixedScaleSize.key)
        self.interfaceViews.values.forEach { $0.setScale(self.chartScale, self.chartFixedScale) }
    }
}

// Helpers from original file

private func popupWithColorRow(_ view: NSView, color: NSColor, title: String, value: String) -> (
    NSView, LabelField, ValueField
) {
    let row = NSView(frame: NSRect(x: 0, y: 0, width: view.frame.width, height: 22))

    let colorBlock = NSView(frame: NSRect(x: 2, y: 5, width: 12, height: 12))
    colorBlock.wantsLayer = true
    colorBlock.layer?.backgroundColor = color.cgColor
    colorBlock.layer?.cornerRadius = 2

    let label = LabelField(
        frame: NSRect(x: 18, y: 6, width: view.frame.width - 18, height: 12), title)
    let field = ValueField(
        frame: NSRect(x: 18, y: 6, width: view.frame.width - 18, height: 12), value)

    row.addSubview(colorBlock)
    row.addSubview(label)
    row.addSubview(field)

    if let stack = view as? NSStackView {
        row.heightAnchor.constraint(equalToConstant: row.bounds.height).isActive = true
        stack.addArrangedSubview(row)
    } else {
        view.addSubview(row)
    }

    return (colorBlock, label, field)
}
