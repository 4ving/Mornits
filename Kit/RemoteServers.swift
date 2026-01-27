//
//  RemoteServers.swift
//  Mornits
//
//  Created by Antigravity on 18/01/2026.
//

import Foundation

public struct RemoteDisk: Codable {
    public var name: String
    public var mountPoint: String
    public var size: Int64
    public var free: Int64
    public var used: Int64 { size - free }

    public var read: Int64 = 0
    public var write: Int64 = 0
    public var totalRead: Int64 = 0
    public var totalWrite: Int64 = 0
}

public struct RemoteProcess: Codable {
    public var pid: Int
    public var name: String
    public var read: Int
    public var write: Int
    public var ram: Int  // Bytes
    public var cpu: Double = 0  // 0-1.0 (percent of Total CPU capacity, or single core?)
}

public struct RemoteNetworkInterface: Codable {
    public var name: String
    public var displayName: String
    public var upload: Int64 = 0
    public var download: Int64 = 0
    public var totalUpload: Int64 = 0
    public var totalDownload: Int64 = 0
}

public struct RemoteNetworkProcess: Codable {
    public var pid: Int
    public var name: String
    public var upload: Int
    public var download: Int
}

public struct RemoteStats {
    public var cpu: Double? = nil  // 0-1.0
    public var cpuDetails: (system: Double, user: Double, idle: Double)? = nil
    public var loadAvg: (load1: Double, load5: Double, load15: Double)? = nil
    public var frequency: Double? = nil
    public var temperature: Double? = nil
    public var uptime: TimeInterval? = nil
    public var ram: Double? = nil  // 0-1.0
    public var ramUsed: Int64 = 0
    public var ramTotal: Int64 = 0
    public var disk: Double? = nil  // 0-1.0 (Aggregate or Root?) - keeping for backward compat or summary
    public var disks: [RemoteDisk] = []
    public var diskRead: Int64 = 0  // Bytes/s
    public var diskWrite: Int64 = 0  // Bytes/s
    public var upload: Int64 = 0  // Bytes/s
    public var download: Int64 = 0  // Bytes/s
    public var processes: [RemoteProcess] = []
    public var interfaces: [RemoteNetworkInterface] = []

    public var nethogsStatus: String = "Unknown"  // Unknown, OK, Missing, Error
    public var networkProcesses: [RemoteNetworkProcess] = []

    public var publicIP: String? = nil
    public var countryCode: String? = nil
    public var latency: Double? = nil
}

public struct SSHServer: Codable, Identifiable, Equatable {
    public var id: UUID = UUID()
    public var name: String
    public var host: String
    public var port: Int = 22
    public var user: String
    public var keyPath: String = "~/.ssh/id_rsa"
    public var password: String? = nil
    public var enabled: Bool = true

    public init(
        name: String, host: String, port: Int, user: String, keyPath: String, password: String?,
        enabled: Bool
    ) {
        self.name = name
        self.host = host
        self.port = port
        self.user = user
        self.keyPath = keyPath
        self.password = password
        self.enabled = enabled
    }
}

public class RemoteServersManager: ObservableObject {
    public static let shared = RemoteServersManager()

    @Published public var servers: [SSHServer] = []

    @Published public var data: [UUID: RemoteStats] = [:]

    // Persistence for offline/connecting state
    public var knownInterfaces: [UUID: [RemoteNetworkInterface]] = [:]

    public var localEnabled: Bool {
        get { UserDefaults.standard.value(forKey: "ssh_local_enabled") as? Bool ?? true }
        set {
            UserDefaults.standard.set(newValue, forKey: "ssh_local_enabled")
            NotificationCenter.default.post(name: .init("RemoteData_Settings_Updated"), object: nil)
        }
    }

    private var timer: Timer?
    private let queue = DispatchQueue(
        label: "com.4ving.mornits.remote.ssh", attributes: .concurrent)
    private let lock = NSLock()

