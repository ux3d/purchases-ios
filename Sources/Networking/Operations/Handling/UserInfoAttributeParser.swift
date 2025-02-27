//
//  Copyright RevenueCat Inc. All Rights Reserved.
//
//  Licensed under the MIT License (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//      https://opensource.org/licenses/MIT
//
//  UserInfoAttributeParser.swift
//
//  Created by Joshua Liebowitz on 11/19/21.

import Foundation

class UserInfoAttributeParser {

    func attributesUserInfoFromResponse(response: [String: Any], statusCode: HTTPStatusCode) -> [String: Any] {
        var resultDict: [String: Any] = [:]
        let isServerError = statusCode.isServerError
        let isNotFoundError = statusCode == .notFoundError

        let successfullySynced = !(isServerError || isNotFoundError)
        resultDict[Backend.RCSuccessfullySyncedKey as String] = successfullySynced

        let hasAttributesResponseContainerKey = (response[Backend.RCAttributeErrorsResponseKey] != nil)
        let attributesResponseDict = hasAttributesResponseContainerKey
        ? response[Backend.RCAttributeErrorsResponseKey]
        : response

        if let attributesResponseDict = attributesResponseDict as? [String: Any],
           let attributesErrors = attributesResponseDict[Backend.RCAttributeErrorsKey] {
            resultDict[Backend.RCAttributeErrorsKey] = attributesErrors
        }

        return resultDict
    }

}
