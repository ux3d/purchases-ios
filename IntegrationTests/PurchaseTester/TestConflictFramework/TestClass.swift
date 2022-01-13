//
//  TestClass.swift
//  TestConflictFramework
//
//  Created by Andrés Boedo on 1/13/22.
//  Copyright © 2022 RevenueCat. All rights reserved.
//

import Foundation

public extension NSDate {

    @objc func foo() -> String {
        return "This is the method from the conflict framework"
    }

}

@objc public class TestClass: NSObject {
    
    @objc public func testFoo() -> String {
        return NSDate().foo()
    }
}
