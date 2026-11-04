import Foundation
import Testing
@testable import AirMouseCore

final class FakeChecker: PermissionChecker {
    var values: [PermissionKind: PermissionStatus]
    init(_ v: [PermissionKind: PermissionStatus]) { values = v }
    func check(_ kind: PermissionKind, completion: @escaping (PermissionStatus) -> Void) { completion(values[kind] ?? .notDetermined) }
}

@Suite struct SetupTests {
    func flow(_ v: [PermissionKind: PermissionStatus]) -> SetupFlow {
        var f = SetupFlow()
        SetupFlow.refresh(using: FakeChecker(v)) { f.update($0, $1) }
        return f
    }

    @Test func orderAndRequirements() {
        #expect(SetupFlow.order == [.accessibility, .bluetooth, .localNetwork, .firewall])
        #expect(PermissionKind.accessibility.requirement == .required)
        #expect(PermissionKind.localNetwork.requirement == .required)
        #expect(PermissionKind.bluetooth.requirement == .optional)
        #expect(PermissionKind.firewall.requirement == .info)
    }

    @Test func requiredStepCannotContinueOrSkipUntilGranted() {
        var f = flow([:])
        #expect(f.current == .accessibility)
        #expect(!f.canContinue(.accessibility) && !f.canSkip(.accessibility))
        f.continueStep(); f.skipStep()
        #expect(f.current == .accessibility)
        f.update(.accessibility, .granted)
        f.continueStep()
        #expect(f.current == .bluetooth)
    }

    @Test func optionalCanBeSkippedInfoAlwaysContinues() {
        var f = flow([.accessibility: .granted, .bluetooth: .denied, .localNetwork: .granted, .firewall: .attention("blocked")])
        f.continueStep()
        #expect(f.current == .bluetooth && f.canSkip(.bluetooth) && !f.canContinue(.bluetooth))
        f.skipStep()
        #expect(f.skipped == [.bluetooth] && f.current == .localNetwork)
        f.continueStep()
        #expect(f.current == .firewall && f.canContinue(.firewall) && f.canSkip(.firewall))
        f.continueStep()
        #expect(f.isFinished && f.current == nil)
        #expect(f.allRequiredGranted && !f.allDone)
    }

    @Test func nextPendingAndAllDone() {
        var f = flow([.accessibility: .granted, .bluetooth: .granted, .localNetwork: .notDetermined, .firewall: .granted])
        #expect(f.firstPendingIndex == 2)
        f.restart(); #expect(f.current == .localNetwork)
        #expect(!f.allRequiredGranted)
        f.update(.localNetwork, .granted)
        #expect(f.allDone && f.firstPendingIndex == nil && f.warnings.isEmpty)
        f.restart(); #expect(f.current == .accessibility)
        f.open(.firewall); #expect(f.current == .firewall && f.stepNumber == 4)
    }

    @Test func checkingIsNotSatisfiedAndNotWarned() {
        let f = SetupFlow()
        #expect(f.warnings.isEmpty && !f.canContinue(.firewall) && !f.isSatisfied(.firewall))
    }

    @Test func warningsRequiredFirst() {
        let f = flow([.accessibility: .denied, .bluetooth: .off("Bluetooth is off"), .localNetwork: .denied, .firewall: .attention("x")])
        #expect(f.warnings == [.accessibility, .localNetwork, .bluetooth, .firewall])
    }

    @Test func finishLaterGoesToSummary() {
        var f = flow([:])
        f.finishLater()
        #expect(f.isFinished && !f.allRequiredGranted && f.warnings.contains(.accessibility))
    }

    @Test func launchFlag() {
        #expect(SetupFlow.shouldShowOnLaunch(completedBefore: false))
        #expect(!SetupFlow.shouldShowOnLaunch(completedBefore: true))
    }

    @Test func firewallParsing() {
        #expect(FirewallParser.status(global: "Firewall is disabled. (State = 0)", app: nil) == .granted)
        #expect(FirewallParser.status(global: "Firewall is enabled. (State = 1)", app: "Incoming connection to /Applications/AirMouse.app is permitted.") == .granted)
        #expect(FirewallParser.status(global: "Firewall is enabled. (State = 1)", app: "Incoming connection to /Applications/AirMouse.app is blocked.") == .attention("The firewall blocks AirMouse"))
        #expect(FirewallParser.status(global: "Firewall is blocking all non-essential incoming connections. (State = 2)", app: nil) == .attention("The firewall blocks all incoming connections"))
        #expect(FirewallParser.status(global: "", app: nil) == .granted)
    }
}

@Suite struct SectionTests {
    @Test func initialSection() {
        var f = SetupFlow()
        #expect(AppSection.initial(completedSetupBefore: false, flow: f) == .permissions)
        f.update(.accessibility, .notDetermined)
        #expect(AppSection.initial(completedSetupBefore: true, flow: f) == .permissions)
        f.update(.accessibility, .granted)
        f.update(.localNetwork, .notDetermined) // unknown at launch: don't force Permissions
        #expect(AppSection.initial(completedSetupBefore: true, flow: f) == .home)
    }

    @Test func calibrationRecord() throws {
        let d = Date(timeIntervalSince1970: 1_800_000_000)
        let r = try #require(CalibrationRecord.from(events: [.start, .placed, .point(.left), .done(sensitivity: 1480)], now: d))
        #expect(r == CalibrationRecord(sensitivity: 1480, biasOK: true, date: d))
        #expect(CalibrationRecord.decode(r.encoded()) == r)
        #expect(CalibrationRecord.from(events: [.start, .cancel], now: d) == nil)
        #expect(CalibrationRecord.from(events: [.start, .done(sensitivity: nil)], now: d)?.biasOK == false)
    }
}
