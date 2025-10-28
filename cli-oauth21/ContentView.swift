//
//  ContentView.swift
//  cli-oauth21
//  Created by Dmitry Alexandrov on 27.10.2025.
//
import SwiftUI

struct ContentView: View {
    @StateObject private var oauthClient = OAuth21Client()
    
    @State private var username = ""
    @State private var password = ""
    @State private var clientName = "Demo iOS App"
    @State private var isLoading = false
    @State private var currentStep = 0 // 0: начальный, 1: клиент зарегистрирован, 2: пользователь зарегистрирован, 3: аутентифицирован
    
    var body: some View {
        NavigationView {
            VStack(spacing: 20) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 60))
                    .foregroundColor(.blue)
                
                Text("OAuth 2.1 Authentication Flow")
                    .font(.headline)
                    .foregroundColor(.secondary)
                
                if oauthClient.isAuthenticated {
                    authenticatedView
                } else {
                    authenticationView
                }
                
                Spacer()
            }
            .padding()
            .navigationTitle("OAuth 2.1 Demo")
            .overlay(loadingOverlay)
            .alert("Error", isPresented: .constant(oauthClient.errorMessage != nil)) {
                Button("OK") { oauthClient.errorMessage = nil }
            } message: {
                Text(oauthClient.errorMessage ?? "Unknown error")
            }
        }
    }
    
    private var authenticationView: some View {
        VStack(spacing: 20) {
            credentialsSection
            
            if currentStep < 1 {
                clientRegistrationSection
            } else if currentStep == 1 {
                userRegistrationSection
            } else if currentStep >= 2 {
                authenticationSection
            }
            
            if currentStep > 0 {
                resetSection
            }
        }
    }
    
    private var credentialsSection: some View {
        VStack(spacing: 16) {
            Text("Step 1: Enter Credentials")
                .font(.headline)
                .foregroundColor(.primary)
            
            TextField("Username", text: $username)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .autocapitalization(.none)
                .disabled(isLoading)
            
            SecureField("Password", text: $password)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .disabled(isLoading)
        }
    }
    
    private var clientRegistrationSection: some View {
        VStack(spacing: 16) {
            Text("Step 2: Client Registration")
                .font(.headline)
                .foregroundColor(.primary)
            
            Text("Register this app as an OAuth client")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Button("Register Client") {
                Task { await registerClient() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(username.isEmpty || password.isEmpty || isLoading)
        }
        .padding()
        .background(Color.blue.opacity(0.1))
        .cornerRadius(10)
    }
    
    private var userRegistrationSection: some View {
        VStack(spacing: 16) {
            Text("Step 3: User Registration")
                .font(.headline)
                .foregroundColor(.primary)
            
            Text("Create a new user account")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Button("Register User") {
                Task { await registerUser() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(username.isEmpty || password.isEmpty || isLoading)
        }
        .padding()
        .background(Color.green.opacity(0.1))
        .cornerRadius(10)
    }
    
    private var authenticationSection: some View {
        VStack(spacing: 16) {
            Text(currentStep == 2 ? "Step 4: Authentication" : "Re-authenticate")
                .font(.headline)
                .foregroundColor(.primary)
            
            Text(currentStep == 2 ? "Complete OAuth 2.1 authentication flow" : "Authenticate with existing user")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Button(currentStep == 2 ? "Authenticate" : "Sign In") {
                Task { await authenticate() }
            }
            .buttonStyle(.borderedProminent)
            .disabled(username.isEmpty || password.isEmpty || isLoading)
        }
        .padding()
        .background(Color.orange.opacity(0.1))
        .cornerRadius(10)
    }
    
    private var resetSection: some View {
        VStack(spacing: 8) {
            Button("Reset Flow") {
                resetFlow()
            }
            .buttonStyle(.borderless)
            .foregroundColor(.red)
            .font(.caption)
            
            Text("This will clear all progress")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
    }
    
    private var authenticatedView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 50))
                .foregroundColor(.green)
            
            Text("Authenticated Successfully!")
                .font(.title2)
                .foregroundColor(.green)
            
            if let userInfo = oauthClient.userInfo {
                userInfoView(userInfo)
            }
            
            HStack(spacing: 16) {
                Button("Get User Info") {
                    Task { await getUserInfo() }
                }
                .buttonStyle(.bordered)
                
                Button("Logout") {
                    logout()
                }
                .buttonStyle(.borderedProminent)
                .tint(.red)
            }
        }
    }
    
    private var loadingOverlay: some View {
        Group {
            if isLoading {
                ZStack {
                    Color.black.opacity(0.3)
                        .ignoresSafeArea()
                    
                    VStack(spacing: 16) {
                        ProgressView()
                            .scaleEffect(1.5)
                        
                        Text("Processing...")
                            .font(.headline)
                            .foregroundColor(.white)
                    }
                    .padding(30)
                    .background(Color.black.opacity(0.8))
                    .cornerRadius(15)
                }
            }
        }
    }
    
    private func userInfoView(_ userInfo: [String: Any]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("User Information:")
                .font(.headline)
                .foregroundColor(.primary)
            
            Divider()
            
            InfoRow(label: "User ID", value: userInfo["sub"] as? String ?? "N/A")
            InfoRow(label: "Username", value: userInfo["name"] as? String ?? "N/A")
            InfoRow(label: "Email", value: userInfo["email"] as? String ?? "N/A")
            
            if let updatedAt = userInfo["updated_at"] as? Int {
                InfoRow(label: "Last Updated", value: DateFormatter.localizedString(from: Date(timeIntervalSince1970: TimeInterval(updatedAt)), dateStyle: .medium, timeStyle: .medium))
            }
        }
        .padding()
        .background(Color.gray.opacity(0.1))
        .cornerRadius(8)
    }
    
    private func registerClient() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            try await oauthClient.registerClient(clientName: clientName)
            await MainActor.run {
                oauthClient.errorMessage = nil
                currentStep = 1
            }
        } catch {
            await MainActor.run { oauthClient.errorMessage = error.localizedDescription }
        }
    }
    
    private func registerUser() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            try await oauthClient.registerUser(username: username, password: password)
            await MainActor.run {
                oauthClient.errorMessage = nil
                currentStep = 2
            }
        } catch {
            await MainActor.run { oauthClient.errorMessage = error.localizedDescription }
        }
    }
    
    private func authenticate() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            let tokens = try await oauthClient.authenticate(username: username, password: password)
            print("Authentication successful: \(tokens)")
            
            await MainActor.run {
                oauthClient.errorMessage = nil
                currentStep = 3
            }
        } catch {
            await MainActor.run { oauthClient.errorMessage = error.localizedDescription }
        }
    }
    
    private func getUserInfo() async {
        isLoading = true
        defer { isLoading = false }
        
        do {
            _ = try await oauthClient.fetchUserInfo()
        } catch {
            await MainActor.run { oauthClient.errorMessage = error.localizedDescription }
        }
    }
    
    private func resetFlow() {
        currentStep = 0
        username = ""
        password = ""
        oauthClient.reset()
    }
    
    private func logout() {
        // При logout сохраняем логин и пароль, но сбрасываем состояние аутентификации
        oauthClient.logout()
        currentStep = 2 // Возвращаем к шагу аутентификации
    }
}

struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .frame(width: 100, alignment: .leading)
            
            Text(value)
                .font(.subheadline)
                .foregroundColor(.primary)
                .textSelection(.enabled)
            
            Spacer()
        }
    }
}

