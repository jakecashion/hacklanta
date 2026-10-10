import MapKit
import SwiftUI

struct NearbyMapView: View {
    @EnvironmentObject var tracker: LocationTracker
    @EnvironmentObject var matchStore: MatchStore

    @State private var camera: MapCameraPosition = .userLocation(
        fallback: .region(MKCoordinateRegion(
            center: MockData.defaultCenter,
            latitudinalMeters: 1000, longitudinalMeters: 1000))
    )
    @State private var users = MockData.currentUsers()
    @State private var anchored = false
    @State private var selected: NearbyUser?
    @State private var showDevMenu = false

    var body: some View {
        Map(position: $camera) {
            UserAnnotation()
            ForEach(users) { user in
                Annotation(user.name, coordinate: user.coordinate, anchor: .bottom) {
                    SongPin(user: user, isSelected: selected?.id == user.id)
                        .onTapGesture { tapHaptic(); selected = user }
                }
            }
        }
        .mapStyle(.standard(elevation: .flat))
        .mapControls {
            MapUserLocationButton()
            MapCompass()
        }
        .overlay(alignment: .topLeading) {
            Button { showDevMenu = true } label: {
                Image(systemName: "wrench.and.screwdriver")
                    .font(.body.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 44, height: 44)
                    .background(Color.card, in: Circle())
            }
            .accessibilityLabel("Dev menu")
            .padding(12)
            .sheet(isPresented: $showDevMenu, onDismiss: { matchStore.sheetDidDismiss() }) {
                DevMenuView().preferredColorScheme(.dark)
            }
        }
        .overlay(alignment: .bottom) {
            Text(pillText)
                .font(.footnote.weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.card, in: Capsule())
                .padding(.bottom, 12)
        }
        .sheet(item: $selected, onDismiss: { matchStore.sheetDidDismiss() }) { user in
            NearbyUserCard(
                user: user,
                onRecommend: { open(user, .songSearch) },
                onMeetUp: { open(user, .meetup) }
            )
            .presentationDetents([.height(300)])
            .presentationBackgroundInteraction(.enabled)
            .preferredColorScheme(.dark)
        }
        // Put the mock people around the real position once the tracker has a fix.
        .onChange(of: tracker.totalCount) { _, _ in
            guard !anchored, let fix = tracker.fixes.first else { return }
            anchored = true
            MockData.center = CLLocationCoordinate2D(latitude: fix.lat, longitude: fix.lon)
            users = MockData.currentUsers()
            // Keep an open card in step with the new positions.
            if let id = selected?.id { selected = users.first { $0.id == id } }
        }
        // Tell the store when a sheet is up, and close it when the store asks.
        .onChange(of: selected != nil || showDevMenu) { _, up in matchStore.isSheetUp = up }
        .onChange(of: matchStore.closeSheetsToken) { _, _ in
            selected = nil
            showDevMenu = false
        }
    }

    private var pillText: String {
        switch users.count {
        case 0: "No one near you yet"
        case 1: "1 person near you"
        default: "\(users.count) people near you"
        }
    }

    /// The card closes first. The match flow opens when the card is gone.
    private func open(_ user: NearbyUser, _ route: MatchRoute) {
        matchStore.whenReady { matchStore.open(user, route: route) }
    }
}

#Preview {
    NearbyMapView()
        .environmentObject(LocationTracker.shared)
        .environmentObject(MatchStore())
        .preferredColorScheme(.dark)
}
