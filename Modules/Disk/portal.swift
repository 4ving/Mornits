//
//  portal.swift
//  Disk
//
//  Created by Serhiy Mytrovtsiy on 20/02/2023
//  Using Swift 5.0
//  Running on macOS 13.2
//
//  Copyright © 2023 Serhiy Mytrovtsiy. All rights reserved.
//

import Cocoa
import Kit

public class Portal: PortalWrapper {
    private var circle: PieChartView? = nil

    private var nameField: NSTextField? = nil
    private var usedField: NSTextField? = nil
    private var freeField: NSTextField? = nil

    private var readField: NSTextField? = nil
    private var writeField: NSTextField? = nil

    private var readColorView: NSView? = nil
    private var writeColorView: NSView? = nil

    private var readRowView: NSView? = nil
    private var writeRowView: NSView? = nil
    private var detailsContainer: NSStackView? = nil

    private var reverseOrder: Bool = false

    private var valueColorState: SColor = .secondBlue
    private var valueColor: NSColor {
        self.readColor
    }

    private var readColor: NSColor {
        SColor.fromString(
            Store.shared.string(key: "\(self.name)_readColor", defaultValue: SColor.secondBlue.key)
        ).additional as! NSColor
    }
    private var writeColor: NSColor {
        SColor.fromString(
            Store.shared.string(key: "\(self.name)_writeColor", defaultValue: SColor.secondRed.key)
        ).additional as! NSColor
    }

    private var initialized: Bool = false

    public override func load() {
        self.loadColors()
        self.reverseOrder = Store.shared.bool(key: "\(self.name)_reverseOrder", defaultValue: false)

        let view = NSStackView()
        view.orientation = .horizontal
        view.distribution = .fillEqually
        view.spacing = Constants.Popup.spacing * 2
        view.edgeInsets = NSEdgeInsets(
            top: 0,
            left: Constants.Popup.spacing * 2,
            bottom: 0,
            right: Constants.Popup.spacing * 2
        )

        let chartsView = self.charts()
        let detailsView = self.details()

        view.addArrangedSubview(chartsView)
        view.addArrangedSubview(detailsView)

        self.addArrangedSubview(view)

        chartsView.heightAnchor.constraint(equalTo: view.heightAnchor).isActive = true
    }

    private func loadColors() {
        self.valueColorState = SColor.fromString(
            Store.shared.string(
                key: "\(self.name)_valueColor", defaultValue: self.valueColorState.key))
    }

    private func charts() -> NSView {
        let view = NSStackView()
        view.orientation = .vertical
        view.distribution = .fillEqually
        view.spacing = Constants.Popup.spacing * 2
        view.edgeInsets = NSEdgeInsets(
            top: Constants.Popup.spacing * 4,
            left: Constants.Popup.spacing * 4,
            bottom: Constants.Popup.spacing * 4,
            right: Constants.Popup.spacing * 4
        )

        let chart = PieChartView(frame: NSRect.zero, segments: [], drawValue: true)
        chart.toolTip = localizedString("Disk usage")
        view.addArrangedSubview(chart)
        self.circle = chart

        return view
    }

    private func details() -> NSView {
        let view = NSStackView()
        view.orientation = .vertical
        view.distribution = .fillEqually
        view.spacing = Constants.Popup.spacing * 2
        self.detailsContainer = view

        self.nameField = portalRow(view, title: "\(localizedString("Name")):").1
        self.usedField = portalRow(view, title: "\(localizedString("Used")):").1
        self.freeField = portalRow(view, title: "\(localizedString("Free")):").1

        let writeRow = self.speedRow(title: "\(localizedString("Write")):")
        self.writeField = writeRow.2
        self.writeColorView = writeRow.1
        self.writeRowView = writeRow.0

        let readRow = self.speedRow(title: "\(localizedString("Read")):")
        self.readField = readRow.2
        self.readColorView = readRow.1
        self.readRowView = readRow.0

        self.reorderRows()

        return view
    }

    private func reorderRows() {
        guard let view = self.detailsContainer,
            let readRow = self.readRowView,
            let writeRow = self.writeRowView
        else { return }

        if view.arrangedSubviews.contains(readRow) {
            view.removeArrangedSubview(readRow)
        }
        if view.arrangedSubviews.contains(writeRow) {
            view.removeArrangedSubview(writeRow)
        }

        if self.reverseOrder {
            // Read, Write
            view.addArrangedSubview(readRow)
            view.addArrangedSubview(writeRow)
        } else {
            // Write, Read
            view.addArrangedSubview(writeRow)
            view.addArrangedSubview(readRow)
        }
    }

    private func speedRow(title: String) -> (NSStackView, NSView?, NSTextField) {
        let row = NSStackView()
        row.orientation = .horizontal
        row.distribution = .fillProportionally
        row.spacing = 1

        let titleField = LabelField(title)
        titleField.font = NSFont.systemFont(ofSize: 11, weight: .regular)

        let valueField = ValueField("0")
        valueField.font = NSFont.systemFont(ofSize: 12, weight: .regular)

        row.addArrangedSubview(titleField)
        row.addArrangedSubview(NSView())
        row.addArrangedSubview(valueField)

        return (row, nil, valueField)
    }

    internal func utilizationCallback(_ value: drive) {
        DispatchQueue.main.async(execute: {
            if (self.window?.isVisible ?? false) || !self.initialized {
                self.nameField?.stringValue = value.mediaName
                self.usedField?.stringValue = DiskSize(value.size - value.free).getReadableMemory()
                self.freeField?.stringValue = DiskSize(value.free).getReadableMemory()

                self.circle?.toolTip =
                    "\(localizedString("Disk usage")): \(Int(value.percentage*100))%"
                self.circle?.setValue(value.percentage)
                self.circle?.setSegments([
                    circle_segment(value: value.percentage, color: self.valueColor)
                ])
                self.initialized = true
            }
        })
    }

    internal func activityCallback(_ value: drive) {
        DispatchQueue.main.async(execute: {
            if (self.window?.isVisible ?? false) || !self.initialized {
                self.readField?.stringValue = Units(bytes: value.activity.read).getReadableSpeed(
                    base: .byte)
                self.writeField?.stringValue = Units(bytes: value.activity.write).getReadableSpeed(
                    base: .byte)

                self.readColorView?.layer?.backgroundColor = self.readColor.cgColor
                self.writeColorView?.layer?.backgroundColor = self.writeColor.cgColor

                let currentReverseOrder = Store.shared.bool(
                    key: "\(self.name)_reverseOrder", defaultValue: false)
                if self.reverseOrder != currentReverseOrder {
                    self.reverseOrder = currentReverseOrder
                    self.reorderRows()
                }
            }
        })
    }
}
