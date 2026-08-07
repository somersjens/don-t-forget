import Foundation

enum AutomatedReviewPersistence {
    static let totalActiveDuration = "review.totalActiveDuration"
    static let completedMilestoneCount = "review.completedMilestoneCount"
    static let requestDates = "review.requestDates"

    static let allKeys = [
        totalActiveDuration,
        completedMilestoneCount,
        requestDates
    ]
}

enum AutomatedReviewPolicy {
    static let usageMilestones: [TimeInterval] = [
        15 * 60,
        60 * 60,
        180 * 60
    ]
    static let minimumSessionDuration: TimeInterval = 90
    static let minimumIdleDuration: TimeInterval = 5
    static let minimumRequestInterval: TimeInterval = 14 * 24 * 60 * 60
    static let requestWindow: TimeInterval = 365 * 24 * 60 * 60
    static let maximumRequestsPerWindow = 3

    static func eligibleMilestone(
        totalActiveDuration: TimeInterval,
        completedMilestoneCount: Int,
        requestDates: [Date],
        sessionActiveDuration: TimeInterval,
        idleDuration: TimeInterval,
        isTextInputActive: Bool,
        now: Date
    ) -> Int? {
        guard completedMilestoneCount < usageMilestones.count,
              totalActiveDuration >= usageMilestones[completedMilestoneCount],
              sessionActiveDuration >= minimumSessionDuration,
              idleDuration >= minimumIdleDuration,
              !isTextInputActive else {
            return nil
        }

        let recentRequests = requestDates.filter {
            now.timeIntervalSince($0) >= 0 && now.timeIntervalSince($0) < requestWindow
        }
        guard recentRequests.count < maximumRequestsPerWindow else { return nil }

        if let latestRequest = requestDates.max(),
           now.timeIntervalSince(latestRequest) < minimumRequestInterval {
            return nil
        }

        return completedMilestoneCount
    }
}

#if os(iOS)
import StoreKit
import SwiftUI
import UIKit

@MainActor
final class AutomatedReviewRequestService {
    static let shared = AutomatedReviewRequestService()

