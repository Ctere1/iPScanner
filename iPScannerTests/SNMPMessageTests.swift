import XCTest
@testable import iPScanner

/// Hand-rolled BER, so the encoding is pinned to bytes rather than to "it seemed to work against
/// my router". The request is deterministic given a request id, which is why the id is a parameter.
final class SNMPMessageTests: XCTestCase {

    // MARK: - Encoding

    func testGetRequestIsWellFormedBER() {
        let data = SNMPMessage.get(oids: [SNMPMessage.sysDescr], community: "public", requestID: 1)
        let bytes = Array(data)

        XCTAssertEqual(bytes[0], 0x30, "a message is a SEQUENCE")
        XCTAssertEqual(Int(bytes[1]), bytes.count - 2, "declared length matches the real one")
        // version INTEGER 1 == SNMPv2c
        XCTAssertEqual(Array(bytes[2...4]), [0x02, 0x01, 0x01])
        // community OCTET STRING "public"
        XCTAssertEqual(Array(bytes[5...7]), [0x04, 0x06, 0x70])
        XCTAssertTrue(data.range(of: Data("public".utf8)) != nil)
        XCTAssertTrue(bytes.contains(0xA0), "GetRequest PDU tag")
    }

    /// 1.3.6.1.2.1.1.1.0 → the first two arcs pack into one byte (40*1+3 = 43 = 0x2B), and the rest
    /// are base-128. This is the part of BER that is easy to get quietly wrong.
    func testEncodesTheSysDescrOID() {
        let data = SNMPMessage.get(oids: [SNMPMessage.sysDescr], community: "public", requestID: 1)
        let expected = Data([0x06, 0x08, 0x2B, 0x06, 0x01, 0x02, 0x01, 0x01, 0x01, 0x00])
        XCTAssertNotNil(data.range(of: expected), "sysDescr OID must encode to 2B 06 01 02 01 01 01 00")
    }

    func testEncodingIsDeterministicForAGivenRequestID() {
        let first = SNMPMessage.get(oids: SNMPMessage.defaultOIDs, community: "public", requestID: 42)
        let second = SNMPMessage.get(oids: SNMPMessage.defaultOIDs, community: "public", requestID: 42)
        XCTAssertEqual(first, second)
    }

    func testRequestIDIsCarriedInThePDU() {
        let data = SNMPMessage.get(oids: [SNMPMessage.sysDescr], requestID: 0x1234)
        XCTAssertNotNil(data.range(of: Data([0x02, 0x02, 0x12, 0x34])), "request-id INTEGER 0x1234")
    }

    func testCommunityIsHonoured() {
        let data = SNMPMessage.get(oids: [SNMPMessage.sysDescr], community: "private", requestID: 1)
        XCTAssertNotNil(data.range(of: Data("private".utf8)))
        XCTAssertNil(data.range(of: Data("public".utf8)))
    }

    func testAskingForSeveralOIDsProducesSeveralBindings() {
        let data = SNMPMessage.get(oids: SNMPMessage.defaultOIDs, requestID: 1)
        // The three system OIDs differ only in their last-but-one arc: .1 descr, .2 objectID,
        // .5 name. Asserting on each full encoding is what catches an off-by-one there.
        let encodings: [String: Data] = [
            SNMPMessage.sysDescr: Data([0x06, 0x08, 0x2B, 0x06, 0x01, 0x02, 0x01, 0x01, 0x01, 0x00]),
            SNMPMessage.sysObjectID: Data([0x06, 0x08, 0x2B, 0x06, 0x01, 0x02, 0x01, 0x01, 0x02, 0x00]),
            SNMPMessage.sysName: Data([0x06, 0x08, 0x2B, 0x06, 0x01, 0x02, 0x01, 0x01, 0x05, 0x00])
        ]
        for (oid, encoded) in encodings {
            XCTAssertNotNil(data.range(of: encoded), "missing binding for \(oid)")
        }
    }

    // MARK: - Decoding

