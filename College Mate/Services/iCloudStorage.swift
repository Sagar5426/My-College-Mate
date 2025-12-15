import Foundation
import Combine

@propertyWrapper
struct iCloudStorage<Value> {
    private let key: String
    private let defaultValue: Value
    private let store = NSUbiquitousKeyValueStore.default
    private let publisher = PassthroughSubject<Value, Never>()
    private var observer: AnyObject? // Holds the notification observer token

    init(wrappedValue: Value, _ key: String) {
        self.defaultValue = wrappedValue
        self.key = key
        
        // We use the block-based observer API, which does not need '@objc' or '#selector'.
        self.observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store,
            queue: .main // Ensure updates happen on the main thread
        ) { [self] notification in
            guard let userInfo = notification.userInfo,
                  let changedKeys = userInfo[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String],
                  changedKeys.contains(key) else {
                return
            }
            
            // Fetch the new value from the store
            let newValue = (store.object(forKey: key) as? Value) ?? defaultValue
            publisher.send(newValue) // Notify local subscribers
        }
        
    }

    var wrappedValue: Value {
        get {
            // Get the value from the iCloud store, or use the default
            (store.object(forKey: key) as? Value) ?? defaultValue
        }
        set {
            // Save the new value to the iCloud store
            store.set(newValue, forKey: key)
            store.synchronize() // Start the sync process
            publisher.send(newValue) // Notify local observers
        }
    }

    var projectedValue: AnyPublisher<Value, Never> {
        publisher.eraseToAnyPublisher()
    }
}

// MARK: - Extensions for specific types

// Extension to support Data (for profile image)
extension iCloudStorage where Value == Data? {
    init(wrappedValue: Data?, _ key: String) {
        self.defaultValue = wrappedValue
        self.key = key
        
        // Use the same block-based observer
        self.observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store,
            queue: .main
        ) { [self] notification in
            guard let userInfo = notification.userInfo,
                  let changedKeys = userInfo[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String],
                  changedKeys.contains(key) else {
                return
            }
            let newValue = (store.object(forKey: key) as? Value) ?? defaultValue
            publisher.send(newValue)
        }
        
    }
}

// Extension to support Date (for userDob)
extension iCloudStorage where Value == Date {
    init(wrappedValue: Date, _ key: String) {
        self.defaultValue = wrappedValue
        self.key = key
        
        // Use the same block-based observer
        self.observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store,
            queue: .main
        ) { [self] notification in
            guard let userInfo = notification.userInfo,
                  let changedKeys = userInfo[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String],
                  changedKeys.contains(key) else {
                return
            }
            let newValue = (store.object(forKey: key) as? Value) ?? defaultValue
            publisher.send(newValue)
        }
    }

    var wrappedValue: Date {
        get {
            (store.object(forKey: key) as? Date) ?? defaultValue
        }
        set {
            store.set(newValue, forKey: key)
            store.synchronize()
            publisher.send(newValue)
        }
    }
}

// Extension to support RawRepresentable (for Gender enum)
extension iCloudStorage where Value: RawRepresentable {
    init(wrappedValue: Value, _ key: String) {
        self.defaultValue = wrappedValue
        self.key = key
        
        // Use the same block-based observer
        self.observer = NotificationCenter.default.addObserver(
            forName: NSUbiquitousKeyValueStore.didChangeExternallyNotification,
            object: store,
            queue: .main
        ) { [self] notification in
            guard let userInfo = notification.userInfo,
                  let changedKeys = userInfo[NSUbiquitousKeyValueStoreChangedKeysKey] as? [String],
                  changedKeys.contains(key) else {
                return
            }
            
            guard let rawValue = store.object(forKey: key) as? Value.RawValue else {
                publisher.send(defaultValue)
                return
            }
            let newValue = Value(rawValue: rawValue) ?? defaultValue
            publisher.send(newValue)
        }
    }

    var wrappedValue: Value {
        get {
            guard let rawValue = store.object(forKey: key) as? Value.RawValue else {
                return defaultValue
            }
            return Value(rawValue: rawValue) ?? defaultValue
        }
        set {
            store.set(newValue.rawValue, forKey: key)
            store.synchronize()
            publisher.send(newValue)
        }
    }
}