    private let defaults: UserDefaults
    private var storedActiveDuration: TimeInterval
    private var activeSegmentStartedAt: Date?
    private var sessionActiveDuration: TimeInterval = 0
    private var lastInteractionDate = Date.now
    private var lastPeriodicSaveDate = Date.now
    private var sessionHasEnded = true

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        storedActiveDuration = defaults.double(
            forKey: AutomatedReviewPersistence.totalActiveDuration
        )
    }

    func sceneBecameActive(at date: Date = .now) {
        guard activeSegmentStartedAt == nil else { return }
        if sessionHasEnded {
            sessionActiveDuration = 0
            sessionHasEnded = false
        }
        activeSegmentStartedAt = date
        lastInteractionDate = date
        lastPeriodicSaveDate = date
    }

    func sceneBecameInactive(at date: Date = .now) {
        saveActiveSegment(at: date)
    }

    func sceneEnteredBackground(at date: Date = .now) {
        saveActiveSegment(at: date)
        sessionHasEnded = true
    }

    func recordInteraction(at date: Date = .now) {
        lastInteractionDate = date
    }

    func requestReviewIfEligible(
        at date: Date = .now,
        isTextInputActive: Bool,
        canPresent: Bool,
        requestReview: () -> Void
    ) {
        guard activeSegmentStartedAt != nil else { return }
        guard canPresent else {
            periodicallySaveUsage(at: date)
            return
        }

        let totalDuration = storedActiveDuration + currentSegmentDuration(at: date)
        let currentSessionDuration = sessionActiveDuration + currentSegmentDuration(at: date)
        let requestDates = storedRequestDates
        let completedCount = defaults.integer(
            forKey: AutomatedReviewPersistence.completedMilestoneCount
        )

        guard let milestone = AutomatedReviewPolicy.eligibleMilestone(
            totalActiveDuration: totalDuration,
            completedMilestoneCount: completedCount,
            requestDates: requestDates,
            sessionActiveDuration: currentSessionDuration,
            idleDuration: date.timeIntervalSince(lastInteractionDate),
            isTextInputActive: isTextInputActive,
            now: date
        ) else {
            periodicallySaveUsage(at: date)
            return
        }

        saveActiveSegment(at: date)
        defaults.set(
            milestone + 1,
            forKey: AutomatedReviewPersistence.completedMilestoneCount
        )
        defaults.set(
            (requestDates + [date]).map(\.timeIntervalSinceReferenceDate),
            forKey: AutomatedReviewPersistence.requestDates
        )
        requestReview()
        activeSegmentStartedAt = date
    }

    private var storedRequestDates: [Date] {
        (defaults.array(forKey: AutomatedReviewPersistence.requestDates) as? [NSNumber] ?? []).map {
            Date(timeIntervalSinceReferenceDate: $0.doubleValue)
        }
    }

    private func currentSegmentDuration(at date: Date) -> TimeInterval {
        guard let activeSegmentStartedAt else { return 0 }
        return max(0, date.timeIntervalSince(activeSegmentStartedAt))
    }

    private func saveActiveSegment(at date: Date) {
        let duration = currentSegmentDuration(at: date)
        guard duration > 0 else {
            activeSegmentStartedAt = nil
            return
        }

        storedActiveDuration += duration
        sessionActiveDuration += duration
        defaults.set(
            storedActiveDuration,
            forKey: AutomatedReviewPersistence.totalActiveDuration
        )
        activeSegmentStartedAt = nil
        lastPeriodicSaveDate = date
    }

    private func periodicallySaveUsage(at date: Date) {
        guard date.timeIntervalSince(lastPeriodicSaveDate) >= 30 else { return }
        saveActiveSegment(at: date)
        activeSegmentStartedAt = date
    }
}

struct AutomatedReviewRequestView: View {
    @Environment(\.requestReview) private var requestReview
    @Environment(\.scenePhase) private var scenePhase

    private let service = AutomatedReviewRequestService.shared

    var body: some View {
        Color.clear
            .frame(width: 0, height: 0)
            .accessibilityHidden(true)
            .onAppear {
                if scenePhase == .active {
                    service.sceneBecameActive()
                }
            }
            .onChange(of: scenePhase) { _, phase in
                switch phase {
                case .active:
                    service.sceneBecameActive()
                case .inactive:
                    service.sceneBecameInactive()
                case .background:
                    service.sceneEnteredBackground()
                @unknown default:
                    service.sceneBecameInactive()
                }
            }
            .task {
                while !Task.isCancelled {
                    try? await Task.sleep(for: .seconds(1))
                    guard !Task.isCancelled, scenePhase == .active else { continue }
                    service.requestReviewIfEligible(
                        isTextInputActive: UIResponder.reviewTextInputIsActive,
                        canPresent: UIApplication.shared.reviewCanPresentPrompt,
                        requestReview: { requestReview() }
                    )
                }
            }
    }
}

private extension UIResponder {
    nonisolated(unsafe) static weak var reviewFirstResponder: UIResponder?

    @objc func captureReviewFirstResponder(_ sender: Any?) {
        Self.reviewFirstResponder = self
    }

    @MainActor
    static var reviewTextInputIsActive: Bool {
        reviewFirstResponder = nil
        UIApplication.shared.sendAction(
            #selector(captureReviewFirstResponder(_:)),
            to: nil,
            from: nil,
            for: nil
        )
        return reviewFirstResponder is UITextField || reviewFirstResponder is UITextView
    }
}

private extension UIApplication {
    var reviewCanPresentPrompt: Bool {
        let activeWindow = connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive }?
            .windows
            .first { $0.isKeyWindow }

        guard let rootViewController = activeWindow?.rootViewController else { return false }
        return rootViewController.presentedViewController == nil
    }
}
#endif
