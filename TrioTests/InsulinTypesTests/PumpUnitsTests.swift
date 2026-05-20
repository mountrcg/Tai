import Foundation
import Testing

@testable import Trio

@Suite("PumpUnits wrapper math") struct PumpUnitsTests {
    // The concentration grid we ship for users: U10, U50, U100, U200, U500.
    static let concentrations: [Decimal] = [0.1, 0.5, 1, 2, 5]

    // Representative insulin amounts: zero, smallest pump increments, common boluses, max bolus.
    static let volumes: [Decimal] = [0, 0.025, 0.05, 0.1, 1.0, 5.5, 25.0]

    // MARK: - AlgorithmInsulin / PumpInsulin round-trips

    @Test("iU → cU → iU is identity across the concentration grid") func insulinRoundTripFromAlgorithm() {
        for concentration in Self.concentrations {
            for value in Self.volumes {
                let start = AlgorithmInsulin(iU: value)
                let pump = start.cU(concentration: concentration)
                let backToAlgorithm = pump.iU(concentration: concentration)
                #expect(
                    backToAlgorithm == start,
                    "iU \(value) at concentration \(concentration) failed round-trip: got \(backToAlgorithm.iU)"
                )
            }
        }
    }

    @Test("cU → iU → cU is identity across the concentration grid") func insulinRoundTripFromPump() {
        for concentration in Self.concentrations {
            for value in Self.volumes {
                let start = PumpInsulin(cU: value)
                let algorithm = start.iU(concentration: concentration)
                let backToPump = algorithm.cU(concentration: concentration)
                #expect(
                    backToPump == start,
                    "cU \(value) at concentration \(concentration) failed round-trip: got \(backToPump.cU)"
                )
            }
        }
    }

    @Test("U100 is the identity concentration") func insulinU100IsIdentity() {
        for value in Self.volumes {
            let algorithm = AlgorithmInsulin(iU: value)
            #expect(algorithm.cU(concentration: 1).cU == value)
            let pump = PumpInsulin(cU: value)
            #expect(pump.iU(concentration: 1).iU == value)
        }
    }

    @Test("U200 halves iU into cU exactly") func insulinU200Halves() {
        #expect(AlgorithmInsulin(iU: 1.0).cU(concentration: 2).cU == 0.5)
        #expect(AlgorithmInsulin(iU: 0.1).cU(concentration: 2).cU == 0.05)
        #expect(AlgorithmInsulin(iU: 0.05).cU(concentration: 2).cU == 0.025)
        #expect(AlgorithmInsulin(iU: 25.0).cU(concentration: 2).cU == 12.5)
    }

    @Test("U500 fifths iU into cU exactly") func insulinU500Fifths() {
        #expect(AlgorithmInsulin(iU: 1.0).cU(concentration: 5).cU == 0.2)
        #expect(AlgorithmInsulin(iU: 25.0).cU(concentration: 5).cU == 5.0)
    }

    @Test("U50 doubles iU into cU exactly") func insulinU50Doubles() {
        #expect(AlgorithmInsulin(iU: 1.0).cU(concentration: 0.5).cU == 2.0)
        #expect(AlgorithmInsulin(iU: 0.05).cU(concentration: 0.5).cU == 0.1)
    }

    @Test("Zero is identity in both directions at every concentration") func insulinZeroIsIdentity() {
        for concentration in Self.concentrations {
            #expect(AlgorithmInsulin(iU: 0).cU(concentration: concentration).cU == 0)
            #expect(PumpInsulin(cU: 0).iU(concentration: concentration).iU == 0)
        }
    }

    // MARK: - AlgorithmBasalRate / PumpBasalRate round-trips

    @Test("Basal rate iU/hr → cU/hr → iU/hr is identity") func basalRateRoundTripFromAlgorithm() {
        for concentration in Self.concentrations {
            for value in Self.volumes {
                let start = AlgorithmBasalRate(iU: value)
                let pump = start.cU(concentration: concentration)
                let back = pump.iU(concentration: concentration)
                #expect(
                    back == start,
                    "rate \(value)/hr at concentration \(concentration) failed round-trip: got \(back.iU)"
                )
            }
        }
    }

    @Test("Basal rate cU/hr → iU/hr → cU/hr is identity") func basalRateRoundTripFromPump() {
        for concentration in Self.concentrations {
            for value in Self.volumes {
                let start = PumpBasalRate(cU: value)
                let algorithm = start.iU(concentration: concentration)
                let back = algorithm.cU(concentration: concentration)
                #expect(
                    back == start,
                    "cU rate \(value)/hr at concentration \(concentration) failed round-trip: got \(back.cU)"
                )
            }
        }
    }

    // MARK: - Decimal precision (no float drift)

    @Test("0.05 iU at U200 produces exactly 0.025 cU (no float drift)") func decimalPrecisionAtIncrementBoundary() {
        let pump = AlgorithmInsulin(iU: 0.05).cU(concentration: 2)
        #expect(pump.cU == Decimal(string: "0.025")!)
    }

    @Test("0.005 cU at U10 produces exactly 0.0005 iU (no float drift)") func decimalPrecisionForFineConcentration() {
        let algorithm = PumpInsulin(cU: 0.005).iU(concentration: 0.1)
        #expect(algorithm.iU == Decimal(string: "0.0005")!)
    }

    // MARK: - Equatable / Hashable

    @Test("AlgorithmInsulin uses iU for equality and hashing") func insulinEquatableAndHashable() {
        let a = AlgorithmInsulin(iU: 1.0)
        let b = AlgorithmInsulin(iU: Decimal(1.0))
        #expect(a == b)
        var set = Set<AlgorithmInsulin>()
        set.insert(a)
        set.insert(b)
        #expect(set.count == 1, "Two AlgorithmInsulin with equal iU must collide in a Set")
    }

    @Test("PumpInsulin and AlgorithmInsulin are distinct types (compile-time guarantee)") func insulinTypesAreDistinct() {
        let algorithm = AlgorithmInsulin(iU: 1.0)
        let pump = PumpInsulin(cU: 1.0)
        #expect(algorithm.iU == pump.cU)
    }

    // MARK: - Comparable

    @Test("AlgorithmInsulin is ordered by iU") func insulinComparable() {
        #expect(AlgorithmInsulin(iU: 0.5) < AlgorithmInsulin(iU: 1.0))
        #expect(AlgorithmInsulin(iU: 1.0) > AlgorithmInsulin(iU: 0.5))
        let sorted = [AlgorithmInsulin(iU: 2), AlgorithmInsulin(iU: 0), AlgorithmInsulin(iU: 1)].sorted()
        #expect(sorted.map(\.iU) == [0, 1, 2])
    }

    @Test("PumpInsulin is ordered by cU") func pumpInsulinComparable() {
        #expect(PumpInsulin(cU: 0.5) < PumpInsulin(cU: 1.0))
        #expect(min(PumpInsulin(cU: 0.025), PumpInsulin(cU: 0.05)).cU == 0.025)
    }

    // MARK: - Same-domain arithmetic

    @Test("AlgorithmInsulin supports same-domain addition and subtraction") func insulinArithmetic() {
        let total = AlgorithmInsulin(iU: 1.0) + AlgorithmInsulin(iU: 0.5)
        #expect(total.iU == Decimal(string: "1.5")!)
        let remainder = AlgorithmInsulin(iU: 1.0) - AlgorithmInsulin(iU: 0.4)
        #expect(remainder.iU == Decimal(string: "0.6")!)
    }

    @Test("AlgorithmBasalRate supports same-domain addition and subtraction") func basalRateArithmetic() {
        let total = AlgorithmBasalRate(iU: 1.0) + AlgorithmBasalRate(iU: 0.25)
        #expect(total.iU == Decimal(string: "1.25")!)
    }

    // MARK: - Double bridging

    @Test("PumpInsulin doubleValue bridges to LoopKit's Double API") func pumpInsulinDoubleBridge() {
        #expect(PumpInsulin(cU: 0.5).doubleValue == 0.5)
        #expect(PumpInsulin(cU: 0).doubleValue == 0)
    }

    // MARK: - Codable

    @Test("AlgorithmInsulin round-trips through JSON Codable") func insulinCodable() throws {
        let original = AlgorithmInsulin(iU: Decimal(string: "1.275")!)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(AlgorithmInsulin.self, from: data)
        #expect(decoded == original)
    }

    @Test("PumpInsulin round-trips through JSON Codable") func pumpInsulinCodable() throws {
        let original = PumpInsulin(cU: Decimal(string: "0.6375")!)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PumpInsulin.self, from: data)
        #expect(decoded == original)
    }
}
