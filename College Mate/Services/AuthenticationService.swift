import Foundation
import Combine

// 1. Mark the entire class as @MainActor
// This ensures ALL property updates happen on the main thread automatically.
@MainActor
class AuthenticationService: ObservableObject {
    
    private static let isLoggedInKey = "isLoggedIn"
    
    @Published var isLoggedIn: Bool {
        didSet {
            UserDefaults.standard.set(isLoggedIn, forKey: Self.isLoggedInKey)
        }
    }
    
    init() {
        self.isLoggedIn = UserDefaults.standard.bool(forKey: Self.isLoggedInKey)
    }
    
    func login() {
        isLoggedIn = true
    }
    
    func logout() {
        isLoggedIn = false
    }
}
