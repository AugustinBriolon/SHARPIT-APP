import Foundation
import Testing
@testable import Sharpit

@Test func heartRateMeasurementParsesUint8Bpm() {
    // flags=0 (UINT8), bpm=142
    let data = Data([0x00, 142])
    #expect(HeartRateMeasurement.parseBpm(data) == 142)
}

@Test func heartRateMeasurementParsesUint16Bpm() {
    // flags=1 (UINT16 LE), bpm=260
    let data = Data([0x01, 0x04, 0x01])
    #expect(HeartRateMeasurement.parseBpm(data) == 260)
}

@Test func heartRateMeasurementRejectsTruncatedPayload() {
    #expect(HeartRateMeasurement.parseBpm(Data()) == nil)
    #expect(HeartRateMeasurement.parseBpm(Data([0x00])) == nil)
    #expect(HeartRateMeasurement.parseBpm(Data([0x01, 0x04])) == nil)
}
