import Foundation
import Testing
@testable import AirMouseCore

@Suite struct OnboardingTests {
    @Test func pagesNextBackFinish() {
        var f = OnboardingFlow()
        #expect(f.current == .welcome && !f.canGoBack)
        f.back(); #expect(f.index == 0)
        f.next(); #expect(f.current == .howItWorks && f.canGoBack)
        f.back(); #expect(f.current == .welcome)
        f.next(); f.next(); #expect(f.current == .getIPhone)
        f.next(); #expect(f.current == .permissions && f.isLastPage && f.pageNumber == 4)
        f.next(); #expect(f.isFinished && f.current == nil && !f.canGoBack)
        f.next(); f.back(); #expect(f.isFinished)
    }

    @Test func tourOrderNextSkip() {
        var t = TourFlow()
        #expect(t.steps == [.statusCard, .pairRow, .calibrate, .centerCursor, .permissionsRow, .menuBar])
        #expect(t.current == .statusCard && t.stepNumber == 1 && t.total == 6)
        for _ in 0..<5 { t.next() }
        #expect(t.current == .menuBar && t.isLastStep && !TourTarget.menuBar.hasTarget)
        t.next(); #expect(t.isFinished && !t.wasSkipped)
        var s = TourFlow(); s.next(); s.skip()
        #expect(s.isFinished && s.wasSkipped && s.current == nil)
    }

    @Test func persistedFlags() throws {
        let suite = "airmouse.tests.\(UUID().uuidString)"
        let d = try #require(UserDefaults(suiteName: suite))
        defer { d.removePersistentDomain(forName: suite) }
        let store = OnboardingStore(defaults: d)
        #expect(store.shouldShowOnboarding && !store.shouldStartTour)
        store.onboardingDone = true
        #expect(!store.shouldShowOnboarding && store.shouldStartTour)
        store.tourDone = true
        #expect(!store.shouldStartTour)
        d.set(true, forKey: OnboardingStore.setupKey)
        store.reset()
        #expect(store.shouldShowOnboarding && !store.tourDone && !d.bool(forKey: OnboardingStore.setupKey))
    }
}
