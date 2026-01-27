//
//  portal.swift
//  Bluetooth
//
//  Created by Serhiy Mytrovtsiy on 26/01/2026
//  Using Swift 5.0
//  Running on macOS 10.15
//
//  Copyright © 2026 Serhiy Mytrovtsiy. All rights reserved.
//

import Cocoa
import Kit

public class Portal: PortalWrapper {
    private let emptyView: EmptyView = EmptyView(
        height: 30, isHidden: false, msg: localizedString("No Bluetooth devices are available"))
    private let container: NSStackView = NSStackView()

    public override func load() {
        self.container.orientation = .vertical
        self.container.spacing = Constants.Popup.spacing
        self.container.distribution = .fill
        self.container.alignment = .width

        self.addArrangedSubview(self.container)
        self.addArrangedSubview(self.emptyView)
    }

    internal func callback(_ list: [BLEDevice]) {
        DispatchQueue.main.async(execute: {
            // Manage empty state
            if list.isEmpty {
                self.container.isHidden = true
                self.emptyView.isHidden = false
                return
            }
            self.container.isHidden = false
            self.emptyView.isHidden = true

            // Rebuild list (simplest approach for now, optimize if flicker occurs)
            self.container.subviews.forEach { $0.removeFromSuperview() }

            list.filter { $0.isConnected || $0.isPaired }.forEach { (device: BLEDevice) in
                let view = NSStackView()
                view.orientation = .horizontal
                view.distribution = .fill
                view.spacing = 5

                let nameLabel = LabelField(device.name)
                nameLabel.font = NSFont.systemFont(ofSize: 11, weight: .regular)

                view.addArrangedSubview(nameLabel)
                view.addArrangedSubview(NSView())  // Spacer

                device.batteryLevel.forEach { (pair: KeyValue_t) in
                    let valLabel = ValueField("\(pair.value)%")
                    valLabel.font = NSFont.systemFont(ofSize: 12, weight: .regular)
                    if let key = pair.key.split(separator: "_").last {
                        valLabel.toolTip = String(key)
                    }
                    view.addArrangedSubview(valLabel)
                }

                self.container.addArrangedSubview(view)
                view.widthAnchor.constraint(equalTo: self.container.widthAnchor).isActive = true
            }
        })
    }
}
