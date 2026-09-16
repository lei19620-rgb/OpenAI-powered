import SwiftUI

struct PrivacyPolicyView: View {
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Study AI Privacy Policy")
                        .font(.largeTitle.bold())
                    Text("Updated September 16, 2026 · Direct API edition")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("Study AI is an independently developed study tool, not an official OpenAI app. AI features use your configured API service and account. No account with the app developer is required.")
                }

                PolicySection(title: "1. Data we process") {
                    PolicyBullet("Study content includes tasks, courses and units, Markdown notes and templates, imported PDFs and Markdown files, OCR text, Pencil annotations, assignments, answers, scores, and explanations.")
                    PolicyBullet("Settings include appearance, alarm device, overdue policy, default template, iCloud preference, and the status of task actions, alarms, notifications, and Reminders synchronization.")
                    PolicyBullet("Files are imported only when you select them in the system file picker. This version does not access contacts, location, camera, microphone, or your photo library.")
                }

                PolicySection(title: "2. How data is used") {
                    PolicyBullet("To display, search, edit, and save study content on your device.")
                    PolicyBullet("To extract PDF text, perform OCR, extract questions, and grade objective questions on your device.")
                    PolicyBullet("To schedule alarms and local notifications according to your task configuration, including steps that require your action.")
                    PolicyBullet("With permission, to sync actionable steps to Apple Reminders, mark them complete when finished in the app, and remove overdue reminders.")
                    PolicyBullet("When enabled, to sync through a private Apple CloudKit database across devices using the same Apple Account.")
                }

                PolicySection(title: "3. Storage and iCloud") {
                    Text("This edition defaults to local storage and uses a separate CloudKit container. Once provisioned, iCloud can be enabled in Settings and takes effect on the next launch. AI records are study data; API keys stay in this device’s Keychain. Disabling sync does not delete existing cloud copies.")
                    Text("Private CloudKit data is accessible to the current user and counts toward their iCloud storage. Apple states that private data is not visible in the developer portal.")
                    Link("Apple CloudKit private database documentation", destination: URL(string: "https://developer.apple.com/documentation/cloudkit/ckcontainer/privateclouddatabase")!)
                }

                PolicySection(title: "4. Permissions") {
                    PolicyBullet("Notifications support actionable tasks, study reminders, and follow-up reminders. Other study features remain available if permission is denied.")
                    PolicyBullet("Alarm access schedules alarms through AlarmKit on physical devices. Authorization is managed by the operating system. The app cannot guarantee an alarm will sound under every condition.")
                    PolicyBullet("Full Reminders access is used to create, update, complete, and delete app-managed task reminders. They are not uploaded to a developer server.")
                    PolicyBullet("Files are accessed through the system document picker for the PDFs, Markdown files, assignments, or templates you select. No persistent library-wide permission is requested.")
                }

                PolicySection(title: "5. Third parties, ads, and tracking") {
                    Text("The app has no ads, third-party analytics SDKs, cross-app tracking, or developer-operated server, and does not sell study data. AI requests go directly to the endpoint you approve, defaulting to the official OpenAI API. A custom endpoint receives the selected text and authentication key. Dictionary lookup is offline.")
                    Text("Before sending, the app shows the selected text, model, and output limit. Only approved text and fixed teaching instructions are sent, not entire PDFs, other notes, or full history. Requests use store=false, which does not mean zero service retention. Canceling a sent request may still incur charges.")
                    Link("OpenAI data controls", destination: URL(string: "https://developers.openai.com/api/docs/guides/your-data")!)
                    Link("Apple Privacy Policy", destination: URL(string: "https://www.apple.com/legal/privacy/en-ww/")!)
                }

                PolicySection(title: "6. Retention, deletion, and withdrawal") {
                    PolicyBullet("AI records can be deleted from assistant history without deleting appended notes or saved assignments. Local deletion does not delete data retained by a service provider. Remove API keys separately in Settings → AI Service. Keys do not sync through iCloud.")
                    PolicyBullet("Local data remains until you delete the content, reset applicable records, or remove the app. Starting a new assignment attempt preserves previous submissions.")
                    PolicyBullet("Disable iCloud in the app’s Settings to stop subsequent sync on this device. Revoke system permissions in iPhone or iPad Settings.")
                    PolicyBullet("Use your Apple Account’s iCloud storage management to remove existing cloud copies. The developer cannot directly view or delete your private study data on your behalf.")
                }

                PolicySection(title: "7. Security and minors") {
                    Text("The app uses iOS and iPadOS sandboxing, system permissions, and CloudKit protections. No technology guarantees absolute security. Protect your device and Apple Account. The app does not request age or identity information or collect personal profiles from children.")
                }

                PolicySection(title: "8. Updates and contact") {
                    Text("Material changes to features or data handling will be reflected in this policy, with renewed consent where needed. Publisher and support details should be provided on the app’s distribution listing before publication.")
                }
            }
            .frame(maxWidth: 760, alignment: .leading)
            .padding(AppTheme.pagePadding)
            .frame(maxWidth: .infinity)
        }
        .background(AppTheme.pageBackground)
        .navigationTitle("Privacy policy")
        .navigationBarTitleDisplayMode(.inline)
    }
}

private struct PolicySection<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.title3.bold())
            content
                .font(.body)
                .foregroundStyle(.primary)
        }
    }
}

private struct PolicyBullet: View {
    let text: String

    init(_ text: String) {
        self.text = text
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("•")
            Text(text)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