    private var netState: [UUID: [String: (upload: Int64, download: Int64, time: TimeInterval)]] =
        [:]
    private var diskState: [UUID: [String: (read: Int64, write: Int64, time: TimeInterval)]] = [:]
    private var cpuState: [UUID: [Double]] = [:]  // [user, nice, system, idle, iowait, irq, softirq, steal]
    private var processState:
        [UUID: [Int: (read: Int, write: Int, ticks: Int, time: TimeInterval)]] = [:]

    // Linux command to fetch all stats in one go
    // CPU: /proc/stat
    // NET: /proc/net/dev
    // DISK IO: /proc/diskstats
    // PROCESSES: top IO (via /proc/*/io) - expensive, so we try to be efficient
    // We use grep to fetch all readable io files and comm files.
    private var cmd: String {
        let pingTarget = Store.shared.string(key: "Network_pingAddr", defaultValue: "1.1.1.1")
        let cpuN = Store.shared.int(key: "CPU_processes", defaultValue: 8)
        let ramN = Store.shared.int(key: "RAM_processes", defaultValue: 8)
        let count = max(cpuN, ramN)
        let n = count > 0 ? count : 15  // Fallback or strict

        return
            "head -n1 /proc/stat; echo '___CPU_EXT___'; cat /proc/loadavg; grep 'cpu MHz' /proc/cpuinfo | awk -F: '{sum+=\\$2} END {if(NR>0) print \"cpu MHz : \" sum/NR}'; cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null || cat /sys/class/hwmon/hwmon0/temp1_input 2>/dev/null || cat /sys/devices/virtual/thermal/thermal_zone0/temp 2>/dev/null; cat /proc/uptime; echo '___END_CPU_EXT___'; free | grep Mem; df -Pk; echo '___PROCESSES___'; ps -Ao pid,pcpu,rss,comm --no-headers --sort=-pcpu | head -n \(n); echo '___SEP___'; ps -Ao pid,pcpu,rss,comm --no-headers --sort=-rss | head -n \(n); echo '___END_PROCESSES___'; cat /proc/net/dev; echo '___NET_STATE___'; for i in /sys/class/net/*; do echo -n \"\\${i##*/}:\" && cat \"\\$i/operstate\" 2>/dev/null || echo \"unknown\"; done; echo '___END_NET_STATE___'; echo '___PUBLIC_IP___'; curl -4 -s --connect-timeout 2 https://api.mac-stats.com/ip; echo ''; echo '___END_PUBLIC_IP___'; echo '___PING___'; ping -c 1 -W 1 \(pingTarget) | grep 'time='; echo '___END_PING___'; cat /proc/diskstats"
    }

    init() {
        self.load()
        self.start()
    }

    public func start() {
        if self.timer != nil { return }
        self.timer = Timer.scheduledTimer(
            withTimeInterval: 3, repeats: true,
            block: { _ in
                self.fetchAll()
            })
    }

    public func stop() {
        self.timer?.invalidate()
        self.timer = nil
    }

    private var activeTasks: [UUID: Process] = [:]

    public func addServer(_ server: SSHServer) {
        self.servers.append(server)
        self.save()
        NotificationCenter.default.post(name: .init("RemoteData_Settings_Updated"), object: nil)
    }

    public func updateServer(_ server: SSHServer) {
        if let idx = self.servers.firstIndex(where: { $0.id == server.id }) {
            self.servers[idx] = server
            self.save()

            if !server.enabled {
                self.lock.lock()
                if let task = self.activeTasks[server.id] {
                    task.terminate()
                    self.activeTasks.removeValue(forKey: server.id)
                }
                self.data.removeValue(forKey: server.id)
                self.lock.unlock()
            }

            NotificationCenter.default.post(name: .init("RemoteData_Settings_Updated"), object: nil)
        }
    }

