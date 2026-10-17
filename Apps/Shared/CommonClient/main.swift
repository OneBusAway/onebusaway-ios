//
//  main.swift
//  App
//
//  Copyright © Open Transit Software Foundation
//  This source code is licensed under the Apache 2.0 license found in the
//  LICENSE file in the root directory of this source tree.
//

import UIKit

/// The app delegate a unit-test host launches with. It builds no application
/// stack, so hosted tests start from a quiet process; `SceneDelegate` sees that
/// the delegate is not an `AppDelegate` and leaves the window empty.
final class TestAppDelegate: UIResponder, UIApplicationDelegate {}

#if DEBUG
print("Bundle Path: \(Bundle.main.bundlePath)")
#endif

private let environment = ProcessInfo.processInfo.environment
private let executingTests = (environment["XCInjectBundle"].map { URL(fileURLWithPath: $0).pathExtension } == "xctest")
    || environment["XCInjectBundleInto"] != nil

private let appDelegateClass: AnyClass = executingTests ? TestAppDelegate.self : AppDelegate.self

_ = UIApplicationMain(CommandLine.argc, CommandLine.unsafeArgv, nil, NSStringFromClass(appDelegateClass))
