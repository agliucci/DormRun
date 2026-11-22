import Foundation
import CoreLocation
import Observation

/// Publishes the runner's GPS to Realtime / Supabase ~every 5s — only during an active delivery.
@Observable
@MainActor
final class RunnerLocationService: NSObject {
    private let manager = CLLocationManager()
    private var publishTask: Task<Void, Never>?
    private var activeOrderId: String?
    private var runnerId: String?
    private weak var environment: AppEnvironment?

    private(set) var authorizationStatus: CLAuthorizationStatus
    private(set) var lastCoordinate: CLLocationCoordinate2D?
    private(set) var isPublishing = false
    private(set) var lastError: String?

    override init() {
        authorizationStatus = manager.authorizationStatus
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyBest
        manager.distanceFilter = 8
        manager.allowsBackgroundLocationUpdates = false
        manager.pausesLocationUpdatesAutomatically = true
    }

    func attach(environment: AppEnvironment) {
        self.environment = environment
    }

    func requestPermissionIfNeeded() {
        switch manager.authorizationStatus {
        case .notDetermined:
            manager.requestWhenInUseAuthorization()
        case .denied, .restricted:
            lastError = "Location is off. Enable it in Settings to share your pin while delivering."
        default:
            break
        }
    }

    /// Start GPS + 5s publish loop for an active delivery only.
    func startPublishing(orderId: String, runnerId: String) {
        self.activeOrderId = orderId
        self.runnerId = runnerId
        requestPermissionIfNeeded()
        beginPublishingIfAuthorized()
    }

    func stopPublishing() {
        publishTask?.cancel()
        publishTask = nil
        manager.stopUpdatingLocation()
        isPublishing = false
        activeOrderId = nil
        runnerId = nil
    }

    private func beginPublishingIfAuthorized() {
        guard activeOrderId != nil, runnerId != nil else { return }
        guard isAuthorized else { return }

        manager.startUpdatingLocation()
        isPublishing = true
        lastError = nil

        publishTask?.cancel()
        publishTask = Task { [weak self] in
            // First ping ASAP so customer map isn’t stuck on “Waiting…”.
            await self?.publishOnce()
            while let self, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 3_000_000_000)
                await self.publishOnce()
            }
        }
    }

    private var isAuthorized: Bool {
        switch manager.authorizationStatus {
        case .authorizedAlways, .authorizedWhenInUse: true
        default: false
        }
    }

    private func publishOnce() async {
        guard let coordinate = lastCoordinate,
              let orderId = activeOrderId,
              let runnerId,
              let environment else { return }

        let update = RunnerLocation(
            runnerId: runnerId,
            orderId: orderId,
            latitude: coordinate.latitude,
            longitude: coordinate.longitude,
            updatedAt: .now
        )

        do {
            await RunnerLocationHub.shared.publish(update)
            try await environment.realtime.publishRunnerLocation(update)
            if let client = SupabaseClientProvider.shared() {
                try? await client.publishRunnerLocation(
                    runnerId: runnerId,
                    orderId: orderId,
                    lat: coordinate.latitude,
                    lng: coordinate.longitude
                )
            }
        } catch {
            lastError = "Couldn't share location. We'll keep trying."
        }
    }
}

extension RunnerLocationService: CLLocationManagerDelegate {
    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        Task { @MainActor in
            authorizationStatus = manager.authorizationStatus
            if activeOrderId != nil {
                beginPublishingIfAuthorized()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            lastCoordinate = location.coordinate
            // Push immediately when the first fix arrives.
            if isPublishing {
                await publishOnce()
            }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in
            lastError = error.localizedDescription
        }
    }
}
