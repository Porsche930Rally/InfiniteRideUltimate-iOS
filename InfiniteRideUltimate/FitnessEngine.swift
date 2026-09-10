import Foundation

enum FitnessEngine {
    static func analyze(_ ride: RideActivity, profile: AthleteProfile) -> FitnessResult {
        guard ride.samples.count >= 20 else { return .empty }
        let hrSamples = ride.samples.filter { $0.heartRate > 0 }
        let powered = ride.samples.filter { $0.power > 0 }
        let avgHR = hrSamples.isEmpty ? 0 : Double(hrSamples.map(\.heartRate).reduce(0,+)) / Double(hrSamples.count)
        let avgPower = powered.isEmpty ? 0 : Double(powered.map(\.power).reduce(0,+)) / Double(powered.count)
        let hrr = avgHR > 0 ? (avgHR - Double(profile.restingHR)) / Double(max(1, profile.maximumHR - profile.restingHR)) : 0
        let oxygenDemand = avgPower > 0 ? 10.8 * avgPower / profile.riderKg + 7 : 0
        var baseVO2 = oxygenDemand > 0 && hrr >= 0.55 ? oxygenDemand / min(0.95, max(0.68, hrr)) : 0
        let effort = sustainedEffort(ride.samples, profile: profile)
        if effort.qualifying {
            if baseVO2 == 0 { baseVO2 = effort.vo2 }
            else { baseVO2 = min(baseVO2 + 2, max(baseVO2 - 2, baseVO2 * 0.82 + effort.vo2 * 0.18)) }
        }
        if profile.manualVO2 > 0 { baseVO2 = profile.manualVO2 }
        let ftp20 = bestAveragePower(ride.samples, seconds: 1200) * 0.95
        let ftpShort = bestAveragePower(ride.samples, seconds: 300) * 0.78
        let ftp = max(ftp20, max(ftpShort, avgPower * durationFTPFactor(ride.duration)))
        let sprint = bestAveragePower(ride.samples, seconds: 5)
        let summary: String
        if effort.qualifying {
            summary = String(format: "VO₂ %0.1f from sustained %0.1f mph for %0.2f mi with HR and terrain checks. FTP %0.0f W. Five-second output %0.0f W.", baseVO2, effort.speedMph, effort.miles, ftp, sprint)
        } else {
            summary = String(format: "VO₂ %0.1f from the complete ride. No short-range segment cleared every duration, HR and terrain gate. FTP %0.0f W.", baseVO2, ftp)
        }
        return FitnessResult(vo2: min(95,max(0,baseVO2)), ftp: min(800,max(0,ftp)), shortRangeVO2: effort.qualifying ? effort.vo2 : 0, maxSprint: sprint, qualifying: effort.qualifying, summary: summary)
    }

    private struct Effort { var qualifying=false; var vo2=0.0; var speedMph=0.0; var miles=0.0 }

    private static func sustainedEffort(_ samples: [RideSample], profile: AthleteProfile) -> Effort {
        var best: [RideSample] = [], current: [RideSample] = []
        for sample in samples {
            if sample.speedMps * 2.236936 >= 18 { current.append(sample) }
            else { if duration(current) > duration(best) { best = current }; current = [] }
        }
        if duration(current) > duration(best) { best = current }
        guard best.count > 1 else { return Effort() }
        let seconds = duration(best), meters = max(0,(best.last?.distanceMeters ?? 0) - (best.first?.distanceMeters ?? 0))
        let hrRows = best.filter { $0.heartRate > 0 }, powerRows = best.filter { $0.power > 0 }
        let avgHR = hrRows.isEmpty ? 0 : Double(hrRows.map(\.heartRate).reduce(0,+)) / Double(hrRows.count)
        let avgPower = powerRows.isEmpty ? 0 : Double(powerRows.map(\.power).reduce(0,+)) / Double(powerRows.count)
        let avgSpeed = best.map(\.speedMps).reduce(0,+) / Double(best.count) * 2.236936
        let avgGrade = best.map(\.grade).reduce(0,+) / Double(best.count)
        let hrr = (avgHR - Double(profile.restingHR)) / Double(max(1,profile.maximumHR-profile.restingHR))
        let hrCoverage = Double(hrRows.count) / Double(best.count)
        let measuredCoverage = Double(best.filter(\.powerMeasured).count) / Double(best.count)
        let qualifies = seconds >= 75 && meters >= 482.8 && hrCoverage >= 0.70 && hrr >= 0.65 && avgGrade >= -0.015 && avgPower > 0
        let demand = 10.8 * avgPower / profile.riderKg + 7
        let durationFraction = seconds < 90 ? 0.78 : seconds < 180 ? 0.83 : seconds < 300 ? 0.87 : seconds < 600 ? 0.91 : 0.94
        let hrFraction = min(0.95,max(0.68,hrr))
        let effortFraction = measuredCoverage >= 0.5 ? 0.60*hrFraction + 0.40*durationFraction : 0.72*hrFraction + 0.28*durationFraction
        return Effort(qualifying: qualifies, vo2: min(95,max(0,demand/max(0.68,effortFraction))), speedMph: avgSpeed, miles: meters/1609.344)
    }

    private static func bestAveragePower(_ samples: [RideSample], seconds: TimeInterval) -> Double {
        guard samples.count > 1 else { return 0 }
        var left = 0, weighted = 0.0, time = 0.0, best = 0.0
        for right in 1..<samples.count {
            let dt = min(5,max(0,samples[right].elapsed-samples[right-1].elapsed))
            weighted += Double(samples[right].power)*dt; time += dt
            while left+1 < right && time > seconds {
                let remove = min(5,max(0,samples[left+1].elapsed-samples[left].elapsed))
                weighted -= Double(samples[left+1].power)*remove; time -= remove; left += 1
            }
            if time >= seconds*0.90 { best = max(best,weighted/max(0.1,time)) }
        }
        return best
    }
    private static func duration(_ rows: [RideSample]) -> TimeInterval { guard let a=rows.first,let b=rows.last else{return 0};return b.elapsed-a.elapsed }
    private static func durationFTPFactor(_ seconds: TimeInterval) -> Double { seconds<180 ? 0.70 : seconds<360 ? 0.78 : seconds<720 ? 0.85 : seconds<1200 ? 0.90 : 0.95 }
}