    public func removeServer(_ id: UUID) {
        self.servers.removeAll(where: { $0.id == id })
        self.save()

        self.lock.lock()
        if let task = self.activeTasks[id] {
            task.terminate()
            self.activeTasks.removeValue(forKey: id)
        }
        self.data.removeValue(forKey: id)
        self.lock.unlock()

        NotificationCenter.default.post(name: .init("RemoteData_Settings_Updated"), object: nil)
    }

    public func getKnownInterfaces(_ id: UUID) -> [RemoteNetworkInterface]? {
        self.lock.lock()
        defer { self.lock.unlock() }
        return self.knownInterfaces[id]
    }

    private func load() {
        if let data = UserDefaults.standard.data(forKey: "ssh_servers"),
            let list = try? JSONDecoder().decode([SSHServer].self, from: data)
        {
            self.servers = list
        }

        if let data = UserDefaults.standard.data(forKey: "ssh_known_interfaces"),
            let map = try? JSONDecoder().decode([UUID: [RemoteNetworkInterface]].self, from: data)
        {
            self.knownInterfaces = map
        }
    }

    private func save() {
        if let data = try? JSONEncoder().encode(self.servers) {
            UserDefaults.standard.set(data, forKey: "ssh_servers")
        }

        if let data = try? JSONEncoder().encode(self.knownInterfaces) {
            UserDefaults.standard.set(data, forKey: "ssh_known_interfaces")
        }
    }

    private func fetchAll() {
        for server in self.servers where server.enabled {
            self.queue.async {
                self.fetch(server)
            }
        }
    }

    private func fetch(_ server: SSHServer) {
        let task = Process()
        let outputPipe = Pipe()
        task.standardOutput = outputPipe

        if let password = server.password, !password.isEmpty {
            task.launchPath = "/usr/bin/expect"
            let escapedCmd = self.cmd.replacingOccurrences(of: "\"", with: "\\\"")
            let escapedPwd = password.replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "$", with: "\\$")

            let expectScript = """
                match_max 500000
                set timeout 10
                spawn ssh -p \(server.port) -o StrictHostKeyChecking=no -o ConnectTimeout=5 \(server.user)@\(server.host) "\(escapedCmd)"
                expect {
                    "password:" { send "\(escapedPwd)\\r"; exp_continue }
                    eof
                }
                """
            task.arguments = ["-c", expectScript]
        } else {
            task.launchPath = "/usr/bin/ssh"
            let keyPath = NSString(string: server.keyPath).expandingTildeInPath
            task.arguments = [
                "-p", "\(server.port)", "-i", keyPath, "-o", "StrictHostKeyChecking=no", "-o",
                "ConnectTimeout=5", "\(server.user)@\(server.host)", self.cmd,
            ]
        }

        self.lock.lock()
        self.activeTasks[server.id] = task
        self.lock.unlock()

        let start = Date()
        do {
            try task.run()
        } catch {
            print("SSH Error: \(error)")
            self.lock.lock()
            self.activeTasks.removeValue(forKey: server.id)
            self.lock.unlock()
            return
        }

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()

        self.lock.lock()
        self.activeTasks.removeValue(forKey: server.id)
        self.lock.unlock()

        let duration = Date().timeIntervalSince(start) * 1000  // ms
        guard let output = String(data: outputData, encoding: .utf8) else { return }

        // Filter out expect/ssh garbage log if using expect
        var cleanOutput = output
        if server.password != nil {
            // Expect might output the command and password prompt, need to clean it.
            // A simple way is to look for the known starting lines of our command output.
            // Our command output starts with "cpu " from /proc/stat
            if let range = cleanOutput.range(of: "cpu  ") {  // /proc/stat usually has two spaces after cpu
                cleanOutput = String(cleanOutput[range.lowerBound...])
            } else if let range = cleanOutput.range(of: "cpu ") {
                cleanOutput = String(cleanOutput[range.lowerBound...])
            }
        }

