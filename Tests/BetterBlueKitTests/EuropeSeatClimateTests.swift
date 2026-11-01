//
//  EuropeSeatClimateTests.swift
//  BetterBlueKit
//
//  Europe's ccs2 climate start takes Hyundai's seat codes (0 off, 3-5 cool,
//  6-8 heat, upstream SEAT_STATUS), not the 0-3 levels ClimateOptions holds.
//

import Foundation
import Testing
@testable import BetterBlueKit

@Suite("Europe Seat Climate")
@MainActor
struct EuropeSeatClimateTests {
    private func seats(_ options: ClimateOptions, drvSeatLoc: String = "L") -> [String: Int] {
        let config = APIClientConfiguration(region: .europe, brand: .hyundai, username: "",
                                            password: "", pin: "", accountId: UUID())
        let client = HyundaiEuropeAPIClient(configuration: config)
        let (_, body) = client.commandPathAndBody(for: .startClimate(options), ccs2: true, drvSeatLoc: drvSeatLoc)
        return body["seatClimateInfo"] as? [String: Int] ?? [:]
    }

    @Test func highHeatIsCodeEight() {
        var options = ClimateOptions()
        options.frontLeftSeat = 3
        #expect(seats(options)["drvSeatClimateState"] == 8)
        #expect(seats(options)["psgSeatClimateState"] == 0)
    }

    @Test func lowCoolIsCodeThree() {
        var options = ClimateOptions()
        options.frontRightSeat = 1
        options.frontRightVentilation = true
        #expect(seats(options)["psgSeatClimateState"] == 3)
    }

    @Test func rightHandDriveSwapsTheFrontSeats() {
        var options = ClimateOptions()
        options.frontLeftSeat = 2
        options.frontRightSeat = 3
        options.frontRightVentilation = true
        let body = seats(options, drvSeatLoc: "R")
        #expect(body["drvSeatClimateState"] == 5)   // right seat, high cool
        #expect(body["psgSeatClimateState"] == 7)   // left seat, medium heat
    }

    @Test func allOffStaysZero() {
        let body = seats(ClimateOptions())
        #expect(body.values.allSatisfy { $0 == 0 })
    }
}
