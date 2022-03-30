//
//  Copyright RevenueCat Inc. All Rights Reserved.
//
//  Licensed under the MIT License (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//      https://opensource.org/licenses/MIT
//
//  HTTPResponseBody.swift
//
//  Created by Nacho Soto on 3/30/22.

import Foundation

/// The content of an `HTTPResponse`
/// - Note: this can be removed in favor of `Decodable` when all responses implement `Decodable`.
protocol HTTPResponseBody {

    static func create(with data: Data) throws -> Self

}

/// Default implementation of `HTTPResponseBody` for `Data`
extension Data: HTTPResponseBody {

    static func create(with data: Data) throws -> Data {
        return data
    }

}

/// Default implementation of `HTTPResponseBody` for any `Decodable`
extension Decodable {

    static func create(with data: Data) throws -> Self {
        return try JSONDecoder.default.decode(jsonData: data)
    }

}

/// Default implementation of `HTTPResponseBody` for any `Decodable`
extension Dictionary: HTTPResponseBody where Key == String, Value == Any {

    static func create(with data: Data) throws -> [String: Any] {
        // TODO: throw if wrong type
        return try JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

}

extension Optional: HTTPResponseBody where Wrapped: HTTPResponseBody {

    static func create(with data: Data) throws -> Optional<Wrapped> {
        return try Wrapped.create(with: data)
    }

}
