//
//  Copyright RevenueCat Inc. All Rights Reserved.
//
//  Licensed under the MIT License (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//      https://opensource.org/licenses/MIT
//
//  Result+Extensions.swift
//
//  Created by Nacho Soto on 12/1/21.

extension Result {

    /// Creates a `Result` from either a value or an error.
    /// This is useful for converting from old Objective-C closures to new APIs.
    init( _ value: Success?, _ error: Failure?, file: StaticString = #fileID, line: UInt = #line) {
        if let value = value {
            self = .success(value)
        } else if let error = error {
            self = .failure(error)
        } else {
            fatalError("Unexpected nil value and nil error", file: file, line: line)
        }
    }

    var value: Success? {
        switch self {
        case let .success(value): return value
        case .failure: return nil
        }
    }

    var error: Failure? {
        switch self {
        case .success: return nil
        case let .failure(error): return error
        }
    }

}
