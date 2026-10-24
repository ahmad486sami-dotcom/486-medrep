import SwiftUI
import SwiftData

struct RootView: View {
    @ObservedObject private var router = AppRouter.shared
    @StateObject private var lock = LockManager()
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.modelContext) private var context
    @Query private var doctors: [Doctor]
    @AppStorage(Keys.faceID) private var faceID = false
    @State private var showSplash = true

    var body: some View {
        ZStack {
            TabView(selection: $router.tab) {
                TodayView()
                    .tabItem { Label("Today", systemImage: "sun.max.fill") }
                    .tag(AppTab.today)
                MapTabView()
                    .tabItem { Label("Map", systemImage: "map.fill") }
                    .tag(AppTab.map)
                PlannerView()
                    .tabItem { Label("Planner", systemImage: "calendar") }
                    .tag(AppTab.planner)
                DirectoryView()
                    .tabItem { Label("Directory", systemImage: "building.2.fill") }
                    .tag(AppTab.directory)
                RecordsView()
                    .tabItem { Label("Records", systemImage: "chart.bar.doc.horizontal.fill") }
                    .tag(AppTab.records)
            }
            .tint(Theme.accent)
            .sensoryFeedback(.selection, trigger: router.tab)

            if faceID && scenePhase != .active && !lock.isLocked {
                PrivacyCover().transition(.opacity).zIndex(1)
            }

            if lock.isLocked {
                LockView(lock: lock)
                    .transition(.opacity)
                    .zIndex(2)
            }

            if showSplash {
                SplashView()
                    .transition(.opacity.combined(with: .scale(scale: 1.08)))
                    .zIndex(3)
            }
        }
        .onAppear {
            Notifier.requestPermission()
            LocationManager.shared.request()
            Notifier.reschedule(context: context)
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.15) {
                withAnimation(.easeInOut(duration: 0.45)) { showSplash = false }
                if lock.isLocked { lock.unlock() }
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                lock.lockIfNeeded()
                Notifier.reschedule(context: context)
            case .active:
                if lock.isLocked && !showSplash { lock.unlock() }
                LocationManager.shared.request()
            default:
                break
            }
        }
        .sheet(item: $router.openDoctor) { link in
            NavigationStack {
                if let doctor = doctors.first(where: { $0.id == link.id }) {
                    DoctorDetailView(doctor: doctor)
                        .toolbar {
                            ToolbarItem(placement: .cancellationAction) {
                                Button("Close") { router.openDoctor = nil }
                            }
                        }
                } else {
                    EmptyStateView(systemImage: "person.crop.circle.badge.questionmark", title: "Doctor not found", message: "This doctor may have been deleted.")
                }
            }
        }
    }
}

// MARK: - Splash

struct SplashView: View {
    @State private var appear = false
    @State private var ring = false

    var body: some View {
        ZStack {
            Theme.gradient.ignoresSafeArea()
            Circle()
                .stroke(Color.white.opacity(0.18), lineWidth: 2)
                .frame(width: ring ? 420 : 120, height: ring ? 420 : 120)
                .opacity(ring ? 0 : 1)
            VStack(spacing: 10) {
                Text("486")
                    .font(.system(size: 92, weight: .heavy, design: .rounded))
                    .foregroundStyle(.white)
                    .scaleEffect(appear ? 1 : 0.55)
                    .opacity(appear ? 1 : 0)
                    .blur(radius: appear ? 0 : 8)
                Text("Visits · Notes · Routes")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.85))
                    .opacity(appear ? 1 : 0)
                    .offset(y: appear ? 0 : 12)
            }
        }
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.68)) { appear = true }
            withAnimation(.easeOut(duration: 1.1)) { ring = true }
        }
    }
}

// MARK: - Lock

struct LockView: View {
    @ObservedObject var lock: LockManager

    var body: some View {
        ZStack {
            Theme.gradient.ignoresSafeArea()
            VStack(spacing: 18) {
                Image(systemName: "faceid")
                    .font(.system(size: 56, weight: .regular))
                    .foregroundStyle(.white)
                    .symbolEffect(.pulse, options: .repeating)
                Text("486 is locked")
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.white)
                Button {
                    lock.unlock()
                } label: {
                    Text("Unlock")
                        .font(.headline)
                        .padding(.horizontal, 36)
                        .padding(.vertical, 12)
                        .background(.white, in: Capsule())
                        .foregroundStyle(Theme.accent)
                }
                .buttonStyle(PressableButtonStyle())
            }
        }
    }
}

struct PrivacyCover: View {
    var body: some View {
        ZStack {
            Theme.gradient.ignoresSafeArea()
            Text("486")
                .font(.system(size: 64, weight: .heavy, design: .rounded))
                .foregroundStyle(.white)
        }
    }
}
