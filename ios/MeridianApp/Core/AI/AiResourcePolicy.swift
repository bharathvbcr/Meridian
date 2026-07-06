// AiResourcePolicy.swift
// Meridian — iOS 27 / Swift 6
//
// Tiered AI degradation under Low Power Mode or critical thermal state.

import Foundation

final class AiResourcePolicy: @unchecked Sendable {
    enum Tier: Sendable {
        case normal
        case degraded
        case critical
    }

    private let lock = NSLock()
    private var lowPowerMode: Bool
    private var thermalState: ProcessInfo.ThermalState

    init() {
        lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
        thermalState = ProcessInfo.processInfo.thermalState
        NotificationCenter.default.addObserver(
            forName: .NSProcessInfoPowerStateDidChange,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.lock.lock()
            self?.lowPowerMode = ProcessInfo.processInfo.isLowPowerModeEnabled
            self?.lock.unlock()
        }
        if #available(iOS 11.0, *) {
            NotificationCenter.default.addObserver(
                forName: ProcessInfo.thermalStateDidChangeNotification,
                object: nil,
                queue: .main
            ) { [weak self] _ in
                self?.lock.lock()
                self?.thermalState = ProcessInfo.processInfo.thermalState
                self?.lock.unlock()
            }
        }
    }

    func currentTier() -> Tier {
        lock.lock()
        defer { lock.unlock() }
        if lowPowerMode { return .degraded }
        switch thermalState {
        case .critical, .serious:
            return .critical
        case .fair:
            return .degraded
        case .nominal:
            return .normal
        @unknown default:
            return .normal
        }
    }

    func preferRulesOnly() -> Bool { currentTier() != .normal }

    func skipLlm() -> Bool { currentTier() == .critical }

    func skipPrewarm() -> Bool { currentTier() != .normal }
}