    /// A GetResponse for sysDescr = "Test Router", hand-assembled.
    private func response(descr: String, requestID: UInt8 = 1, errorStatus: UInt8 = 0) -> Data {
        let value = Array(descr.utf8)
        let oid: [UInt8] = [0x06, 0x08, 0x2B, 0x06, 0x01, 0x02, 0x01, 0x01, 0x01, 0x00]
        let valueTLV: [UInt8] = [0x04, UInt8(value.count)] + value
        let binding: [UInt8] = [0x30, UInt8(oid.count + valueTLV.count)] + oid + valueTLV
        let bindings: [UInt8] = [0x30, UInt8(binding.count)] + binding
        let pduBody: [UInt8] = [0x02, 0x01, requestID, 0x02, 0x01, errorStatus, 0x02, 0x01, 0x00] + bindings
        let pdu: [UInt8] = [0xA2, UInt8(pduBody.count)] + pduBody
        let community: [UInt8] = [0x04, 0x06] + Array("public".utf8)
        let body: [UInt8] = [0x02, 0x01, 0x01] + community + pdu
        return Data([0x30, UInt8(body.count)] + body)
    }

    func testParsesASysDescrResponse() {
        let values = SNMPMessage.parseResponse(response(descr: "Test Router v1"))
        XCTAssertEqual(values?[SNMPMessage.sysDescr], .octetString("Test Router v1"))
    }

    /// The string a network printer actually returns.
    func testParsesAPrinterSysDescr() {
        let result = SNMPMessage.result(from: response(descr: "HP ETHERNET MULTI-ENVIRONMENT"))
        XCTAssertEqual(result?.sysDescr, "HP ETHERNET MULTI-ENVIRONMENT")
    }

    /// A non-zero error-status means the agent refused. Reporting the half-filled bindings that
    /// come with it would be reporting a failure as data.
    func testErrorStatusYieldsNil() {
        XCTAssertNil(SNMPMessage.parseResponse(response(descr: "ignored", errorStatus: 2)))
    }

    func testTruncatedResponseIsNil() {
        let full = response(descr: "Test Router")
        XCTAssertNil(SNMPMessage.parseResponse(full.prefix(full.count / 2)))
        XCTAssertNil(SNMPMessage.parseResponse(Data([0x30])))
        XCTAssertNil(SNMPMessage.parseResponse(Data()))
    }

    func testGarbageIsNil() {
        XCTAssertNil(SNMPMessage.parseResponse(Data([0xFF, 0xEE, 0xDD, 0xCC])))
    }

    /// A request is not a response; the PDU tag must be checked.
    func testAGetRequestIsNotAValidResponse() {
        let request = SNMPMessage.get(oids: [SNMPMessage.sysDescr], requestID: 1)
        XCTAssertNil(SNMPMessage.parseResponse(request))
    }

    /// Long-form lengths: anything past 127 bytes encodes its length across several bytes, and a
    /// real sysDescr routinely is.
    func testHandlesLongFormLengths() {
        let long = String(repeating: "A", count: 300)
        let data = SNMPMessage.get(oids: [SNMPMessage.sysDescr], community: long, requestID: 1)
        XCTAssertEqual(Array(data)[0], 0x30)
        XCTAssertEqual(Array(data)[1] & 0x80, 0x80, "long form sets the high bit of the length byte")
        XCTAssertNotNil(data.range(of: Data(long.utf8)))
    }

    func testRoundTripsALongSysDescr() {
        // 200 chars forces long-form length handling on the decode side too.
        let descr = String(repeating: "Linux nas 5.10 ", count: 14)
        let value = Array(descr.utf8)
        let oid: [UInt8] = [0x06, 0x08, 0x2B, 0x06, 0x01, 0x02, 0x01, 0x01, 0x01, 0x00]
        let valueTLV: [UInt8] = [0x04, 0x81, UInt8(value.count)] + value
        let binding: [UInt8] = [0x30, 0x81, UInt8(oid.count + valueTLV.count)] + oid + valueTLV
        let bindings: [UInt8] = [0x30, 0x81, UInt8(binding.count)] + binding
        let pduBody: [UInt8] = [0x02, 0x01, 0x01, 0x02, 0x01, 0x00, 0x02, 0x01, 0x00] + bindings
        let pdu: [UInt8] = [0xA2, 0x82, UInt8(pduBody.count >> 8), UInt8(pduBody.count & 0xFF)] + pduBody
        let community: [UInt8] = [0x04, 0x06] + Array("public".utf8)
        let body: [UInt8] = [0x02, 0x01, 0x01] + community + pdu
        let message = Data([0x30, 0x82, UInt8(body.count >> 8), UInt8(body.count & 0xFF)] + body)

        XCTAssertEqual(SNMPMessage.result(from: message)?.sysDescr, descr)
    }
}
