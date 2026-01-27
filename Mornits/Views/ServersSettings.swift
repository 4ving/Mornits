//
//  ServersSettings.swift
//  Stats
//
//  Created by Antigravity on 18/01/2026.
//

import Cocoa
import Kit

class ServersSettings: NSStackView, Settings_v {
    private var list: [SSHServer] {
        RemoteServersManager.shared.servers
    }

    public var callback: (() -> Void) = {}

    private let scrollView = ScrollableStackView(orientation: .vertical)

    init() {
        super.init(frame: NSRect.zero)
        self.orientation = .vertical
        self.spacing = Constants.Settings.margin
        self.edgeInsets = NSEdgeInsets(
            top: 0,
            left: Constants.Settings.margin,
            bottom: Constants.Settings.margin,
            right: Constants.Settings.margin
        )

        self.scrollView.stackView.spacing = Constants.Settings.margin

        self.addArrangedSubview(self.scrollView)

        self.reload()

        NotificationCenter.default.addObserver(
            self, selector: #selector(self.reload), name: .init("reload_servers"), object: nil)
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    public func load(widgets: [widget_t]) {
        // No widget-specific settings needed for Servers currently
    }

    @objc private func reload() {
        self.scrollView.stackView.views.forEach { $0.removeFromSuperview() }

        // Local Section
        let localName = Host.current().localizedName ?? localizedString("Local")
        let localSection = PreferencesSection([
            PreferencesRow(
                localName,
                component: makeSwitch(
                    action: #selector(toggleLocal), state: RemoteServersManager.shared.localEnabled)
            )
        ])
        self.scrollView.stackView.addArrangedSubview(localSection)

        // Servers Section
        let serversSection = PreferencesSection(label: localizedString("Remote Computers"))
        for server in self.list {
            let controls = NSStackView()
            controls.orientation = .horizontal
            controls.spacing = 5

            let editBtn = NSButton(
                title: localizedString("Edit"), target: self, action: #selector(self.editServer))
            editBtn.identifier = NSUserInterfaceItemIdentifier(server.id.uuidString)
            editBtn.bezelStyle = .rounded
            editBtn.controlSize = .small
            editBtn.font = NSFont.systemFont(ofSize: 11)

            let deleteBtn = NSButton(
                title: localizedString("Delete"), target: self, action: #selector(self.deleteServer)
            )
            deleteBtn.identifier = NSUserInterfaceItemIdentifier(server.id.uuidString)
            deleteBtn.bezelStyle = .rounded
            deleteBtn.controlSize = .small
            deleteBtn.font = NSFont.systemFont(ofSize: 11)

            let toggle = makeSwitch(action: #selector(self.toggleServer), state: server.enabled)
            toggle.identifier = NSUserInterfaceItemIdentifier(server.id.uuidString)

            controls.addArrangedSubview(toggle)
            controls.addArrangedSubview(editBtn)
            controls.addArrangedSubview(deleteBtn)

            let row = PreferencesRow(server.name, component: controls)
            serversSection.add(row)
        }
        if !self.list.isEmpty {
            self.scrollView.stackView.addArrangedSubview(serversSection)
        }

        // Add Button Section
        let addSection = PreferencesSection([
            PreferencesRow(
                localizedString("Add remote computer"),
                component: button(title: "+", action: #selector(self.addServer)))
        ])
        self.scrollView.stackView.addArrangedSubview(addSection)
    }

    @objc private func toggleLocal(_ sender: NSControl) {
        RemoteServersManager.shared.localEnabled = controlState(sender)
    }

    @objc private func toggleServer(_ sender: NSControl) {
        guard let idString = sender.identifier?.rawValue, let id = UUID(uuidString: idString),
            var server = self.list.first(where: { $0.id == id })
        else { return }
        server.enabled = controlState(sender)
        RemoteServersManager.shared.updateServer(server)
    }

    @objc private func addServer() {
        let alert = NSAlert()
        alert.messageText = localizedString("Add computer")
        alert.addButton(withTitle: localizedString("Add"))
        alert.addButton(withTitle: localizedString("Cancel"))

        let view = NSStackView(frame: NSRect(x: 0, y: 0, width: 300, height: 210))
        view.orientation = .vertical
        view.spacing = 10

        let nameField = NSTextField(string: "")
        nameField.placeholderString = "Name (e.g. My VPS)"
        let hostField = NSTextField(string: "")
        hostField.placeholderString = "Host (IP or domain)"
        let userField = NSTextField(string: "root")
        userField.placeholderString = "User"
        let passField = NSSecureTextField(string: "")
        passField.placeholderString = "Password (optional)"
        let portField = NSTextField(string: "22")
        portField.placeholderString = "Port"
        let keyField = NSTextField(string: "~/.ssh/id_rsa")
        keyField.placeholderString = "Path to private key"

        view.addArrangedSubview(self.fieldRow("Name:", nameField))
        view.addArrangedSubview(self.fieldRow("Host:", hostField))
        view.addArrangedSubview(self.fieldRow("User:", userField))
        view.addArrangedSubview(self.fieldRow("Pass:", passField))
        view.addArrangedSubview(self.fieldRow("Port:", portField))
        view.addArrangedSubview(self.fieldRow("Key Path:", keyField))

        alert.accessoryView = view

        if alert.runModal() == .alertFirstButtonReturn {
            let server = SSHServer(
                name: nameField.stringValue,
                host: hostField.stringValue,
                port: Int(portField.stringValue) ?? 22,
                user: userField.stringValue,
                keyPath: keyField.stringValue,
                password: passField.stringValue.isEmpty ? nil : passField.stringValue,
                enabled: true
            )
            RemoteServersManager.shared.addServer(server)
            self.reload()
        }
    }

    @objc private func editServer(_ sender: NSButton) {
        guard let idString = sender.identifier?.rawValue, let id = UUID(uuidString: idString),
            let server = self.list.first(where: { $0.id == id })
        else { return }

        let alert = NSAlert()
        alert.messageText = "Edit SSH Server"
        alert.addButton(withTitle: localizedString("Save"))
        alert.addButton(withTitle: localizedString("Cancel"))

        let view = NSStackView(frame: NSRect(x: 0, y: 0, width: 300, height: 210))
        view.orientation = .vertical
        view.spacing = 10

        let nameField = NSTextField(string: server.name)
        let hostField = NSTextField(string: server.host)
        let userField = NSTextField(string: server.user)
        let passField = NSSecureTextField(string: server.password ?? "")
        let portField = NSTextField(string: "\(server.port)")
        let keyField = NSTextField(string: server.keyPath)

        view.addArrangedSubview(self.fieldRow("Name:", nameField))
        view.addArrangedSubview(self.fieldRow("Host:", hostField))
        view.addArrangedSubview(self.fieldRow("User:", userField))
        view.addArrangedSubview(self.fieldRow("Pass:", passField))
        view.addArrangedSubview(self.fieldRow("Port:", portField))
        view.addArrangedSubview(self.fieldRow("Key Path:", keyField))

        alert.accessoryView = view

        if alert.runModal() == .alertFirstButtonReturn {
            var newServer = server
            newServer.name = nameField.stringValue
            newServer.host = hostField.stringValue
            newServer.port = Int(portField.stringValue) ?? 22
            newServer.user = userField.stringValue
            newServer.keyPath = keyField.stringValue
            newServer.password = passField.stringValue.isEmpty ? nil : passField.stringValue

            RemoteServersManager.shared.updateServer(newServer)
            self.reload()
        }
    }

    @objc private func deleteServer(_ sender: NSButton) {
        guard let idString = sender.identifier?.rawValue, let id = UUID(uuidString: idString) else {
            return
        }

        let alert = NSAlert()
        alert.messageText = "Are you sure you want to delete this server?"
        alert.addButton(withTitle: localizedString("Yes"))
        alert.addButton(withTitle: localizedString("Cancel"))

        if alert.runModal() == .alertFirstButtonReturn {
            RemoteServersManager.shared.removeServer(id)
            self.reload()
        }
    }

    private func fieldRow(_ label: String, _ field: NSTextField) -> NSView {
        let view = NSStackView()
        view.orientation = .horizontal
        let labelField = NSTextField(labelWithString: label)
        labelField.widthAnchor.constraint(equalToConstant: 70).isActive = true
        view.addArrangedSubview(labelField)
        view.addArrangedSubview(field)
        return view
    }

    // Helpers to match Settings style
    private func button(title: String, action: Selector) -> NSButton {
        let btn = NSButton(title: title, target: self, action: action)
        btn.bezelStyle = .rounded
        return btn
    }

    private func makeSwitch(action: Selector, state: Bool) -> NSControl {
        if #available(OSX 10.15, *) {
            let switchButton = NSSwitch()
            switchButton.state = state ? .on : .off
            switchButton.action = action
            switchButton.target = self
            switchButton.controlSize = .mini
            switchButton.heightAnchor.constraint(equalToConstant: 25).isActive = true
            return switchButton
        } else {
            let button = NSButton()
            button.setButtonType(.switch)
            button.state = state ? .on : .off
            button.title = ""
            button.action = action
            button.target = self
            return button
        }
    }
}
