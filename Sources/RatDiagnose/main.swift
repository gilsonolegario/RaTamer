import Foundation
import RatTamerCore

extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}

print("RatDiagnose — MX Master 2S diagnostics")

let window = Double(CommandLine.arguments.dropFirst()
    .first(where: { Int($0) != nil }) ?? "15") ?? 15
let wantDivert = CommandLine.arguments.contains("--divert")

do {
    let device = try HIDLocator.openReceiver()
    let session = HIDPPSession(device: device)

    print("Feature presence:")
    for feature in [0x2110, 0x2111, 0x2121, 0x2150, 0x2201, 0x1000, 0x1001, 0x1004] {
        let index = try session.getFeatureIndex(featureID: UInt16(feature), deviceIndex: 1)
        if let index {
            print(String(format: "  0x%04X present at index 0x%02X", feature, index))
        } else {
            print(String(format: "  0x%04X absent", feature))
        }
    }

    if CommandLine.arguments.contains("--ping") {
        print("Ping probe: sending short ping to Root, dumping raw replies for 2s...")
        for _ in 0..<5 {
            try session.sendShort(deviceIndex: 1, featureIndex: 0, functionID: 0,
                                  params: [0x00, 0x00, 0x00])
            let deadline = Date().addingTimeInterval(0.4)
            var answered = false
            while Date() < deadline {
                if let resp = try session.readReport(timeout: 0.1) {
                    let hex = resp.map { String(format: "%02X", $0) }.joined(separator: " ")
                    print("  reply: \(hex)")
                    answered = true
                }
            }
            print("  ping \(answered ? "OK" : "NO REPLY")")
            Thread.sleep(forTimeInterval: 0.3)
        }
        print("session.ping (validated):")
        for _ in 0..<3 {
            let ok = (try? session.ping(deviceIndex: 1)) ?? false
            print("  ping(deviceIndex:1) = \(ok)")
            Thread.sleep(forTimeInterval: 0.3)
        }
        exit(0)
    }

    if let thumbIndex = try session.getFeatureIndex(featureID: 0x2150, deviceIndex: 1) {
        if let resp = try session.request(deviceIndex: 1, featureIndex: thumbIndex,
                                          functionID: 0x00), resp.count >= 7 {
            let d = Array(resp.dropFirst(4))
            print(String(format: "Thumbwheel (0x2150): caps=0x%02X has_divert=%@ has_invert=%@",
                         d[0], d[0] & 0x04 == 0x04 ? "Y" : "N", d[0] & 0x02 == 0x02 ? "Y" : "N"))
        }
        if let resp = try session.request(deviceIndex: 1, featureIndex: thumbIndex,
                                          functionID: 0x01), resp.count >= 6 {
            let d = Array(resp.dropFirst(4))
            print(String(format: "  thumbwheel mode=0x%02X inverted=%@ diverted=%@",
                         d[0], d[0] & 0x04 == 0x04 ? "Y" : "N", d[0] & 0x01 == 0x01 ? "Y" : "N"))
        }
    }

    if let smartShiftIndex = try session.getFeatureIndex(featureID: 0x2110, deviceIndex: 1) {
        if let resp = try session.request(deviceIndex: 1, featureIndex: smartShiftIndex,
                                          functionID: 0x00), resp.count >= 7 {
            let d = Array(resp.dropFirst(4))
            print(String(format: "SmartShift (0x2110): wheelMode=%d autoDisengage=%d autoDisengageDefault=%d",
                         d[0], d[1], d[2]))
        }
        if let setArg = CommandLine.arguments.dropFirst().first(where: {
            ["freespin", "ratcheted", "smartshift"].contains($0)
        }) {
            let status: SmartShiftStatus
            switch setArg {
            case "freespin": status = SmartShiftStatus(wheelMode: 1, autoDisengage: 0, autoDisengageDefault: 0)
            case "ratcheted": status = SmartShiftStatus(wheelMode: 2, autoDisengage: 0xFF, autoDisengageDefault: 0)
            default: status = SmartShiftStatus(wheelMode: 2, autoDisengage: 0, autoDisengageDefault: 0)
            }
            try SmartShiftControls(session: session, deviceIndex: 1,
                                   featureIndex: smartShiftIndex)
                .setRatchetControlMode(status: status)
            print("Set SmartShift: \(setArg) (wheelMode=\(status.wheelMode) autoDisengage=\(status.autoDisengage))")
            if let resp = try session.request(deviceIndex: 1, featureIndex: smartShiftIndex,
                                              functionID: 0x00), resp.count >= 7 {
                let d = Array(resp.dropFirst(4))
                print(String(format: "  after: wheelMode=%d autoDisengage=%d autoDisengageDefault=%d",
                             d[0], d[1], d[2]))
            }
        }
        if let auto = CommandLine.arguments.dropFirst().first(where: { Int($0) != nil }),
           let value = UInt8(auto) {
            try SmartShiftControls(session: session, deviceIndex: 1,
                                   featureIndex: smartShiftIndex)
                .setRatchetControlMode(status: SmartShiftStatus(
                    wheelMode: 0, autoDisengage: value, autoDisengageDefault: 0))
            if let resp = try session.request(deviceIndex: 1, featureIndex: smartShiftIndex,
                                              functionID: 0x00), resp.count >= 7 {
                let d = Array(resp.dropFirst(4))
                print(String(format: "Set autoDisengage=%d; after: wheelMode=%d autoDisengage=%d autoDisengageDefault=%d",
                             value, d[0], d[1], d[2]))
            }
        }
    }

    if let batteryIndex = try session.getFeatureIndex(featureID: 0x1000, deviceIndex: 1) {
        if let resp = try session.request(deviceIndex: 1, featureIndex: batteryIndex,
                                          functionID: 0x00), resp.count >= 7 {
            let capacity = Int(resp[4])
            let nextCapacity = Int(resp[5])
            let status = Int(resp[6])
            let statusNames = ["discharging", "recharging", "charging", "charge complete", "recharging below optimal",
                               "invalid battery", "thermal error", "other error"]
            print(String(format: "Battery (0x1000): capacity=%d%% next=%d%% status=%d (%@)",
                         capacity, nextCapacity, status, statusNames[safe: status] ?? "unknown"))
        }
    }

    if let wheelIndex = try session.getFeatureIndex(featureID: 0x2121, deviceIndex: 1) {
        if let resp = try session.request(deviceIndex: 1, featureIndex: wheelIndex,
                                          functionID: 0x00), resp.count >= 5 {
            let multiplier = resp[4]
            let flags = resp[5]
            print(String(format: "HiResWheel (0x2121): multiplier=%d flags=0x%02X has_invert=%@ has_switch=%@",
                         multiplier, flags, (flags >> 3) & 1 == 1 ? "Y" : "N",
                         (flags >> 2) & 1 == 1 ? "Y" : "N"))
        }
        if let resp = try session.request(deviceIndex: 1, featureIndex: wheelIndex,
                                          functionID: 0x01), resp.count >= 5 {
            let mode = resp[4]
            print(String(format: "  wheelMode=0x%02X inverted=%@ resolution=%@ target=%@",
                         mode, (mode >> 2) & 1 == 1 ? "Y" : "N",
                         (mode >> 1) & 1 == 1 ? "high" : "low",
                         mode & 1 == 1 ? "diverted" : "native"))
        }
        if let setArg = CommandLine.arguments.dropFirst().first(where: { ["invert", "normal"].contains($0) }) {
            var mode: UInt8 = 0
            if let resp = try session.request(deviceIndex: 1, featureIndex: wheelIndex,
                                              functionID: 0x01), resp.count >= 5 {
                mode = resp[4]
            }
            if setArg == "invert" {
                mode |= 0x04
            } else {
                mode &= ~0x04
            }
            try session.request(deviceIndex: 1, featureIndex: wheelIndex,
                                functionID: 0x02, params: [mode, 0, 0])
            print("Set wheel invert=\(setArg) (mode=0x\(String(format: "%02X", mode)))")
        }
    }

    if let dpiIndex = try session.getFeatureIndex(featureID: 0x2201, deviceIndex: 1) {
        if let resp = try session.request(deviceIndex: 1, featureIndex: dpiIndex,
                                          functionID: 0x00), resp.count >= 5 {
            let count = resp[4]
            print("DPI (0x2201): sensorCount=\(count)")
            for sensor in 0..<count {
                if let resp = try session.request(deviceIndex: 1, featureIndex: dpiIndex,
                                                  functionID: 0x02, params: [sensor]),
                   resp.count >= 7 {
                    print(String(format: "  sensor %d: dpi=%d defaultDpi=%d",
                                 sensor, (Int(resp[5]) << 8) | Int(resp[6]),
                                 (Int(resp[7]) << 8) | Int(resp[8])))
                }
                if let resp = try session.request(deviceIndex: 1, featureIndex: dpiIndex,
                                                  functionID: 0x01, params: [sensor]),
                   resp.count >= 5 {
                    let vals = Array(resp.dropFirst(5))
                    let parsed = stride(from: 0, to: vals.count - 1, by: 2).map {
                        (Int(vals[$0]) << 8) | Int(vals[$0 + 1])
                    }.filter { $0 != 0 }
                    print("  sensor \(sensor) dpiList: \(parsed.map(\.description).joined(separator: ", "))")
                }
            }
        }
        if let dpiArg = CommandLine.arguments.dropFirst().first(where: { $0.hasPrefix("dpi=") }) {
            let value = UInt16(dpiArg.dropFirst(4)) ?? 0
            try session.request(deviceIndex: 1, featureIndex: dpiIndex,
                                functionID: 0x03, params: [0, UInt8(value >> 8), UInt8(value & 0xFF)])
            print("Set DPI: \(value)")
        }
    }

    guard let featureIndex = try session.getFeatureIndex(
        featureID: ReprogrammableControls.featureID, deviceIndex: 1
    ) else {
        print("Error: feature 0x1B04 not found on device 1")
        exit(1)
    }
    let service = ReprogrammableControls(session: session,
                                         deviceIndex: 1, featureIndex: featureIndex)
    let controls = try service.enumerate()
    print("Controls (feature index 0x\(String(format: "%02X", featureIndex))):")
    for control in controls {
        print(String(format: "  cid=0x%04X tid=0x%04X %@ divertable=%@",
                     control.cid, control.taskID,
                     ControlTaskName.name(for: control.taskID),
                     control.isDivertable ? "Y" : "n"))
    }

    print("Reporting flags:")
    for control in controls {
        if let flags = try service.reportingFlags(cid: control.cid) {
            print(String(format: "  cid=0x%04X flags=0x%02X remap=0x%04X",
                         control.cid, flags.flags, flags.remap))
        }
    }
    if CommandLine.arguments.contains("--reset-remap") {
        try service.resetRemap(cid: 0x0050)
        try service.resetRemap(cid: 0x0051)
        print("Reset remap 0x0050/0x0051.")
        for control in controls where control.cid == 0x0050 || control.cid == 0x0051 {
            if let flags = try service.reportingFlags(cid: control.cid) {
                print(String(format: "  after reset: cid=0x%04X flags=0x%02X remap=0x%04X",
                             control.cid, flags.flags, flags.remap))
            }
        }
    }

    if CommandLine.arguments.contains("--raw") {
        print("Raw report listener for \(Int(window))s. Roll the thumb wheel (horizontal scroll) and press buttons.")
        let deadline = Date().addingTimeInterval(window)
        while Date() < deadline {
            if let report = try session.readReport(timeout: 0.2) {
                let hex = report.map { String(format: "%02X", $0) }.joined(separator: " ")
                print("\(hex)")
            }
        }
        exit(0)
    }

    if wantDivert {
        for control in controls where control.isDivertable {
            try service.setDiverted(cid: control.cid, diverted: true)
        }
        print("Diverted all controls. Press each physical button within \(Int(window))s "
              + "and note the printed cid.")
        let monitor = DivertedButtonMonitor(deviceIndex: 1, featureIndex: featureIndex)
        monitor.onControlPressed = { print("PRESS   0x\(String(format: "%04X", $0))") }
        monitor.onControlReleased = { print("RELEASE 0x\(String(format: "%04X", $0))") }
        let deadline = Date().addingTimeInterval(window)
        while Date() < deadline {
            if let report = try session.readReport(timeout: 0.2) {
                _ = monitor.feed(report)
            }
        }
        for control in controls where control.isDivertable {
            try service.setDiverted(cid: control.cid, diverted: false)
        }
        print("Undiverted.")
    }
} catch {
    print("Error: \(error)")
    exit(1)
}
