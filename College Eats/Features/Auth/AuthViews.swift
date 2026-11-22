import SwiftUI

struct AuthGateView: View {
    @Environment(AppEnvironment.self) private var env
    @State private var email = ""
    @State private var code = ""
    @State private var step: Step = .email
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var showOnboarding = false

    private enum Step { case email, code }

    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: AppSpacing.xl) {
                VStack(alignment: .leading, spacing: AppSpacing.md) {
                    Image("BrandMark")
                        .resizable()
                        .scaledToFit()
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                        .shadow(color: AppColors.brand.opacity(0.28), radius: 16, y: 8)
                        .accessibilityHidden(true)

                    HStack(alignment: .firstTextBaseline, spacing: 0) {
                        Text(DesignSystem.brandName)
                            .font(AppTypography.display.italic())
                            .foregroundStyle(AppColors.textPrimary)
                            .tracking(-0.8)
                        Text(".")
                            .font(AppTypography.display)
                            .foregroundStyle(AppColors.brand)
                    }

                    Text(step == .email
                         ? "Campus food, delivered by students."
                         : "Enter the 6-digit code we emailed you.")
                        .appText(.body, color: AppColors.textSecondary)
                }
                .padding(.top, AppSpacing.xxl)

                if step == .email {
                    emailField
                    if let campus = detectedCampus {
                        HStack(spacing: AppSpacing.xs) {
                            Image(systemName: "building.columns.fill")
                            Text(campus.name)
                        }
                        .font(AppTypography.caption.weight(.semibold))
                        .foregroundStyle(AppColors.brand)
                        .padding(.horizontal, AppSpacing.sm)
                        .padding(.vertical, AppSpacing.xs)
                        .background(AppColors.brand.opacity(0.12))
                        .clipShape(Capsule(style: .continuous))
                        .accessibilityLabel("Campus \(campus.name)")
                    } else if isValidEmail {
                        Text("That .edu isn’t mapped to a campus yet.")
                            .appText(.caption, color: AppColors.warning)
                    }
                    PrimaryButton(title: "Send code", systemImage: "envelope.fill", isLoading: isLoading, isEnabled: detectedCampus != nil) {
                        Task { await sendCode() }
                    }
                } else {
                    codeField
                    PrimaryButton(title: "Verify & continue", isLoading: isLoading, isEnabled: code.count == 6) {
                        Task { await verify() }
                    }
                    Button("Use a different email") {
                        withAnimation(AppMotion.spring) { step = .email; code = "" }
                    }
                    .font(AppTypography.subheadline)
                    .foregroundStyle(AppColors.brand)
                }

                if let errorMessage {
                    Text(errorMessage)
                        .appText(.footnote, color: AppColors.danger)
                }

                Spacer()

                Text(env.usesLiveAuth
                     ? "Codes are sent by Supabase Auth to your campus email."
                     : "Campus gate is on. Without Supabase keys, any 6-digit code works and your profile is saved on device.")
                    .appText(.caption, color: AppColors.textTertiary)
            }
            .padding(AppSpacing.screenMargin)
            .background(AppColors.background.ignoresSafeArea())
            .navigationBarHidden(true)
            .sheet(isPresented: $showOnboarding) {
                OnboardingView()
                    .environment(env)
                    .interactiveDismissDisabled()
            }
        }
    }

    private var emailField: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text("School email")
                .appText(.caption, color: AppColors.textSecondary)
            TextField("netid@umass.edu", text: $email)
                .textInputAutocapitalization(.never)
                .keyboardType(.emailAddress)
                .autocorrectionDisabled()
                .padding(AppSpacing.md)
                .background(AppColors.surface)
                .appCornerRadius(AppRadius.md)
                .overlay {
                    RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                        .strokeBorder(AppColors.border, lineWidth: 1)
                }
                .font(AppTypography.body)
        }
    }

    private var codeField: some View {
        VStack(alignment: .leading, spacing: AppSpacing.xs) {
            Text("One-time code")
                .appText(.caption, color: AppColors.textSecondary)
            TextField("123456", text: $code)
                .keyboardType(.numberPad)
                .font(AppTypography.code)
                .multilineTextAlignment(.center)
                .padding(AppSpacing.md)
                .background(AppColors.surface)
                .appCornerRadius(AppRadius.md)
                .overlay {
                    RoundedRectangle(cornerRadius: AppRadius.md, style: .continuous)
                        .strokeBorder(AppColors.border, lineWidth: 1)
                }
                .onChange(of: code) { _, newValue in
                    code = String(newValue.filter(\.isNumber).prefix(6))
                }
        }
    }

    private var isValidEmail: Bool {
        CampusRegistry.emailDomain(from: email) != nil
    }

    private var detectedCampus: Campus? {
        CampusRegistry.campus(forEmail: email)
    }

    private func sendCode() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            try await env.authRepository.sendOTP(email: email.trimmingCharacters(in: .whitespacesAndNewlines))
            withAnimation(AppMotion.spring) { step = .code }
            AppHaptics.success()
        } catch {
            errorMessage = (error as? AppError)?.message ?? error.localizedDescription
            AppHaptics.error()
        }
    }

    private func verify() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let profile = try await env.authRepository.verifyOTP(email: email, code: code)
            env.session.profile = profile
            env.session.isOnboardingComplete = !(profile.fullName.isEmpty || profile.phone.isEmpty)
            if !env.session.isOnboardingComplete {
                showOnboarding = true
            }
            AppHaptics.success()
        } catch {
            errorMessage = (error as? AppError)?.message ?? error.localizedDescription
            AppHaptics.error()
        }
    }
}

