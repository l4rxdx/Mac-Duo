import XCTest
@testable import MacDuo

final class DepthRendererTests: XCTestCase {
    @MainActor
    func testPackageShaderBuildsMetalPipeline() {
        XCTAssertNotNil(DepthRenderer())
    }
}
