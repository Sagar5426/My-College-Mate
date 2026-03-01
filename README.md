# 🎓 College Mate

A focused study companion for college students — built with **SwiftUI**, **SwiftData**, and native Apple frameworks. Track attendance with the 75% rule in mind, keep subject‑wise notes (PDFs & images), and manage your weekly timetable — all in a clean, fast, and delightful interface.

---

## ✨ Highlights

- 📚 Subject management with an intuitive, card‑based UI
- ✅ Attendance tracking designed around the 75% requirement
- 🖼️ Notes that accept PDFs and images (from Photos or Files)
- 🗓️ Simple timetable view for your weekly schedule
- ⚡️ Fast, minimal design focused on what matters

> Personal project turned daily essential — made by a student for students.

---

## 🧠 Why I Built This

Two everyday pain points inspired College Mate:

1. Checking attendance was slow and frustrating — yet essential to meet the 75% rule.
2. Important study notes (screenshots/PDFs) got buried among unrelated photos.

College Mate solves this by:
- Providing a fast, clean UI to track attendance per subject
- Storing only subject‑relevant images and PDFs
- Keeping everything organized in a beautiful, distraction‑free layout

---

## 📸 Screenshots

### 🏠 Home Screen
<img width="220" alt="Simulator Screenshot - iPhone 17 Pro - 2026-02-28 at 01 26 46" src="https://github.com/user-attachments/assets/410ba175-1ef7-48b1-ba6f-f3651c813d1b" />
<img width="220" alt="Simulator Screenshot - iPhone 17 Pro - 2026-02-28 at 01 26 55" src="https://github.com/user-attachments/assets/6c763191-4034-448d-b9bf-f08afe0a885a" />
<img width="220" alt="Simulator Screenshot - iPhone 17 Pro - 2026-02-28 at 01 27 01" src="https://github.com/user-attachments/assets/18f755c6-4c35-4d92-965b-ef1710b93b98" />

<img width="220" alt="Screenshot 2025-10-29 at 11 15 29 PM" src="https://github.com/user-attachments/assets/bedc08ad-2633-44dd-9387-ff1a8786d963" />
<img width="220" alt="Screenshot 2025-10-29 at 11 17 21 PM" src="https://github.com/user-attachments/assets/8a833850-83ea-4f15-8e80-aec675f55d7a" />
<img width="220" alt="Screenshot 2025-10-29 at 11 17 28 PM" src="https://github.com/user-attachments/assets/0a18b0e2-67bb-4a62-91f9-8b0c50e493b3" />

### 📝 Daily Log View
<img width="220" alt="Simulator Screenshot - iPhone 17 Pro - 2026-02-28 at 01 43 03" src="https://github.com/user-attachments/assets/3a8289eb-06dc-46ca-bee3-e6eb3d74f4e2" />
<img width="220" alt="Simulator Screenshot - iPhone 17 Pro - 2026-02-28 at 01 31 53" src="https://github.com/user-attachments/assets/63b857ba-0f07-4cd9-bfcd-2e4245c4fdbd" />

### 📅 Timetable View

<img width="220" alt="Timetable" src="https://github.com/user-attachments/assets/228f53b0-2e11-43ce-8fa9-16e47f577bfd" />

### 👤 Profile & Attendance History

<img width="220" alt="Profile 1" src="https://github.com/user-attachments/assets/ad3a7cc1-3cf3-4b82-bd1c-268fff094dde" />
<img width="220" alt="Profile 2" src="https://github.com/user-attachments/assets/c38cfe97-9d0a-4e29-99c2-5c99cc634f42" />
<img width="220" alt="Profile 3" src="https://github.com/user-attachments/assets/60c9800c-2d33-4a6b-ba2b-3288e75a633a" />
<img width="220" alt="Profile 4" src="https://github.com/user-attachments/assets/815da267-ece6-411b-8f1c-11a922d28ca1" />

### 📝 Notes View
<img  width="220" alt="Simulator Screenshot - iPhone 17 Pro - 2026-02-28 at 01 35 26" src="https://github.com/user-attachments/assets/fcf0ffbf-476a-451b-92c0-4dbc67321456" />


### Dynamic Island: Live Activity

<img width="220" alt="Simulator Screenshot - iPhone 17 Pro - 2026-02-28 at 01 37 24" src="https://github.com/user-attachments/assets/4926ddf7-b5df-48bd-bce4-14a5dc41a6e0" />
<img width="220" alt="Simulator Screenshot - iPhone 17 Pro - 2026-02-28 at 01 38 43" src="https://github.com/user-attachments/assets/cc455033-d076-40f6-a1c6-151298dbb5b1" />
<img width="220" alt="Simulator Screenshot - iPhone 17 Pro - 2026-02-28 at 01 39 17" src="https://github.com/user-attachments/assets/0398c929-df29-4363-878f-538f47edf4a6" />
<img width="220" alt="Simulator Screenshot - iPhone 17 Pro - 2026-02-28 at 01 42 38" src="https://github.com/user-attachments/assets/ebc6d80a-bc66-4405-b8d4-941e50953552" />

---

## 🎥 Demo

- iPhone Simulator (full demo except Notes view):
  - 🔗 https://github.com/user-attachments/assets/c2967243-07c9-4cc7-98ca-bd228efafa66
- iPhone 15 (Notes view only):
  - 🔗 https://github.com/user-attachments/assets/f48304cc-0374-43d3-83c2-44b507310598

---

## 🧱 Tech Stack

- **SwiftUI** — Declarative UI
- **SwiftData** — Local persistence (CloudKit sync planned)
- **PDFKit** — Displaying PDFs
- **PhotosUI** — Image picking
- **UniformTypeIdentifiers (UTType)** — File type handling

> Targeting iOS 17+ (SwiftData). Built with Xcode 15+.

---

## 🔒 Data & Privacy

- Notes and attendance data are stored locally on‑device.
- Only subject‑relevant images/PDFs are imported (from Photos/Files with user consent).
- iCloud sync (Private Database) is planned for cross‑device access.
- No third‑party analytics.

---

## 🚀 Roadmap

- ☁️ iCloud sync across iPhone and iPad (SwiftData + CloudKit)
- 👤 Sign in with Apple (start trial after login)
- 💳 One‑time unlock after a 90‑day free period (StoreKit 2)
- 📥 WhatsApp auto‑import
- 📊 Weekly attendance analytics
- 🔔 Smart alerts for low attendance

If you have feature ideas, please open an issue or start a discussion!

---

## 🛠️ Getting Started

### Requirements
- iOS 17 or later
- Xcode 15 or later

### Build & Run

1. Clone the repository:
   ```bash
   git clone https://github.com/<your-username>/college-mate.git
   cd college-mate