struct OnboardingView: View {
    @Environment(AppEnvironment.self) private var env
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var phone = ""
    @State private var buildingId: String = MockCatalogData.buildings.first?.id ?? ""
    @State private var wantsRunner = false
    @State private var vehicle: VehicleType = .walk
    @State private var isSaving = false
    @State private var errorMessage: String?

    var body: some View {
        NavigationStack {
            Form {
                Section("About you") {
                    TextField("Full name", text: $name)
                    TextField("Phone", text: $phone)
                        .keyboardType(.phonePad)
                }
                Section("Home base") {
                    Picker("Building / dorm", selection: $buildingId) {
                        ForEach(env.session.buildings) { building in
                            Text("\(building.name) · \(building.neighborhood)").tag(building.id)
                        }
                    }
                }
                Section("Runner (optional)") {
                    Toggle("I want to deliver too", isOn: $wantsRunner)
                    if wantsRunner {
                        Picker("Vehicle", selection: $vehicle) {
                            ForEach(VehicleType.allCases, id: \.self) { type in
                                Label(type.label, systemImage: type.systemImage).tag(type)
                            }
                        }
                    }
                }
                Section("Location") {
                    Text("DormRun uses your location to show live runner ETAs and share your pin while delivering.")
                        .appText(.footnote, color: AppColors.textSecondary)
                    Button("Allow location access") {
                        env.runnerLocation.requestPermissionIfNeeded()
                    }
                }
                if let errorMessage {
                    Text(errorMessage).foregroundStyle(AppColors.danger)
                }
            }
            .scrollContentBackground(.hidden)
            .background(AppColors.background)
            .navigationTitle("Welcome")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { Task { await save() } }
                        .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || phone.count < 7 || isSaving)
                }
            }
            .task {
                if env.session.buildings.isEmpty {
                    env.session.buildings = MockCatalogData.buildings
                }
                if buildingId.isEmpty || !env.session.buildings.contains(where: { $0.id == buildingId }) {
                    buildingId = env.session.buildings.first?.id ?? ""
                }
                // Prompt early so tracking / Deliver already have permission.
                env.runnerLocation.requestPermissionIfNeeded()
            }
        }
    }

    private func save() async {
        guard var profile = env.session.profile else { return }
        isSaving = true
        defer { isSaving = false }
        profile.fullName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        profile.phone = phone
        profile.campusId = env.session.selectedCampus.id
        profile.homeBuildingId = buildingId
        profile.isRunner = wantsRunner
        profile.vehicleType = wantsRunner ? vehicle : nil
        do {
            env.session.profile = try await env.authRepository.updateProfile(profile)
            env.session.isOnboardingComplete = true
            env.cart.dropoffBuildingId = buildingId
            env.runnerLocation.requestPermissionIfNeeded()
            dismiss()
        } catch {
            errorMessage = (error as? AppError)?.message ?? error.localizedDescription
        }
    }
}
