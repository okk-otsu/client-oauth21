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
            ZStack {
                Color(.systemGroupedBackground)
                    .ignoresSafeArea()

                Group {
                    if vm.isCheckingSession {
                        checkingView
                    } else if vm.isAuthenticated {
                        profileView
                            .onReceive(ticker) { now = $0 }
                            .padding(.horizontal, 16)
                            .padding(.top, 12)
                    } else {
                        authView
                            .padding(.horizontal, 20)
                            .padding(.top, 12)
                    }
                }
            }
            .navigationBarHidden(true)
            .overlay(loadingOverlay)
            .alert(
                vm.successMessage == nil ? "Error" : "Готово",
                isPresented: Binding(
                    get: { vm.error != nil || vm.successMessage != nil },
                    set: { if !$0 { vm.error = nil; vm.successMessage = nil } }
                )
            ) {
                Button("OK") { vm.error = nil; vm.successMessage = nil }
            } message: {
                Text(vm.successMessage ?? vm.error ?? "")
            }
        }
    }

    // MARK: Checking
    private var checkingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Checking session…")
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(.horizontal, 20)
        .padding(.top, 12)
    }

    // MARK: Auth
    private var authView: some View {
        VStack(spacing: 16) {
            Picker("Mode", selection: $vm.mode) {
                ForEach(AuthViewModel.AuthMode.allCases) { mode in
                    Text(mode.rawValue).tag(mode)
                }
            }
            .pickerStyle(.segmented)

            TextField("Username", text: $vm.username)
                .textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never)

            SecureField("Password", text: $vm.password)
                .textFieldStyle(.roundedBorder)

            Button(vm.mode == .login ? "Login" : "Register & Login") {
                Task { await vm.continueAuth() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(vm.username.isEmpty || vm.password.isEmpty)

            Button("Reset All") {
                vm.resetAll()
            }
            .foregroundColor(.red)
            .font(.caption)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(16)
        .frame(maxWidth: 520)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
    }

    // MARK: Profile
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
                    profileRow(title: "ID", value: profile?.sub ?? "—")
                    Divider().opacity(0.35)
                    profileRow(title: "Имя пользователя", value: profile?.displayUsername ?? "—")
                    Divider().opacity(0.35)
                    profileRow(title: "Дата обновления", value: profile?.updatedAtText ?? "—")
                }
                .tileWidth(min: tileMinWidth)
                .settingsCardStyle()

                Spacer()

                VStack(spacing: 14) {
                    HStack(spacing: 8) {
                        Image(systemName: "clock")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.secondary)

                        Text("Истекает через:")
                            .font(.system(size: 22, weight: .semibold))
                            .foregroundStyle(.secondary)
                    }

                    Text(expiresText(now: now))
                        .font(.system(size: 52, weight: .bold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 28)
                .tileWidth(min: tileMinWidth)
                .settingsCardStyle()

                Spacer()

                Button {
                    Task { await vm.refreshTokenManually() }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "arrow.clockwise")
                            .font(.system(size: 20, weight: .semibold))

                        Text("Обновить токен")
                            .font(.system(size: 22, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.primary)
                .tileWidth(min: tileMinWidth)
                .settingsCardStyle()

                Button {
                    Task { await vm.logout() }
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: "rectangle.portrait.and.arrow.right")
                            .font(.system(size: 20, weight: .semibold))

                        Text("Выйти")
                            .font(.system(size: 22, weight: .semibold))
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 18)
                }
                .buttonStyle(.plain)
                .foregroundStyle(.red)
                .tileWidth(min: tileMinWidth)
                .settingsCardStyle()
            }
            .frame(maxWidth: 560)
            .frame(maxWidth: .infinity)
        }
    }

    private var avatar: some View {
        Circle()
            .fill(Color(.secondarySystemGroupedBackground))
            .frame(width: 125, height: 125)
            .overlay(
                Image(systemName: "person.fill")
                    .font(.system(size: 54, weight: .semibold))
                    .foregroundStyle(.secondary)
            )
            .overlay(
                Circle()
                    .strokeBorder(Color(.separator).opacity(0.35), lineWidth: 0.5)
            )
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
        if seconds <= 0 { return "0 сек" }

        let mins = seconds / 60
        let secs = seconds % 60

        return mins >= 1 ? "\(mins) мин" : "\(secs) сек"
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

// MARK: - Tile width helper
private extension View {
    func tileWidth(min: CGFloat) -> some View {
        self
            .frame(maxWidth: .infinity)
            .frame(minWidth: min)
    }
}

// MARK: - Settings-like card style
private extension View {
    func settingsCardStyle() -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .stroke(Color(.separator).opacity(0.25), lineWidth: 0.5)
            )
    }
}
