import Foundation

public struct LicensePurchase: Decodable, Equatable {
    public let productName: String?
    public let createdAt: String?

    enum CodingKeys: String, CodingKey {
        case productName = "product_name"
        case createdAt = "created_at"
    }
}

public struct LicenseVerification: Decodable, Equatable {
    public let success: Bool
    public let uses: Int?
    public let purchase: LicensePurchase?
}

public protocol LicenseVerifying {
    func verify(licenseKey: String) async throws -> LicenseVerification
}

public struct GumroadLicenseClient: LicenseVerifying {
    public static let endpoint = URL(string: "https://api.gumroad.com/v2/licenses/verify")!

    public let productID: String
    public let session: URLSession

    public init(productID: String, session: URLSession = .shared) {
        self.productID = productID
        self.session = session
    }

    public func verify(licenseKey: String) async throws -> LicenseVerification {
        var request = URLRequest(url: Self.endpoint)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        var components = URLComponents()
        components.queryItems = [
            URLQueryItem(name: "product_id", value: productID),
            URLQueryItem(name: "license_key", value: licenseKey)
        ]
        request.httpBody = components.query?.data(using: .utf8)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw URLError(.badServerResponse)
        }
        guard http.statusCode == 200 else {
            throw URLError(URLError.Code(rawValue: http.statusCode))
        }
        return try JSONDecoder().decode(LicenseVerification.self, from: data)
    }
}
