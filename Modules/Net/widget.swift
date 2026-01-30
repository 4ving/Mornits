//
//  widget.swift
//  Net
//
//  Created by Serhiy Mytrovtsiy on 30/07/2024
//  Using Swift 5.0
//  Running on macOS 14.5
//
//  Copyright © 2024 Serhiy Mytrovtsiy. All rights reserved.
//

import Charts
import Kit
import SwiftUI
import WidgetKit

public struct Network_entry: TimelineEntry {
    public static let kind = "NetworkWidget"
    public static var snapshot: Network_entry = Network_entry(
        value: Network_Usage(
            bandwidth: Bandwidth(upload: 1_238_400, download: 18_732_000),
            raddr: Network_addr(v4: "192.168.0.1"),
            interface: Network_interface(displayName: "Mornits"),
            status: true
        ))

    public var date: Date {
        Calendar.current.date(byAdding: .second, value: 5, to: Date())!
    }
    public var value: Network_Usage? = nil
}

@available(macOS 11.0, *)
public struct Provider: TimelineProvider {
    public typealias Entry = Network_entry

    private let userDefaults: UserDefaults? = UserDefaults(
        suiteName: "group.com.4ving.Mornits.shared"
    )

    public func placeholder(in context: Context) -> Network_entry {
        Network_entry()
    }

    public func getSnapshot(in context: Context, completion: @escaping (Network_entry) -> Void) {
        completion(Network_entry.snapshot)
    }

    public func getTimeline(
        in context: Context, completion: @escaping (Timeline<Network_entry>) -> Void
    ) {
        var entry = Network_entry()
        var loaded = false
        
        if let containerURL = FileManager.default.containerURL(
            forSecurityApplicationGroupIdentifier: "N7LBX474DC.group.com.4ving.Mornits.shared")
        {
            let plistURL = containerURL.appendingPathComponent("Library/Preferences/group.com.4ving.Mornits.shared.plist")
            if let data = try? Data(contentsOf: plistURL) {
                if let dict = try? PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any] {
                    if let rawData = dict["Network@UsageReader"] as? Data {
                         if let load = try? JSONDecoder().decode(Network_Usage.self, from: rawData) {
                            entry.value = load
                            loaded = true
                         }
                    }
                }
            }
        }

        if !loaded {
            if let raw = userDefaults?.data(forKey: "Network@UsageReader"),
                let load = try? JSONDecoder().decode(Network_Usage.self, from: raw)
            {
                entry.value = load
            }
        }
        
        // Compute speed
        if let current = entry.value {
            // TODO: partial logic from original code, currently unused.
            // let lastSpeed = Store.shared.int64(key: "Network_lastSpeed", defaultValue: 0)
            // let currentSpeed = current.bandwidth.upload + current.bandwidth.download
            // let now = Date().timeIntervalSince1970
            // let lastTime = Store.shared.double(key: "Network_lastTime", defaultValue: now)
            
            // Simple logic to just use current speed, or more complex if needed.
            // For now, we just pass the value.
            entry.value = current
        }

        let entries: [Network_entry] = [entry]
        completion(Timeline(entries: entries, policy: .atEnd))
    }
}

@available(macOS 14.0, *)
public struct NetworkWidget: Widget {
    private var downloadColor: Color = Color(nsColor: NSColor.systemBlue)
    private var uploadColor: Color = Color(nsColor: NSColor.systemRed)

    public init() {}

    public var body: some WidgetConfiguration {
        StaticConfiguration(kind: Network_entry.kind, provider: Provider()) { entry in
            VStack(spacing: 10) {
                if let value = entry.value {
                    VStack {
                        HStack {
                            VStack {
                                VStack(spacing: 0) {
                                    Text(Units(bytes: value.bandwidth.upload).getReadableTuple().0)
                                        .font(.system(size: 24, weight: .regular))
                                    Text(Units(bytes: value.bandwidth.upload).getReadableTuple().1)
                                        .font(.system(size: 10, weight: .regular))
                                }
                                Text(localizedString("Upload")).font(.system(size: 12, weight: .regular))
                                    .foregroundColor(.gray)
                            }.frame(maxWidth: .infinity)
                            VStack {
                                VStack(spacing: 0) {
                                    Text(
                                        Units(bytes: value.bandwidth.download).getReadableTuple().0
                                    ).font(.system(size: 24, weight: .regular))
                                    Text(
                                        Units(bytes: value.bandwidth.download).getReadableTuple().1
                                    ).font(.system(size: 10, weight: .regular))
                                }
                                Text(localizedString("Download")).font(.system(size: 12, weight: .regular))
                                    .foregroundColor(.gray)
                            }.frame(maxWidth: .infinity)
                        }
                        .frame(maxHeight: .infinity)
                        VStack(spacing: 3) {
                            HStack {
                                Text(localizedString("Total upload")).font(.system(size: 10, weight: .regular))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(Units(bytes: value.total.upload).getReadableMemory(style: .file))
                                    .font(.system(size: 10))
                            }
                            HStack {
                                Text(localizedString("Total download")).font(.system(size: 10, weight: .regular))
                                    .foregroundColor(.secondary)
                                Spacer()
                                Text(Units(bytes: value.total.download).getReadableMemory(style: .file))
                                    .font(.system(size: 10))
                            }
                        }
                    }
                } else {
                    Text("No data")
                }
            }
            .containerBackground(for: .widget) {
                Color.clear
            }
        }
        .configurationDisplayName("Network widget")
        .description("Displays network stats")
        .supportedFamilies([.systemSmall])
    }
}
