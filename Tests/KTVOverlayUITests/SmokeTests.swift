import KTVOverlayUI
import Testing

@Suite struct SmokeTests {
    @Test func overlayModuleNameIsStable() {
        #expect(OverlayModule.name == "KTVOverlayUI")
    }
}
