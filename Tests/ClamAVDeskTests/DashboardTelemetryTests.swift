import Foundation
import Testing
@testable import ClamAVDesk

struct DashboardTelemetryTests {
    @Test func noMeasurementsAreInventedBeforeSampling() {
        var telemetry = ScanTelemetry()
        #expect(telemetry.currentRate == nil)
        #expect(telemetry.averageRate == nil)
        #expect(telemetry.peakRate == nil)
        telemetry.start(queues: [100], now: 10)
        telemetry.sample(completed: 50, now: 10.2)
        #expect(telemetry.samples.isEmpty)
        #expect(telemetry.averageRate == nil)
        #expect(telemetry.peakRate == nil)
    }

    @Test func ratesUseActualCountsAndElapsedIntervals() {
        var telemetry = ScanTelemetry()
        telemetry.start(queues: [1000], now: 10)
        telemetry.sample(completed: 100, now: 12)
        #expect(telemetry.currentRate == 50)
        #expect(telemetry.averageRate == 50)
        #expect(telemetry.peakRate == 50)
        telemetry.sample(completed: 400, now: 15)
        #expect(telemetry.currentRate == 100)
        #expect(telemetry.averageRate == 80)
        #expect(telemetry.peakRate == 100)
        telemetry.sample(completed: 400, now: 16)
        #expect(telemetry.currentRate == 0)
        #expect(telemetry.averageRate == 400.0 / 6)
        #expect(telemetry.peakRate == 100)
    }

    @Test func sessionPeakSurvivesChartEvictionAndResetClearsEverything() {
        var telemetry = ScanTelemetry()
        telemetry.start(queues: [2000], now: 0)
        telemetry.sample(completed: 1000, now: 1)
        for time in 2...70 { telemetry.sample(completed: 1000, now: Double(time)) }
        #expect(telemetry.samples.count <= 61)
        #expect(telemetry.samples.allSatisfy { $0.filesPerSecond == 0 })
        #expect(telemetry.peakRate == 1000)
        #expect(telemetry.averageRate == 1000.0 / 70)
        telemetry.start(queues: [10], now: 100)
        #expect(telemetry.averageRate == nil)
        #expect(telemetry.peakRate == nil)
        #expect(telemetry.samples.isEmpty)
    }

    @Test func dialRangeIsExplicitAndFractionsCannotOverflow() {
        #expect(ScanSpeedScale.maximum(for: nil) == 10)
        #expect(ScanSpeedScale.maximum(for: 0) == 10)
        #expect(ScanSpeedScale.maximum(for: 51) == 100)
        #expect(ScanSpeedScale.maximum(for: 1200) == 2000)
        #expect(ScanSpeedScale.maximum(for: .infinity) == 10)
        #expect(ScanSpeedScale.fraction(rate: 50, maximum: 100) == 0.5)
        #expect(ScanSpeedScale.fraction(rate: 200, maximum: 100) == 1)
        #expect(ScanSpeedScale.fraction(rate: -1, maximum: 100) == 0)
        #expect(ScanSpeedScale.fraction(rate: .nan, maximum: 100) == 0)
    }
}
