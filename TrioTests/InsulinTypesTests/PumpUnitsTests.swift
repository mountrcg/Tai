import Foundation
import Testing

@testable import Trio

@Suite("PumpInsulin / PumpRate wrapper math") struct PumpUnitsTests {
    // The concentration grid we ship for users: U10, U50, U100, U200, U500.
    static let concentrations: [Decimal] = [0.1, 0.5, 1, 2, 5]

    // Representative insulin amounts: zero, smallest pump increments, common boluses, max bolus.
    static let values: [Decimal] = [0, 0.025, 0.05, 0.1, 1.0, 5.5, 25.0]

    // MARK: - PumpInsulin round-trips

    @Test("PumpInsulin: iU → pU → iU is identity across the concentration grid")  func pumpInsulinRoundTripFromIU() {
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

    @Test("PumpInsulin: pU → iU → pU is identity across the concentration grid")  func pumpInsulinRoundTripFromPU() {
        for concentration in Self.concentrations {
            for value in Self.values {
                let pump = PumpInsulin(pU: value)
                let iU = pump.iU(concentration: concentration)
                let backToPump = PumpInsulin(iU: iU, concentration: concentration)
                #expect(
                    backToPump.pU == value,
                    "pU=\(value) c=\(concentration): round-trip yielded \(backToPump.pU)"
                )
            }
        }
    }

    @Test("PumpInsulin at U100: pU and iU agree (identity concentration)")  func pumpInsulinU100IsIdentity() {
        for value in Self.values {
            #expect(PumpInsulin(iU: value, concentration: 1).pU == value)
            #expect(PumpInsulin(pU: value).iU(concentration: 1) == value)
        }
    }

    @Test("PumpInsulin at U200 halves iU into pU exactly")  func pumpInsulinU200Halves() {
        #expect(PumpInsulin(iU: 1.0, concentration: 2).pU == 0.5)
        #expect(PumpInsulin(iU: 0.1, concentration: 2).pU == 0.05)
        #expect(PumpInsulin(iU: 0.05, concentration: 2).pU == 0.025)
        #expect(PumpInsulin(iU: 25.0, concentration: 2).pU == 12.5)
    }

    @Test("PumpInsulin at U500 fifths iU into pU exactly")  func pumpInsulinU500Fifths() {
        #expect(PumpInsulin(iU: 1.0, concentration: 5).pU == 0.2)
        #expect(PumpInsulin(iU: 25.0, concentration: 5).pU == 5.0)
    }

    @Test("PumpInsulin at U50 doubles iU into pU exactly")  func pumpInsulinU50Doubles() {
        #expect(PumpInsulin(iU: 1.0, concentration: 0.5).pU == 2.0)
        #expect(PumpInsulin(iU: 0.05, concentration: 0.5).pU == 0.1)
    }

    @Test("PumpInsulin: zero is identity in both directions at every concentration")  func pumpInsulinZeroIsIdentity() {
        for concentration in Self.concentrations {
            #expect(PumpInsulin(iU: 0, concentration: concentration).pU == 0)
            #expect(PumpInsulin(pU: 0).iU(concentration: concentration) == 0)
        }
    }

    // MARK: - PumpRate round-trips

    @Test("PumpRate: iU/hr → pU/hr → iU/hr is identity")  func pumpRateRoundTripFromIU() {
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

    @Test("PumpRate: pU/hr → iU/hr → pU/hr is identity")  func pumpRateRoundTripFromPU() {
        for concentration in Self.concentrations {
            for value in Self.values {
                let pump = PumpRate(pU: value)
                let iU = pump.iU(concentration: concentration)
                let backToPump = PumpRate(iU: iU, concentration: concentration)
                #expect(
                    backToPump.pU == value,
                    "pU/hr=\(value) c=\(concentration): round-trip yielded \(backToPump.pU)"
                )
            }
        }
    }

    // MARK: - Decimal precision (no float drift)

    @Test("0.05 iU at U200 produces exactly 0.025 pU (no float drift)")  func decimalPrecisionAtIncrementBoundary() {
        #expect(PumpInsulin(iU: 0.05, concentration: 2).pU == Decimal(string: "0.025")!)
    }

    @Test("0.005 pU at U10 produces exactly 0.0005 iU (no float drift)")  func decimalPrecisionForFineConcentration() {
        #expect(PumpInsulin(pU: 0.005).iU(concentration: 0.1) == Decimal(string: "0.0005")!)
    }

    // MARK: - Equatable / Hashable

    @Test("PumpInsulin uses pU for equality and hashing")  func pumpInsulinEquatableAndHashable() {
        let a = PumpInsulin(pU: 0.5)
        let b = PumpInsulin(pU: Decimal(0.5))
        #expect(a == b)
        var set = Set<PumpInsulin>()
        set.insert(a)
        set.insert(b)
        #expect(set.count == 1, "Two PumpInsulin with equal pU must collide in a Set")
    }

    @Test("PumpInsulin and PumpRate are distinct types (compile-time guarantee)")  func wrapperTypesAreDistinct() {
        let insulin = PumpInsulin(pU: 1.0)
        let rate = PumpRate(pU: 1.0)
        #expect(insulin.pU == rate.pU, "underlying pU agrees but types do not")
    }

    // MARK: - Comparable

    @Test("PumpInsulin is ordered by pU")  func pumpInsulinComparable() {
        #expect(PumpInsulin(pU: 0.5) < PumpInsulin(pU: 1.0))
        #expect(min(PumpInsulin(pU: 0.025), PumpInsulin(pU: 0.05)).pU == 0.025)
    }

    // MARK: - Double bridging

    @Test("PumpInsulin.doubleValue bridges to LoopKit's Double API")  func pumpInsulinDoubleBridge() {
        #expect(PumpInsulin(pU: 0.5).doubleValue == 0.5)
        #expect(PumpInsulin(pU: 0).doubleValue == 0)
    }

    @Test("PumpRate.doubleValue bridges to LoopKit's Double API")  func pumpRateDoubleBridge() {
        #expect(PumpRate(pU: 1.25).doubleValue == 1.25)
    }

    // MARK: - Codable

    @Test("PumpInsulin round-trips through JSON Codable")  func pumpInsulinCodable() throws {
        let original = PumpInsulin(pU: Decimal(string: "0.6375")!)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(PumpInsulin.self, from: data)
        #expect(decoded == original)
    }
}
