import Foundation

// Spec 2 "First-run onboarding": Welcome -> Get the other app -> Permissions -> app -> guided tour.

public enum OnboardingPage: String, CaseIterable, Sendable {
    case welcome, howItWorks, getIPhone, permissions
}

public struct OnboardingFlow: Equatable, Sendable {
    public let pages: [OnboardingPage]
    public private(set) var index = 0
    public private(set) var isFinished = false

    public init(pages: [OnboardingPage] = OnboardingPage.allCases) { self.pages = pages }

    public var current: OnboardingPage? { isFinished ? nil : pages[index] }
    public var pageNumber: Int { index + 1 }
    public var canGoBack: Bool { !isFinished && index > 0 }
    public var isLastPage: Bool { index == pages.count - 1 }

    public mutating func next() {
        guard !isFinished else { return }
        if isLastPage { isFinished = true } else { index += 1 }
    }

    public mutating func back() {
        guard canGoBack else { return }
        index -= 1
    }
}

/// Coach-mark targets of the Mac tour, in order. `menuBar` has no on-window target (text only).
public enum TourTarget: String, CaseIterable, Sendable {
    case statusCard, pairRow, calibrate, centerCursor, permissionsRow, menuBar

    public var hasTarget: Bool { self != .menuBar }
}

public struct TourFlow: Equatable, Sendable {
    public let steps: [TourTarget]
    public private(set) var index = 0
    public private(set) var isFinished = false
    public private(set) var wasSkipped = false

    public init(steps: [TourTarget] = TourTarget.allCases) { self.steps = steps }

    public var current: TourTarget? { isFinished ? nil : steps[index] }
    public var stepNumber: Int { index + 1 }
    public var total: Int { steps.count }
    public var isLastStep: Bool { index == steps.count - 1 }

    public mutating func next() {
        guard !isFinished else { return }
        if isLastStep { isFinished = true } else { index += 1 }
    }

    public mutating func skip() {
        isFinished = true
        wasSkipped = true
    }
}

/// Persisted flags (UserDefaults). Tests pass their own suite.
public struct OnboardingStore {
    public static let onboardingKey = "onboarding.done.v1"
    public static let tourKey = "tour.done.v1"
    public static let setupKey = "setupCompleted.v1"

    public let defaults: UserDefaults
    public init(defaults: UserDefaults = .standard) { self.defaults = defaults }

    public var onboardingDone: Bool {
        get { defaults.bool(forKey: Self.onboardingKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.onboardingKey) }
    }

    public var tourDone: Bool {
        get { defaults.bool(forKey: Self.tourKey) }
        nonmutating set { defaults.set(newValue, forKey: Self.tourKey) }
    }

    public var shouldShowOnboarding: Bool { !onboardingDone }
    /// Tour runs once, after onboarding finished and the user arrived in the app.
    public var shouldStartTour: Bool { onboardingDone && !tourDone }

    /// `--reset-onboarding`: show Welcome, Permissions on launch, and the tour again.
    public func reset() {
        for k in [Self.onboardingKey, Self.tourKey, Self.setupKey] { defaults.removeObject(forKey: k) }
    }
}