        self.parse(server.id, cleanOutput, duration)
    }

    private func parse(_ id: UUID, _ output: String, _ latency: Double) {


        if !output.contains("Filesystem") || !output.contains("cpu ") { return }

        // Parse Public IP
        var publicIP: String? = nil
        var countryCode: String? = nil
        if let start = output.range(of: "___PUBLIC_IP___"),
            let end = output.range(of: "___END_PUBLIC_IP___")
        {
            let ipRange = start.upperBound..<end.lowerBound
            let regex = String(output[ipRange]).trimmingCharacters(in: .whitespacesAndNewlines)
            // Parse JSON
            if let data = regex.data(using: .utf8),
                let json = try? JSONSerialization.jsonObject(with: data, options: [])
                    as? [String: Any]
            {
                publicIP = json["ipv4"] as? String
                countryCode = json["country"] as? String
            }
        }

        var stats = self.data[id] ?? RemoteStats()
        let cleanOutput = output.replacingOccurrences(of: "\r", with: "")
        let lines = cleanOutput.components(separatedBy: "\n")


        var memLine = ""
        var diskLines: [String] = []
        var netLines: [String] = []
        var diskIOLines: [String] = []



        for line in lines {

            if line.hasPrefix("Mem:") {
                memLine = line
                continue
            }
            if line.hasPrefix("/dev/") || line.contains("Filesystem") {
                diskLines.append(line)
                continue
            }
            if line.contains(":") { netLines.append(line) }

            // simple check for diskstats
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            if parts.count >= 10
                && (parts[2].hasPrefix("sd") || parts[2].hasPrefix("vd")
                    || parts[2].hasPrefix("nvme") || parts[2].hasPrefix("mmcblk")
                    || parts[2].hasPrefix("xvd"))
            {
                diskIOLines.append(line)
            }
        }

        // Parse RAM
        let memParts = memLine.split(separator: " ", omittingEmptySubsequences: true)
        if memParts.count >= 3, let total = Double(memParts[1]), let used = Double(memParts[2]) {
            stats.ram = used / total
            stats.ramTotal = Int64(total) * 1024
            stats.ramUsed = Int64(used) * 1024
        }

        // Parse Disk
        // df -Pk output: Filesystem 1024-blocks Used Available Capacity Mounted on
        var physicalDisks: [String: RemoteDisk] = [:]

        for line in diskLines {
            if line.contains("Filesystem") { continue }
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)
            if parts.count >= 6 {
                // /dev/sda1 -> sda
                var name = String(parts[0])
                if name.hasPrefix("/dev/") {
                    name = name.replacingOccurrences(of: "/dev/", with: "")
                }
                if name.hasPrefix("mapper/") {  // LVM
                    // mapper/ubuntu--vg-ubuntu--lv -> map to sda if possible?
                    // LVM is tricky without lsblk -D or similar.
                    // For now, keep as is if it's main FS.
                    // Or try to strip numbers to guess physical?
                    // Let's stick to simple stripping for standard partitions.
                }

                // Strip partition number for standard disks (sda1 -> sda, nvme0n1p1 -> nvme0n1)
                var physicalName = name
                if name.hasPrefix("sd") || name.hasPrefix("vd") || name.hasPrefix("xvd")
                    || name.hasPrefix("hd")
                {
                    physicalName = name.trimmingCharacters(in: .decimalDigits)
                } else if name.hasPrefix("nvme") || name.hasPrefix("mmcblk") {
                    if let range = name.range(of: "p\\d+$", options: .regularExpression) {
                        physicalName = String(name[..<range.lowerBound])
                    }
                }

                if let size = Int64(parts[1]), let used = Int64(parts[2]),
                    let free = Int64(parts[3])
                {
                    // df -k returns 1024-blocks, convert to bytes
                    if var disk = physicalDisks[physicalName] {
                        disk.size += size * 1024
                        disk.free += free * 1024
                        // Append mount point
                        disk.mountPoint += ", \(parts[5])"
                        physicalDisks[physicalName] = disk
                    } else {
                        let disk = RemoteDisk(
                            name: physicalName,
                            mountPoint: String(parts[5]),
                            size: size * 1024,
                            free: free * 1024
                        )
                        physicalDisks[physicalName] = disk
                    }

                    if parts[5] == "/" {  // Root usage fallback
                        stats.disk = Double(used) / Double(size)
                    }
                }
            }
        }

        // Parse Network
        var totalUp: Int64 = 0
        var totalDown: Int64 = 0
        let now = Date().timeIntervalSince1970

        self.lock.lock()
        if self.netState[id] == nil {
            self.netState[id] = [:]
        }
        var currentNetState = self.netState[id] ?? [:]
        self.lock.unlock()

        // Parse Network State
        var interfaceStates: [String: String] = [:]
        if output.contains("___NET_STATE___") {
            if let startIdx = lines.firstIndex(of: "___NET_STATE___"),
                let endIdx = lines.lastIndex(of: "___END_NET_STATE___"),
                startIdx < endIdx
            {
                let stateLines = lines[startIdx + 1..<endIdx]
                for line in stateLines {
                    let parts = line.split(separator: ":")
                    if parts.count == 2 {
                        let name = String(parts[0]).trimmingCharacters(in: .whitespaces)
                        let state = String(parts[1]).trimmingCharacters(in: .whitespaces)
                        interfaceStates[name] = state
                    }
                }
            }
        }

        var interfaces: [RemoteNetworkInterface] = []

        for line in netLines {
            let parts = line.split(separator: ":")
            if parts.count == 2 {
                let name = String(parts[0]).trimmingCharacters(in: .whitespaces)
                let values = parts[1].split(separator: " ", omittingEmptySubsequences: true)
                // /proc/net/dev format:
                // name: bytes packets errs drop fifo frame compressed multicast | bytes packets errs drop fifo colls carrier compressed
                // we need 1st (recv bytes) and 9th (trans bytes) - values index 0 and 8

                if values.count >= 9,
                    let d = Int64(values[0]),
                    let u = Int64(values[8])
                {



                    let prevObj = currentNetState[name]
                    let prevTime = prevObj?.2 ?? now
                    let prevDownload = prevObj?.1 ?? d
                    let prevUpload = prevObj?.0 ?? u

                    let dt = now - prevTime
                    if dt > 0 {
                        let downRate = Int64(Double(d - prevDownload) / dt)
                        let upRate = Int64(Double(u - prevUpload) / dt)

                        if downRate >= 0 && upRate >= 0 {  // Sanity check
                            let isVirtual =
                                name.hasPrefix("lo") || name.hasPrefix("tun")
                                || name.hasPrefix("tap") || name.hasPrefix("veth")
                                || name.hasPrefix("docker") || name.hasPrefix("br")
                                || name.hasPrefix("lxd") || name.hasPrefix("virbr")
                                || name.hasPrefix("vnet") || name.hasPrefix("cali")
                                || name.hasPrefix("flannel") || name.hasPrefix("kube")
                                || name.hasPrefix("cni") || name.hasPrefix("safeline")

                            let state = interfaceStates[name] ?? "unknown"
                            let isDown = state != "up" && state != "unknown"  // if unknown, keep it? or strict 'up'?
                            // usually physical unplugged is "down".

                            if !isVirtual && !isDown {
                                var interface = RemoteNetworkInterface(
                                    name: name, displayName: name)
                                interface.download = downRate
                                interface.upload = upRate
                                interface.totalDownload = d
                                interface.totalUpload = u
                                interfaces.append(interface)

                                totalDown += downRate
                                totalUp += upRate
                            }
                        }
                    }

                    currentNetState[name] = (u, d, now)
                }
            }
        }
        self.lock.lock()
        self.netState[id] = currentNetState
        self.lock.unlock()

        stats.interfaces = interfaces.sorted(by: { $0.name < $1.name })
        stats.download = totalDown
        stats.upload = totalUp

        // Parse Disk IO
        // Update local cache
        self.lock.lock()
        if self.diskState[id] == nil {
            self.diskState[id] = [:]
        }
        var currentDiskState = self.diskState[id] ?? [:]
        self.lock.unlock()

        for line in diskIOLines {
            let parts = line.split(separator: " ", omittingEmptySubsequences: true)

            // Format check
            if parts.count < 3 { continue }

            // 8 0 sda ...
            let name = String(parts[2])

            // Filter out partitions (e.g. sda1, nvme0n1p1) to avoid double counting
            // Regular disks: sda, vda, xvda, hda
            // NVMe/MMC: nvme0n1, mmcblk0
            var isPartition = false
            if name.hasPrefix("sd") || name.hasPrefix("vd") || name.hasPrefix("xvd")
                || name.hasPrefix("hd")
            {
                if name.last?.isNumber == true { isPartition = true }
            } else if name.hasPrefix("nvme") || name.hasPrefix("mmcblk") {
                if name.contains("p") && name.last?.isNumber == true { isPartition = true }
            }

            if !isPartition {
                if parts.count >= 10, let read = Int64(parts[5]), let written = Int64(parts[9]) {

                    if let prev = currentDiskState[name] {
                        let dt = now - prev.time
                        if dt > 0 {
                            let readDiff = read - prev.read
                            let writeDiff = written - prev.write

                            let rRate = Int64(Double(readDiff * 512) / dt)
                            let wRate = Int64(Double(writeDiff * 512) / dt)

                            if var d = physicalDisks[name] {
                                d.read = rRate
                                d.write = wRate
                                d.totalRead = read * 512
                                d.totalWrite = written * 512
                                physicalDisks[name] = d
                            } else {

                                // Disk present in IO but not mounted.
                                // Add it to show IO?
                                var d = RemoteDisk(name: name, mountPoint: "", size: 0, free: 0)
                                d.read = rRate
                                d.write = wRate
                                d.totalRead = read * 512
                                d.totalWrite = written * 512
                                physicalDisks[name] = d
                            }
                        }
                    } else {

                    }

                    currentDiskState[name] = (read, written, now)
                }
            }
        }
        self.lock.lock()
        self.diskState[id] = currentDiskState
        self.lock.unlock()

        stats.disks = physicalDisks.map { $0.value }.sorted(by: { $0.name < $1.name })

        // Sum up total IO for summary (legacy/overview)
        stats.diskRead = stats.disks.reduce(0, { $0 + $1.read })
        stats.diskWrite = stats.disks.reduce(0, { $0 + $1.write })

        // Parse CPU
        // format: cpu user nice system idle iowait irq softirq steal guest guest_nice
        let foundCpuLine = lines.first(where: { $0.hasPrefix("cpu ") && !$0.contains("MHz") }) ?? ""
        let cpuParts = foundCpuLine.split(separator: " ", omittingEmptySubsequences: true)
            .dropFirst()
            .compactMap { Double($0) }
        if cpuParts.count >= 4 {
            let valUser = cpuParts[0]
            let valNice = cpuParts[1]
            let valSystem = cpuParts[2]
            let valIdle = cpuParts[3]
            var valTotal = valUser + valNice + valSystem + valIdle

            // Add optional fields if present
            if cpuParts.count >= 5 { valTotal += cpuParts[4] }  // iowait
            if cpuParts.count >= 6 { valTotal += cpuParts[5] }  // irq
            if cpuParts.count >= 7 { valTotal += cpuParts[6] }  // softirq
            if cpuParts.count >= 8 { valTotal += cpuParts[7] }  // steal

            self.lock.lock()
            if let prev = self.cpuState[id], prev.count == cpuParts.count {
                let prevUser = prev[0]
                let prevNice = prev[1]
                let prevSystem = prev[2]
                let prevIdle = prev[3]
                var prevTotal = prevUser + prevNice + prevSystem + prevIdle

                if prev.count >= 5 { prevTotal += prev[4] }
                if prev.count >= 6 { prevTotal += prev[5] }
                if prev.count >= 7 { prevTotal += prev[6] }
                if prev.count >= 8 { prevTotal += prev[7] }

                let diffTotal = valTotal - prevTotal
                let diffIdle = valIdle - prevIdle



                if diffTotal > 0 {

                    stats.cpu = Double(diffTotal - diffIdle) / Double(diffTotal)

                    let sysDiff = valSystem - prevSystem
                    let usrDiff = (valUser - prevUser) + (valNice - prevNice)



                    stats.cpuDetails = (
                        system: Double(sysDiff) / Double(diffTotal),
                        user: Double(usrDiff) / Double(diffTotal),
                        idle: Double(diffIdle) / Double(diffTotal)
                    )
                }
            }

            self.cpuState[id] = cpuParts
            self.lock.unlock()
        }

        // Parse Processes

        var procs: [Int: RemoteProcess] = [:]

        if let startIdx = lines.firstIndex(of: "___PROCESSES___") {
            let suffix = lines.suffix(from: startIdx + 1)
            let endIdx = suffix.firstIndex(of: "___END_PROCESSES___") ?? suffix.endIndex
            let procLines = suffix.prefix(upTo: endIdx)

            for line in procLines {
                if line == "___SEP___" { continue }

                // Format: PID %CPU RSS COMMAND
                // 123 0.0 1024 systemd
                let parts = line.split(separator: " ", omittingEmptySubsequences: true)
                guard parts.count >= 4 else { continue }

                if let pid = Int(parts[0]), let cpu = Double(parts[1]), let rss = Int(parts[2]) {
                    // Reconstruct command (parts[3]...)
                    let comm = parts.dropFirst(3).joined(separator: " ")

                    let p = RemoteProcess(
                        pid: pid,
                        name: comm,
                        read: 0,
                        write: 0,
                        ram: rss * 1024,  // RSS is in KB usually
                        cpu: cpu / 100.0  // % to 0-1.0
                    )
                    procs[pid] = p
                }
            }
        }

        stats.processes = Array(procs.values)

        // Cleanup old pids not needed as we rebuild list every time now
        // But we might want to update processState if we were tracking IO...
        // Logic for processState handling is removed as we stateless-ly fetch from ps now.

        // Parse Nethogs
        if output.contains("___NETHOGS___") {
            stats.nethogsStatus = "OK"
            if let startIdx = lines.firstIndex(of: "___NETHOGS___") {
                let suffix = lines.suffix(from: startIdx + 1)
                // Filter out error markers or subsequent blocks if any
                let nethogsLines = suffix.prefix(while: { !$0.contains("___") })

                var networkProcs: [RemoteNetworkProcess] = []
                for line in nethogsLines {
                    // Example: 1234/root /usr/bin/python3 eth0 10.5 20.1
                    // Nethogs format can vary, but -t mode usually gives: PID/USER PROGRAM DEV SENT RECEIVED
                    _ = line.split(separator: "\t", omittingEmptySubsequences: true)  // Nethogs -t uses tabs? or spaces? output varies.
                    // Assuming space/tab separated
                    let spaceParts = line.split(separator: " ", omittingEmptySubsequences: true)
                    // Try to match standard nethogs -t output
                    // PID/USER   PROGRAM   DEV   SENT   RECEIVED
                    // count >= 5
                    if spaceParts.count >= 5, let sent = Double(spaceParts[spaceParts.count - 2]),
                        let received = Double(spaceParts[spaceParts.count - 1])
                    {
                        // PID/USER might be "1234/root" or just "1234" depending on version
                        // PROGRAM might contain spaces? usually nethogs truncates or handles it.
                        let pidUser = String(spaceParts[0])
                        let pidString = pidUser.split(separator: "/").first ?? ""
                        let pid = Int(pidString) ?? 0

                        var name = String(spaceParts[1])
                        // If name is full path, take last component
                        if name.contains("/") {
                            name = String(name.split(separator: "/").last ?? Substring(name))
                        }

                        // kb/s to bytes/s? Nethogs display units.
                        // nethogs -t usually displays in KB/s.
                        // Let's assume KB/s for now, verify later.
                        let upload = Int(sent * 1024)
                        let download = Int(received * 1024)

                        if upload > 0 || download > 0 {
                            networkProcs.append(
                                RemoteNetworkProcess(
                                    pid: pid, name: name, upload: upload, download: download))
                        }
                    } else {
                        // Try tab split if spaces didn't work (unlikely for splitting strict columns but good backup)
                        // OR handle unexpected format
                    }
                }
                stats.networkProcesses = networkProcs.sorted(by: {
                    $0.upload + $0.download > $1.upload + $1.download
                })
            }
        }

        // Parse Ping
        if let startIdx = lines.firstIndex(of: "___PING___") {
            let suffix = lines.suffix(from: startIdx + 1)
            if let line = suffix.first(where: { $0.contains("time=") }) {
                // 64 bytes from 1.1.1.1: icmp_seq=1 ttl=58 time=12.3 ms
                let parts = line.split(separator: " ")
                if let timePart = parts.first(where: { $0.hasPrefix("time=") }) {
                    let valueString = timePart.dropFirst(5)  // remove "time="
                    if let val = Double(valueString) {
                        stats.latency = val
                    }
                }
            }
        } else if output.contains("___NETHOGS_ERROR___") {
            stats.nethogsStatus = "Error"
        }

        // Parse CPU Info
        if let startIdx = lines.firstIndex(of: "___CPU_EXT___"),
            let endIdx = lines.firstIndex(of: "___END_CPU_EXT___"),
            startIdx < endIdx
        {
            let extLines = lines[startIdx + 1..<endIdx]
            for line in extLines {
                // loadavg: 0.13 0.10 0.09 1/438 12345
                if line.contains(" ") && !line.contains("cpu MHz") {
                    let parts = line.split(separator: " ")
                    if parts.count >= 3,
                        let l1 = Double(parts[0]),
                        let l5 = Double(parts[1]),
                        let l15 = Double(parts[2])
                    {
                        stats.loadAvg = (l1, l5, l15)
                    }
                }
                // frequency: cpu MHz : 2400.000
                if line.contains("cpu MHz") {
                    let parts = line.split(separator: ":")
                    if parts.count == 2,
                        let val = Double(parts[1].trimmingCharacters(in: .whitespaces))
                    {
                        stats.frequency = val
                    }
                }
                // temperature: 45000 (integers, divide by 1000)
                if let val = Int(line), val > 1000 {
                    // Simple heuristic: if line is just number and > 1000, usually thermal_zone output
                    stats.temperature = Double(val) / 1000.0
                }

                // uptime: 12345.67 123123.45 (uptime idle_time)
                // format: contains space and two doubles.
                // loadavg also has spaces but 3-5 parts. uptime usually 2 parts (sometimes more if logic varies but /proc/uptime only 2)
                if line.contains(" "), !line.contains("cpu MHz") {
                    let parts = line.split(separator: " ")
                    if parts.count == 2, let t = Double(parts[0]) {
                        stats.uptime = t
                    }
                }
            }
        }

        stats.publicIP = publicIP
        stats.countryCode = countryCode
        if stats.latency == nil {
            stats.latency = latency
        }

        // Cache known interfaces
        if !stats.interfaces.isEmpty {
            self.lock.lock()
            self.knownInterfaces[id] = stats.interfaces
            self.lock.unlock()
            self.save()
        }

        DispatchQueue.main.async {
            self.data[id] = stats
        }
    }
}
