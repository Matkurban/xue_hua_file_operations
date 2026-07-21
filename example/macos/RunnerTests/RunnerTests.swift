import Cocoa
import FlutterMacOS
import XCTest

@testable import xue_hua_file_operations

class RunnerTests: XCTestCase {

  func testUnknownMethodReturnsNotImplemented() {
    let plugin = XueHuaFileOperationsPlugin()

    let call = FlutterMethodCall(methodName: "getPlatformVersion", arguments: [])

    let resultExpectation = expectation(description: "result block must be called.")
    plugin.handle(call) { result in
      XCTAssertTrue((result as AnyObject?) === (FlutterMethodNotImplemented as AnyObject?))
      resultExpectation.fulfill()
    }
    waitForExpectations(timeout: 1)
  }

  func testOpenFileRequiresPathOrIdentifier() {
    let plugin = XueHuaFileOperationsPlugin()

    let call = FlutterMethodCall(methodName: "openFile", arguments: [:])

    let resultExpectation = expectation(description: "result block must be called.")
    plugin.handle(call) { result in
      let error = result as? FlutterError
      XCTAssertEqual(error?.code, "invalid_args")
      resultExpectation.fulfill()
    }
    waitForExpectations(timeout: 1)
  }

}
