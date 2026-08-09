import XCTest
@testable import RatTamerCore

final class MockURLProtocol: URLProtocol {
    static var handler: ((URLRequest) throws -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard let handler = Self.handler else {
            client?.urlProtocol(self, didFailWithError: URLError(.unknown))
            return
        }
        do {
            let (response, data) = try handler(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}

    static func bodyData(of request: URLRequest) -> Data {
        if let body = request.httpBody { return body }
        guard let stream = request.httpBodyStream else { return Data() }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let read = stream.read(&buffer, maxLength: buffer.count)
            guard read > 0 else { break }
            data.append(buffer, count: read)
        }
        return data
    }
}

final class LicenseClientTests: XCTestCase {
    private var session: URLSession!

    override func setUp() {
        super.setUp()
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [MockURLProtocol.self]
        session = URLSession(configuration: config)
        MockURLProtocol.handler = nil
    }

    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    func testVerifyPostsFormBodyWithProductIDAndKey() async throws {
        let captured = expectation(description: "request captured")
        MockURLProtocol.handler = { request in
            let body = String(data: MockURLProtocol.bodyData(of: request), encoding: .utf8) ?? ""
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertTrue(body.contains("product_id=rattamer-pro"))
            XCTAssertTrue(body.contains("license_key=KEY-123"))
            captured.fulfill()
            let response = HTTPURLResponse(url: request.url!,
                                           statusCode: 200,
                                           httpVersion: nil,
                                           headerFields: nil)!
            return (response, Data("{\"success\":true,\"uses\":1}".utf8))
        }

        let client = GumroadLicenseClient(productID: "rattamer-pro", session: session)
        let result = try await client.verify(licenseKey: "KEY-123")

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.uses, 1)
        await fulfillment(of: [captured], timeout: 5)
    }

    func testVerifyDecodesPurchase() async throws {
        MockURLProtocol.handler = { request in
            let json = Data("""
            {"success":true,"uses":3,
             "purchase":{"product_name":"RatTamer Pro","created_at":"2026-08-08T00:00:00Z"}}
            """.utf8)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200,
                                           httpVersion: nil, headerFields: nil)!
            return (response, json)
        }

        let client = GumroadLicenseClient(productID: "rattamer-pro", session: session)
        let result = try await client.verify(licenseKey: "KEY-123")

        XCTAssertTrue(result.success)
        XCTAssertEqual(result.purchase?.productName, "RatTamer Pro")
        XCTAssertEqual(result.purchase?.createdAt, "2026-08-08T00:00:00Z")
    }

    func testVerifyThrowsOnNon200() async {
        MockURLProtocol.handler = { request in
            let response = HTTPURLResponse(url: request.url!, statusCode: 429,
                                           httpVersion: nil, headerFields: nil)!
            return (response, Data())
        }

        let client = GumroadLicenseClient(productID: "rattamer-pro", session: session)
        do {
            _ = try await client.verify(licenseKey: "KEY-123")
            XCTFail("expected throw for 429")
        } catch {
            // expected
        }
    }
}
