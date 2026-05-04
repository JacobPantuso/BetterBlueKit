//
//  SVMTests.swift
//  BetterBlueKitTests
//
//  Tests for Surround View Monitor data models
//

import Foundation
import Testing
@testable import BetterBlueKit

@Suite("SVM Tests")
struct SVMTests {

    @Test("SVMLocation creation")
    func testSVMLocationCreation() {
        let gpsDetail = SVMGPSDetail(
            coordLat: 34.0,
            coordLon: -118.0,
            coordType: 0,
            head: 90,
            speed: 0,
            speedUnit: 0,
            time: "20251213191601"
        )
        
        let location = SVMLocation(
            gpsDetail: gpsDetail,
            svmImage: "base64EncodedString",
            validAngleofView: [0.0, 90.0],
            boundaryArea: [1, 2, 3]
        )

        #expect(location.gpsDetail?.coordLat == 34.0)
        #expect(location.svmImage == "base64EncodedString")
        #expect(location.validAngleofView?.count == 2)
        #expect(location.boundaryArea?.count == 3)
    }

    @Test("SVMResponse decoding from JSON")
    func testSVMResponseDecoding() throws {
        let jsonString = """
        {
          "responseHeader": {
            "responseCode": 0,
            "responseDesc": "Success"
          },
          "result": {
            "svmLocations": [
              {
                "gpsDetail": {
                  "coordLat": 32.44227222,
                  "coordLon": -56.70162222222223,
                  "coordType": 0,
                  "head": 48,
                  "speed": 0,
                  "speedUnit": 0,
                  "time": "20251213191601"
                },
                "svmImage": "dGVzdGltYWdl",
                "validAngleofView": [
                  0.0,
                  78.0,
                  78.0
                ],
                "boundaryArea": [
                  249
                ]
              }
            ]
          }
        }
        """

        let data = Data(jsonString.utf8)
        let response = try JSONDecoder().decode(SVMResponse.self, from: data)

        // Check Header
        #expect(response.responseHeader?.responseCode == 0)
        #expect(response.responseHeader?.responseDesc == "Success")

        // Check Result
        guard let result = response.result,
              let locations = result.svmLocations,
              let firstLocation = locations.first else {
            #expect(Bool(false), "Result or locations missing")
            return
        }

        #expect(locations.count == 1)
        
        // Check GPS Detail
        #expect(firstLocation.gpsDetail?.coordLat == 32.44227222,)
        #expect(firstLocation.gpsDetail?.coordLon == -56.70162222222223)
        #expect(firstLocation.gpsDetail?.time == "20251213191601")

        // Check Image
        #expect(firstLocation.svmImage == "dGVzdGltYWdl")

        // Check Arrays
        #expect(firstLocation.validAngleofView?.count == 3)
        #expect(firstLocation.boundaryArea?.first == 249)
    }
}
