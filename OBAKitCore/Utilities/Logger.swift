//
//  Logger.swift
//  OBAKitCore
//
//  Created by Aaron Brethorst on 7/15/20.
//

import Foundation
import CocoaLumberjackSwift

@objc(OBALogger) public class Logger: NSObject {

    static let shared = Logger()

    override init() {
        super.init()

        DDLog.add(DDOSLogger.sharedInstance, with: .info)

        let fileLogger: DDFileLogger = DDFileLogger()
        fileLogger.rollingFrequency = 60 * 60 * 24 // 24 hours
        fileLogger.logFileManager.maximumNumberOfLogFiles = 7 // 1 week.
        DDLog.add(fileLogger, with: .info)
    }

    // MARK: - Info

    @objc public class func info(_ message: String) {
        shared.info(message)
    }

    func info(_ message: String) {
        DDLogInfo(message)
    }

    // MARK: - Warn

    @objc public class func warn(_ message: String) {
        shared.warn(message)
    }

    func warn(_ message: String) {
        DDLogWarn(message)
    }

    // MARK: - Error

    @objc public class func error(_ message: String) {
        shared.error(message)
    }

    func error(_ message: String) {
        DDLogError(message)
    }
}
