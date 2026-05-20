import Foundation
import Testing

@testable import Trio

@Suite("PumpInsulin / PumpRate wrapper math") struct PumpUnitsTests {
    // The concentration grid we ship for users: U10, U50, U100, U200, U500.
    static let concentrations: [Decimal] = [0.1, 0.5, 1, 2, 5]

    // Representative insulin amounts: zero, smallest pump increments, common boluses, max bolus.
    static let values: [Decimal] = [0, 0.025, 0.05, 0.1, 1.0, 5.5, 25.0]

    // MARK: - PumpInsulin round-trips

    @Test("PumpInsulin: iU → cU → iU is identity across the concentration grid")  func pumpInsulinRoundTripFromIU() {
        for concentration in Self.concentrations {
            for value in Self.values {
                let pump = PumpInsulin(iU: value, concentration: concentration)
                let backToIU = pump.iU(concentration: concentration)
                #expect(
                    backToIU == value,
                    "iU=\(value) c=\(concentration): round-trip yielded \(backToIU)"
                )
            }
        }
    }

    @Test("PumpInsulin: cU → iU → cU is identity across the concentration grid")  func pumpInsulinRoundTripFromCU() {
        for concentration in Self.concentrations {
            for value in Self.values {
                let pump = PumpInsulin(cU: value)
                let iU = pump.iU(concentration: concentration)
                let backToPump = PumpInsulin(iU: iU, concentration: concentration)
                #expect(
                    backToPump.cU == value,
                    "cU=\(value) c=\(concentration): round-trip yielded \(backToPump.cU)"
                )
            }
        }
    }

    @Test("PumpInsulin at U100: cU and iU agree (identity concentration)")  func pumpInsulinU100IsIdentity() {
        for value in Self.values {
            #expect(PumpInsulin(iU: value, concentration: 1).cU == value)
            #expect(PumpInsulin(cU: value).iU(concentration: 1) == value)
        }
    }

    @Test("PumpInsulin at U200 halves iU into cU exactly")  func pumpInsulinU200Halves() {
        #expect(PumpInsulin(iU: 1.0, concentration: 2).cU == 0.5)
        #expect(PumpInsulin(iU: 0.1, concentration: 2).cU == 0.05)
        #expect(PumpInsulin(iU: 0.05, concentration: 2).cU == 0.025)
        #expect(PumpInsulin(iU: 25.0, concentration: 2).cU == 12.5)
    }

    @Test("PumpInsulin at U500 fifths iU into cU exactly")  func pumpInsulinU500Fifths() {
        #expect(PumpInsulin(iU: 1.0, concentration: 5).cU == 0.2)
        #expect(PumpInsulin(iU: 25.0, concentration: 5).cU == 5.0)
    }

    @Test("PumpInsulin at U50 doubles iU into cU exactly")  func pumpInsulinU50Doubles() {
        #expect(PumpInsulin(iU: 1.0, concentration: 0.5).cU == 2.0)
        #expect(PumpInsulin(iU: 0.05, concentration: 0.5).cU == 0.1)
    }

    @Test("PumpInsulin: zero is identity in both directions at every concentration")  func pumpInsulinZeroIsIdentity() {
        for concentration in Self.concentrations {
            #expect(PumpInsulin(iU: 0, concentration: concentration).cU == 0)
            #expect(PumpInsulin(cU: 0).iU(concentration: concentration) == 0)
        }
    }

    // MARK: - PumpRate round-trips

    @Test("PumpRate: iU/hr → cU/hr → iU/hr is identity")  func pumpRateRoundTripFromIU() {
        for concentration in Self.concentrations {
            for value in Self.values {
                let pump = PumpRate(iU: value, concentration: concentration)
                let backToIU = pump.iU(concentration: concentration)
                #expect(
                    backToIU == value,
                    "iU/hr=\(value) c=\(concentration): round-trip yielded \(backToIU)"
                )
            }
        }
    }

    @Test("PumpRate: cU/hr → iU/hr → cU/hr is identity")  func pumpRateRoundTripFromCU() {
        for concentration in Self.concentrations {
            for value in Self.values {
                let pump = PumpRate(cU: value)
                let iU = pump.iU(concentration: concentration)
                let backToPump = PumpRate(iU: iU, concentration: concentration)
                #expect(
                    backToPump.cU == value,
                    "cU/hr=\(value) c=\(concentration): round-trip yielded \(backToPump.cU)"
                )
            }
        }
    }

    // MARK: - Decimal precision (no float drift)

    @Test("0.05 iU at U200 produces exactly 0.025 cU (no float drift)")  func decimalPrecisionAtIncrementBoundary() {
        #expect(PumpInsulin(iU: 0.05, concentration: 2).cU == Decimal(string: "0.025")!)
    }

    @Test("0.005 cU at U10 produces exactly 0.0005 iU (no float drift)")  func decimalPrecisionForFineConcentration() {
        #expect(PumpInsulin(cU: 0.005).iU(concentration: 0.1) == Decimal(string: "0.0005")!)
    }

    // MARK: - Equatable / Hashable

    @Test("PumpInsulin uses cU for equality and hashing")  func pumpInsulinEquatableAndHashable() {
        let a = PumpInsulin(cU: 0.5)
        let b = PumpInsulin(cU: Decimal(0.5))
        #expect(a == b)
        var set = Set<PumpInsulin>()
        set.insert(a)
        set.insert(b)
        #expect(set.count == 1, "Two PumpInsulin with equal cU must collide in a Set")
    }

    @Test("PumpInsulin and PumpRate are distinct types (compile-time guarantee)")  func wrapperTypesAreDistinct() {
        let insulin = PumpInsulin(cU: 1.0)
        let rate = PumpRate(cU: 1.0)
        #expect(insulin.cU == rate.cU, "underlying cU agrees but types do not")
    }

    // MARK: - Comparable

    @Test("PumpInsulin is ordered by cU")  func pumpInsulinComparable() {
        #expect(PumpInsulin(cU: 0.5) < PumpInsulin(cU: 1.0))
        #expect(min(PumpInsulin(cU: 0.025), PumpInsulin(cU: 0.05)).cU == 0.025)
    }

    // MARK: - Double bridging

    @Test("PumpInsulin.doubleValue bridges to LoopKit's Double API")  func pumpInsulinDoubleBridge() {
        #expect(PumpInsulin(cU: 0.5).doubleValue == 0.5)
        #expect(PumpInsulin(cU: 0).doubleValue == 0)
    }

    @Test("PumpRate.doubleValue bridges to LoopKit's Double API")  func pumpRateDoubleBridge() {
        #expect(PumpRate(cU: 1.25).doubleValue == 1.25)
    }

    // MARK: - Codable

    @Test("PumpInsulin round-trips through JSON Codable")  func pumpInsulinCodable() throws {
        let original = PumpInsulin(cU: Decimal(string: "0.6375")!)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PumpInsulin.self, from: data)
        #expect(decoded == original)
    }
}
