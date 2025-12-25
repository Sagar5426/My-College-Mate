import SwiftUI
import LocalAuthentication

// MARK: - Fix: Add @MainActor to ensure all published updates happen on the main thread
@MainActor
class AuthenticationViewModel: ObservableObject {
    
    @Published var isUnlocked = false
    @Published var hasBiometrics = false
    @Published var showError = false
    @Published var errorMessage = ""
    
    // Add the missing callback property
    var onLoginSuccess: (() -> Void)?
    
    init() {
        checkBiometricAvailability()
    }
    
    func checkBiometricAvailability() {
        let context = LAContext()
        var error: NSError?
        
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            hasBiometrics = true
        } else {
            hasBiometrics = false
            if let error = error {
                print("Biometrics unavailable: \(error.localizedDescription)")
            }
        }
    }
    
    func authenticate() {
        let context = LAContext()
        var error: NSError?
        
        // Check for biometrics again before attempting
        if context.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &error) {
            let reason = "Unlock My College Mate"
            
            context.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: reason) { [weak self] success, authenticationError in
                
                // IMPORTANT: Dispatch back to main thread
                Task { @MainActor in
                    if success {
                        self?.isUnlocked = true
                        // Call the success closure if it exists
                        self?.onLoginSuccess?()
                    } else {
                        self?.showError = true
                        self?.errorMessage = authenticationError?.localizedDescription ?? "Authentication failed"
                    }
                }
            }
        } else {
            self.showError = true
            self.errorMessage = "Biometrics not available"
        }
    }
    
    // Simple bypass for testing (optional)
    func unlockForTesting() {
        isUnlocked = true
        onLoginSuccess?()
    }
}
