//
//  EuropeCCIFingerprintTests.swift
//  BetterBlueKit
//
//  X-Fingerprint signing for the EU CCI auth endpoints, pinned against the
//  vectors hyundai_kia_connect_api verified live on 2026-10-14
//  (tests/eu_cci_fingerprint_test.py at 57dbe6f5): an empty-body exchange
//  that answered 200 with exactly this timestamp and signature.
//

import Foundation
import Testing
@testable import BetterBlueKit

@Suite("Europe CCI Fingerprint")
struct EuropeCCIFingerprintTests {

    private func identity(_ config: EuropeCCIConfig, timestamp: String) -> [String: String] {
        [
            "client-id": config.packageId,
            "client-name": config.signedClientName,
            "client-version": "1.4.0",
            "client-os-code": "android",
            "client-os-version": "14",
            "X-Timestamp": timestamp
        ]
    }

    @Test("Kia signature matches the pinned live vector")
    func testKiaVector() {
        let config = EuropeCCIConfig.kia
        #expect(EuropeCCIFingerprint.signature(
            headers: identity(config, timestamp: "1700000000123"), keyPieces: config.fingerprintKey
        ) == "0a3ceccc83823ec0d2c5d39a15dbf722c813e6da48800a0156a7a8459db63337")
    }

    @Test("Hyundai signature matches the pinned live vector")
    func testHyundaiVector() {
        let config = EuropeCCIConfig.hyundai
        #expect(EuropeCCIFingerprint.signature(
            headers: identity(config, timestamp: "1792000084084"), keyPieces: config.fingerprintKey
        ) == "df04e3dadd52288ce5b280b368af261272556b5360adbc90a817a167526e2946")
    }

    @Test("ASCII whitespace in the body is ignored, other whitespace is not")
    func testWhitespace() {
        let config = EuropeCCIConfig.kia
        let headers = identity(config, timestamp: "1700000000123")
        let bare = EuropeCCIFingerprint.signature(headers: headers, keyPieces: config.fingerprintKey)
        #expect(EuropeCCIFingerprint.signature(
            headers: headers, keyPieces: config.fingerprintKey, body: " \t\r\n") == bare)
        #expect(EuropeCCIFingerprint.signature(
            headers: headers, keyPieces: config.fingerprintKey, body: "\u{00A0}") != bare)
        #expect(EuropeCCIFingerprint.signature(
            headers: headers, keyPieces: config.fingerprintKey, body: "{\"a\":1}") != bare)
    }

    @Test("Built headers carry the signed identity and a valid signature")
    func testHeaders() {
        let config = EuropeCCIConfig.hyundai
        let headers = EuropeCCIFingerprint.headers(
            config: config, deviceId: "dev-1", timezone: "+02:00",
            now: Date(timeIntervalSince1970: 1_792_000_084.084)
        )
        #expect(headers["client-name"] == "HyundaiEU")
        #expect(headers["client-os-code"] == "android")
        #expect(headers["User-Agent"] == "okhttp/4.12.0")
        #expect(headers["X-Brand"] == "Hyundai")
        #expect(headers["X-Region"] == "eu")
        #expect(headers["X-Timestamp"] == "1792000084084")
        #expect(headers["X-Fingerprint"] == "df04e3dadd52288ce5b280b368af261272556b5360adbc90a817a167526e2946")
        #expect(headers["App-Request-Id"]?.hasSuffix("_dev1_AOS") == true)
    }

    @Test("Only the gate's own codes count as a gate rejection")
    func testGateRejection() {
        func error(_ status: Int, _ body: String) -> APIError {
            APIError(message: "x", code: status, userInfo: ["responseBody": body])
        }
        for code in [9035, 9036, 9037] {
            #expect(EuropeCCIFingerprint.gateRejection(in: error(400, "{\"code\":\(code),\"message\":\"x\"}")) == code)
        }
        #expect(EuropeCCIFingerprint.gateRejection(in: error(400, "{\"code\":9013}")) == nil)
        #expect(EuropeCCIFingerprint.gateRejection(in: error(500, "{\"code\":9035}")) == nil)
        #expect(EuropeCCIFingerprint.gateRejection(in: error(502, "<html>")) == nil)
    }
}
