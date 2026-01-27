import UIKit
import Social
import SwiftUI
import SwiftData

class ShareViewController: UIViewController {

    override func viewDidLoad() {
        super.viewDidLoad()

        // --- MODIFICATION 1: Get ALL attachments ---
        // We now loop through all input items and all attachments
        // and collect them into an array.
        let attachments: [NSItemProvider] = {
            guard let inputItems = extensionContext?.inputItems as? [NSExtensionItem] else { return [] }
            // Use flatMap to collect all attachments from all items
            return inputItems.flatMap { $0.attachments ?? [] }
        }()
        
        // --- MODIFICATION 2: Check if the array is empty ---
        guard !attachments.isEmpty else {
            self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
            return
        }

        // --- MODIFICATION 3: Pass the whole array to ShareView ---
        // The argument is now 'attachments' (plural)
        let shareView = ShareView(attachments: attachments) {
            // This is the completion handler. When the user taps "Save" in our SwiftUI view,
            // this code will run to close the extension.
            self.extensionContext?.completeRequest(returningItems: [], completionHandler: nil)
        }

        // Embed the SwiftUI view within a UIHostingController.
        let hostingController = UIHostingController(rootView: shareView)
                
                // 1. Add the hosting controller as a child
                self.addChild(hostingController)
                self.view.addSubview(hostingController.view)
                
                // 2. ENABLE AUTO LAYOUT (Crucial for iPad)
                hostingController.view.translatesAutoresizingMaskIntoConstraints = false
                
                // 3. PIN EDGES TO PARENT VIEW
                NSLayoutConstraint.activate([
                    hostingController.view.topAnchor.constraint(equalTo: self.view.topAnchor),
                    hostingController.view.bottomAnchor.constraint(equalTo: self.view.bottomAnchor),
                    hostingController.view.leadingAnchor.constraint(equalTo: self.view.leadingAnchor),
                    hostingController.view.trailingAnchor.constraint(equalTo: self.view.trailingAnchor)
                ])
                
                // 4. Notify child moved
                hostingController.didMove(toParent: self)
    }
}
