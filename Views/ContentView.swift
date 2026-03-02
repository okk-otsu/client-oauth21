//
//  ContentView.swift
//  cli-oauth21
//  Created by Dmitry Alexandrov on 27.10.2025.
//

import SwiftUI

struct ContentView: View {
    @StateObject private var vm = AuthViewModel()

    @State private var now = Date()
    private let ticker = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationView {
            Group {
                if vm.isCheckingSession {
                    checkingView
                } else if vm.isAuthenticated {
                    profileView
                        .onReceive(ticker) { now = $0 }
                        .padding(.horizontal, 10)
                        .padding(.top, 12)
                } else {
                    loginView
                        .padding(.horizontal, 20)
                        .padding(.top, 12)
                }
            }
            .navigationBarHidden(true)
            .overlay(loadingOverlay)
            .alert(
                String(localized: "common.error.title"),
                isPresented: Binding(
                    get: { vm.errorMessage != nil },
                    set: { if !$0 { vm.errorMessage = nil } }
                )
            ) {
                Button(String(localized: "common.ok")) {
                    vm.errorMessage = nil
                }
            } message: {
                Text(vm.errorMessage ?? "")
            }

            .alert(
                String(localized: "common.done.title"),
                isPresented: Binding(
                    get: { vm.successMessage != nil },
                    set: { if !$0 { vm.successMessage = nil } }
                )
            ) {
                Button(String(localized: "common.ok")) {
                    vm.successMessage = nil
                }
            } message: {
                Text(vm.successMessage ?? "")
            }
        }
    }

    // MARK: - Checking
    private var checkingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text(String(localized: "auth.checking"))
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    // MARK: - Login Screen
    private var loginView: some View {
        VStack(spacing: 22) {
            Spacer(minLength: 40)

            Text(String(localized: "auth.title.login"))
                .font(.system(size: 32, weight: .semibold))

            VStack(spacing: 16) {
                TextField(String(localized: "auth.field.username"), text: $vm.username)
                    .font(.system(size: 18))
                    .padding(.vertical, 16)
                    .padding(.horizontal, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.secondarySystemGroupedBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(.separator).opacity(0.4), lineWidth: 0.5)
                    )
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()

                SecureField(String(localized: "auth.field.password"), text: $vm.password)
                    .font(.system(size: 18))
                    .padding(.vertical, 16)
                    .padding(.horizontal, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color(.secondarySystemGroupedBackground))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 12)
                            .stroke(Color(.separator).opacity(0.4), lineWidth: 0.5)
                    )
            }

            Button {
                vm.mode = .login
                Task { await vm.continueAuth() }
            } label: {
                Text(String(localized: "auth.action.login"))
                    .font(.system(size: 18, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
            .disabled(vm.username.isEmpty || vm.password.isEmpty)

            Button {
                vm.mode = .register
                Task { await vm.continueAuth() }
            } label: {
                Text(String(localized: "auth.action.registerLogin"))
                    .font(.system(size: 18, weight: .semibold))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
            }
            .buttonStyle(.borderedProminent)
            .tint(.gray.opacity(0.6))
            .disabled(vm.username.isEmpty || vm.password.isEmpty)

            Spacer(minLength: 10)

            Button {
                vm.resetAll()
            } label: {
                Text(String(localized: "auth.action.resetAll"))
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundStyle(.red)

            Spacer()
        }
        .frame(maxWidth: 420)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Profile
    private var profileView: some View {
        let profile = vm.userInfo.flatMap { UserProfile(from: $0) }
        let tileMinWidth: CGFloat = 380

        return ScrollView(showsIndicators: false) {
            VStack(spacing: 18) {
                HStack() {
                    avatar
                        .padding(.top, 12)
                        .padding(.bottom, 6)
                    Spacer()
                }
                .padding(10)

                VStack(alignment: .leading, spacing: 0) {
                    profileRow(title: String(localized: "profile.field.id"), value: profile?.sub ?? "—")
                    Divider().opacity(0.5)
                    profileRow(title: String(localized: "profile.field.username"), value: profile?.displayUsername ?? "—")
                    Divider().opacity(0.5)
                    profileRow(title: String(localized: "profile.field.updated"), value: profile?.updatedAtText ?? "—")
                }
                .tileWidth(min: tileMinWidth)
                .cardStyle()

                Spacer()

                VStack(spacing: 14) {
                    HStack(spacing: 6) {
                        Image(systemName: "clock")
                            .font(.headline)
                            .foregroundStyle(.secondary)

                        Text(String(localized: "profile.expires"))
                            .font(.headline)
                            .foregroundStyle(.secondary)
                    }

                    Text(expiresText(now: now))
                        .font(.system(size: 52, weight: .bold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .tileWidth(min: tileMinWidth)
                .cardStyle()

                Spacer()

                Button {
                    Task { await vm.refreshTokenManually() }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 20, weight: .semibold))

                        Text(String(localized: "profile.refresh"))
                            .font(.system(size: 22, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
                .tileWidth(min: tileMinWidth)
                .cardStyle()

                Button {
                    Task { await vm.logout() }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 20, weight: .semibold))

                        Text(String(localized: "profile.logout"))
                            .font(.system(size: 22, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
                .tileWidth(min: tileMinWidth)
                .cardStyle()
            }
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
    }

    private var avatar: some View {
        Circle()
            .fill(Color.gray.opacity(0.18))
            .frame(width: 125, height: 125)
            .overlay(
                Image(systemName: "person.fill")
                    .font(.system(size: 52, weight: .semibold))
                    .foregroundStyle(.secondary)
            )
            .overlay(
                Circle()
                    .strokeBorder(Color.black.opacity(0.04), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.05), radius: 14, x: 0, y: 8)
    }

    private func profileRow(title: String, value: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            Text(title)
                .font(.system(size: 18, weight: .medium))
                .foregroundStyle(.secondary)
                .frame(width: 170, alignment: .leading)

            Text(value)
                .font(.system(size: 22, weight: .semibold))
                .foregroundStyle(.primary)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .padding(.vertical, 18)
        .padding(.horizontal, 18)
    }

    private func expiresText(now: Date) -> String {
        guard let seconds = vm.secondsUntilAccessTokenExpires(from: now) else {
            return "—"
        }
        if seconds <= 0 { return String(localized: "time.zeroSeconds") }

        let mins = seconds / 60
        let secs = seconds % 60

        if mins >= 1 {
            return String.localizedStringWithFormat(String(localized: "time.minutes"), mins)
        } else {
            return String.localizedStringWithFormat(String(localized: "time.seconds"), secs)
        }
    }

    private var loadingOverlay: some View {
        Group {
            if vm.isLoading {
                ZStack {
                    Color.black.opacity(0.3).ignoresSafeArea()
                    ProgressView()
                        .scaleEffect(1.5)
                }
            }
        }
    }
}

private extension View {
    func tileWidth(min: CGFloat) -> some View {
        self
            .frame(maxWidth: .infinity)
            .frame(minWidth: min)
    }
}

private extension View {
    func cardStyle() -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color.black.opacity(0.04), lineWidth: 1)
            )
            .shadow(color: Color.black.opacity(0.04), radius: 12, x: 0, y: 8)
    }
}
