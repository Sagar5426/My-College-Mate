import SwiftUI
import PhotosUI
import SwiftData

struct ProfileView: View {
    @Binding var isShowingProfileView: Bool
    @Query var subjects: [Subject]
    
    @EnvironmentObject var authService: AuthenticationService
    
    @StateObject private var viewModel = ProfileViewModel()
    
    // State for image selection
    @State private var isShowingPhotoPicker = false
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var isShowingCropper = false
    @State private var imageToCrop: UIImage? = nil
    
    @State private var isSigningOut = false
    
    var body: some View {
        ZStack {
            NavigationStack {
                ZStack {
                    Color(UIColor.systemGroupedBackground).ignoresSafeArea()

                    VStack {
                        Form {
                            ProfileHeaderView(viewModel: viewModel)
                            NotificationsSectionView(viewModel: viewModel)
                            SyncSectionView(viewModel: viewModel)
                            AttendanceHistorySection(viewModel: viewModel)
                        }
                        .scrollContentBackground(.hidden)
                        .background(Color.clear)
                    }
                    .navigationTitle("Profile")
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Close", systemImage: "xmark") {
                                let generator = UIImpactFeedbackGenerator(style: .light)
                                generator.impactOccurred()
                                isShowingProfileView = false
                            }
                        }
                    }
                    .sheet(isPresented: $viewModel.isEditingProfile) {
                        EditProfileView(
                            viewModel: viewModel,
                            isShowingPhotoPicker: $isShowingPhotoPicker,
                            authService: authService,
                            isSigningOut: $isSigningOut
                        )
                    }
                    .sheet(isPresented: $viewModel.isShowingDatePicker) {
                        ProfileDatePickerSheet(viewModel: viewModel)
                    }
                    .onAppear {
                        viewModel.subjects = subjects
                        viewModel.filterAttendanceLogs()
                    }
                    .onChange(of: subjects) {
                        viewModel.subjects = subjects
                        viewModel.filterAttendanceLogs()
                    }
                    .onChange(of: viewModel.selectedFilter) {
                        if viewModel.selectedFilter != .selectDate {
                            viewModel.filterAttendanceLogs()
                        }
                    }
                    .onChange(of: viewModel.selectedSubjectName) { viewModel.filterAttendanceLogs() }
                }
            }
            .photosPicker(isPresented: $isShowingPhotoPicker, selection: $selectedPhoto, matching: .images)
            .onChange(of: selectedPhoto) {
                Task {
                    if let data = try? await selectedPhoto?.loadTransferable(type: Data.self),
                       let uiImage = UIImage(data: data) {
                        imageToCrop = uiImage
                        isShowingCropper = true
                    }
                }
            }
            .fullScreenCover(isPresented: $isShowingCropper) {
                if let imageToCrop {
                    ProfileImageCropperFullScreen(image: imageToCrop, viewModel: viewModel, isPresented: $isShowingCropper)
                }
            }
            .onChange(of: isShowingCropper) {
                if !isShowingCropper {
                    imageToCrop = nil
                    selectedPhoto = nil
                }
            }
            
            if isSigningOut {
                Color.black.opacity(0.4)
                    .ignoresSafeArea()
                    .transition(.opacity.animation(.easeIn(duration: 0.2)))
                
                ProgressView("Signing Out...")
                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                    .padding()
                    .background(Color.black.opacity(0.6))
                    .cornerRadius(10)
                    .foregroundColor(.white)
                    .transition(.opacity.animation(.easeIn(duration: 0.2)))
            }
        }
    }
    
    // MARK: - Subviews

    private struct ProfileHeaderView: View {
        @ObservedObject var viewModel: ProfileViewModel
        
        var body: some View {
            Section {
                Button {
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()
                    viewModel.isEditingProfile = true
                } label: {
                    HStack(spacing: 12) {
                        ProfileImageView(profileImageData: viewModel.profileImageData)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            Text(viewModel.username.isEmpty ? "Your Name" : viewModel.username)
                                .font(.headline)
                                .foregroundColor(.primary)
                            
                            Text(viewModel.collegeName.isEmpty ? "Your College" : viewModel.collegeName)
                                .font(.subheadline)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .center, spacing: 4) {
                            if viewModel.ageCalculated != 0 {
                                Text("\(viewModel.ageCalculated) yrs old").foregroundStyle(.gray).font(.caption)
                            }
                            Text(viewModel.gender.rawValue).foregroundStyle(.gray).font(.caption)
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            .listRowBackground(Color(UIColor.secondarySystemGroupedBackground))
        }
    }

    private struct ProfileImageView: View {
        let profileImageData: Data?
        
        var body: some View {
            if let imageData = profileImageData, let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable().scaledToFill().frame(width: 60, height: 60).clipShape(Circle())
            } else {
                Image(systemName: "person.circle.fill")
                    .resizable().scaledToFill().frame(width: 60, height: 60).foregroundColor(.gray)
            }
        }
    }

    private struct NotificationsSectionView: View {
        @ObservedObject var viewModel: ProfileViewModel
        
        var body: some View {
            Section {
                Toggle(isOn: $viewModel.notificationsEnabled) {
                    Label("Send Notifications", systemImage: "bell")
                }
                .onChange(of: viewModel.notificationsEnabled) {
                    let generator = UIImpactFeedbackGenerator(style: .light)
                    generator.impactOccurred()
                }
                
                if viewModel.notificationsEnabled {
                    Picker("Prior notification time", selection: $viewModel.notificationLeadMinutes) {
                        ForEach(viewModel.leadOptions) { option in
                            Text(option.title).tag(option.rawValue)
                        }
                    }
                    .pickerStyle(.segmented)
                    Text("This sets how long before class you’ll receive a prior notification.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                }
            } header: {
                Text("Notifications")
                    .foregroundColor(.gray)
            }
            .listRowBackground(Color(UIColor.secondarySystemGroupedBackground))
        }
    }

    private struct SyncSectionView: View {
        @ObservedObject var viewModel: ProfileViewModel
        @State private var showSyncInfo = false
        
        var body: some View {
            Section {
                HStack {
                    if viewModel.isSyncing {
                        ProgressView()
                            .padding(.trailing, 4)
                        Text("Syncing Attendance...")
                            .foregroundColor(.secondary)
                    } else {
                        Button(action: {
                            let generator = UIImpactFeedbackGenerator(style: .medium)
                            generator.impactOccurred()
                            
                            viewModel.triggerSync()
                            showSyncInfo = true
                            
                            DispatchQueue.main.asyncAfter(deadline: .now() + 30) {
                                withAnimation {
                                    showSyncInfo = false
                                }
                            }
                        }) {
                            HStack(spacing: 8) {
                                Image(systemName: "arrow.clockwise")
                                Text("Sync Now")
                            }
                        }
                        .buttonStyle(PlainButtonStyle())
                        .foregroundColor(.accentColor)
                    }
                    
                    Spacer()
                    
                    if let lastSyncedTime = viewModel.lastSyncedTime {
                        Text("Last: \(lastSyncedTime, formatter: DateFormatter.shortTime)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text("Ready to sync")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                
                if showSyncInfo {
                    Text("iCloud sync may take a few moments to complete. After pressing the Sync button, close the app and reopen it after about a minute to ensure your data is fully updated.")
                        .font(.footnote)
                        .foregroundColor(.secondary)
                        .padding(.top, 8)
                        .transition(.opacity)
                }
                
            } header: {
                Text("Sync Attendance with iCloud")
                    .foregroundColor(.gray)
            }
            .animation(.easeInOut, value: showSyncInfo)
            .listRowBackground(Color(UIColor.secondarySystemGroupedBackground))
        }
    }

    private struct AttendanceHistorySection: View {
        @ObservedObject var viewModel: ProfileViewModel

        var body: some View {
            Section {
                VStack(alignment: .leading, spacing: 10) {
                    HStack {
                        // LEFT MENU (SUBJECTS)
                        Menu {
                            Button("All Subjects") {
                                let generator = UIImpactFeedbackGenerator(style: .light)
                                generator.impactOccurred()
                                viewModel.selectedSubjectName = "All Subjects"
                            }
                            ForEach(viewModel.subjects, id: \.id) { subject in
                                Button(subject.name) {
                                    let generator = UIImpactFeedbackGenerator(style: .light)
                                    generator.impactOccurred()
                                    viewModel.selectedSubjectName = subject.name
                                }
                            }
                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "book.closed")
                                Text(viewModel.selectedSubjectName)
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                            }
                            .frame(width: 190, alignment: .leading)
                            .foregroundColor(.blue)
                        }
                        
                        Spacer()
                        
                        // RIGHT MENU (DATES)
                        Menu {
                            Button(ProfileViewModel.FilterType.oneDay.rawValue) {
                                let generator = UIImpactFeedbackGenerator(style: .light)
                                generator.impactOccurred()
                                viewModel.selectedFilter = .oneDay
                            }
                            Button(ProfileViewModel.FilterType.sevenDays.rawValue) {
                                let generator = UIImpactFeedbackGenerator(style: .light)
                                generator.impactOccurred()
                                viewModel.selectedFilter = .sevenDays
                            }
                            Button(ProfileViewModel.FilterType.oneMonth.rawValue) {
                                let generator = UIImpactFeedbackGenerator(style: .light)
                                generator.impactOccurred()
                                viewModel.selectedFilter = .oneMonth
                            }
                            Button(ProfileViewModel.FilterType.allHistory.rawValue) {
                                let generator = UIImpactFeedbackGenerator(style: .light)
                                generator.impactOccurred()
                                viewModel.selectedFilter = .allHistory
                            }
                            
                            Divider()
                            Button(ProfileViewModel.FilterType.selectDate.rawValue) {
                                let generator = UIImpactFeedbackGenerator(style: .light)
                                generator.impactOccurred()
                                viewModel.selectedFilter = .selectDate
                                viewModel.isShowingDatePicker = true
                            }

                        } label: {
                            HStack(spacing: 4) {
                                Image(systemName: "calendar")
                                Text(
                                    viewModel.selectedFilter == .selectDate
                                    ? viewModel.selectedDate.formatted(
                                        Date.FormatStyle()
                                            .day(.twoDigits)
                                            .month(.abbreviated)
                                            .year()
                                      )
                                    : viewModel.selectedFilter.rawValue
                                )
                                .lineLimit(1)
                                .truncationMode(.tail)
                                .fixedSize(horizontal: true, vertical: false)

                            }
                            .frame(width: 130, alignment: .trailing)
                            .foregroundColor(.blue)
                        }
                    }
                    .padding(.bottom, 8)

                    if viewModel.filteredLogs.isEmpty {
                        Text("No attendance changes in this period.")
                            .foregroundColor(.gray).padding(.vertical)
                    } else {
                        ForEach(viewModel.filteredLogs) { log in
                            VStack(alignment: .leading, spacing: 4) {
                                HStack {
                                    Text(log.action)
                                    Spacer()
                                    Text(log.timestamp.formatted(date: .abbreviated, time: .shortened))
                                        .font(.caption).foregroundColor(.gray)
                                }
                                Text(log.subjectName)
                                    .font(.caption).foregroundColor(.secondary)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            } header: {
                Text("Attendance History")
                    .foregroundColor(.gray)
            }
            .listRowBackground(Color(UIColor.secondarySystemGroupedBackground))
        }
    }

    private struct EditProfileView: View {
        @ObservedObject var viewModel: ProfileViewModel
        @Binding var isShowingPhotoPicker: Bool
        @ObservedObject var authService: AuthenticationService
        
        @Binding var isSigningOut: Bool
        
        @Environment(\.dismiss) private var dismiss
        
        var body: some View {
            NavigationStack {
                Form {
                    Section {
                        HStack {
                            Spacer()
                            Button(action: {
                                dismiss()
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) {
                                    isShowingPhotoPicker = true
                                }
                            }) {
                                ZStack(alignment: .bottomTrailing) {
                                    if let imageData = viewModel.profileImageData, let uiImage = UIImage(data: imageData) {
                                        Image(uiImage: uiImage)
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 120, height: 120)
                                            .clipShape(Circle())
                                    } else {
                                        Image(systemName: "person.circle.fill")
                                            .resizable()
                                            .scaledToFill()
                                            .frame(width: 120, height: 120)
                                            .foregroundColor(.gray.opacity(0.5))
                                    }

                                    Image(systemName: "camera.circle.fill")
                                        .font(.system(size: 32))
                                        .foregroundColor(.accentColor)
                                        .background(Circle().fill(Color(UIColor.systemGroupedBackground)))
                                        .offset(x: 4, y: 4)
                                }
                            }
                            .padding(.vertical, 16)
                            Spacer()
                        }
                    }
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())

                    Section(header: Text("Basic Information")) {
                        HStack(spacing: 12) {
                            Image(systemName: "person.fill")
                                .foregroundColor(.gray)
                                .frame(width: 20)
                            TextField("Enter your name", text: $viewModel.username)
                                .foregroundColor(.primary)
                                .textInputAutocapitalization(.words)
                        }
                        
                        HStack(spacing: 12) {
                            Image(systemName: "graduationcap.fill")
                                .foregroundColor(.gray)
                                .frame(width: 20)
                            TextField("Enter your college name", text: $viewModel.collegeName)
                                .foregroundColor(.primary)
                                .textInputAutocapitalization(.words)
                        }
                    }

                    Section(header: Text("User Details")) {
                        HStack {
                            Text("Email").foregroundStyle(.secondary)
                            Spacer()
                            TextField("Email", text: $viewModel.email)
                                .multilineTextAlignment(.trailing)
                                .keyboardType(.emailAddress)
                                .textInputAutocapitalization(.never)
                                .autocorrectionDisabled(true)
                        }

                        DatePicker("Date of Birth", selection: $viewModel.userDob, displayedComponents: .date)
                            .foregroundStyle(.secondary)

                        Picker("Gender", selection: $viewModel.gender) {
                            ForEach(ProfileViewModel.Gender.allCases, id: \.self) { genderOption in
                                Text(genderOption.rawValue)
                            }
                        }
                        .foregroundStyle(.secondary)
                    }
                    
                    Section {
                        Button(role: .destructive) {
                            let generator = UIImpactFeedbackGenerator(style: .heavy)
                            generator.impactOccurred()
                            
                            dismiss()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                                withAnimation(.easeIn(duration: 0.2)) {
                                    isSigningOut = true
                                }
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    authService.logout()
                                }
                            }
                        } label: {
                            Text("Sign Out")
                                .fontWeight(.semibold)
                                .frame(maxWidth: .infinity, alignment: .center)
                        }
                    }
                }
                .scrollContentBackground(.hidden)
                .background(Color(UIColor.systemGroupedBackground).ignoresSafeArea())
                .navigationTitle("Edit Profile")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") {
                            let generator = UIImpactFeedbackGenerator(style: .light)
                            generator.impactOccurred()
                            dismiss()
                        }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            let generator = UIImpactFeedbackGenerator(style: .medium)
                            generator.impactOccurred()
                            dismiss()
                        }.bold()
                    }
                }
                .scrollDismissesKeyboard(.interactively)
            }
        }
    }

    // MARK: -DATE PICKER SHEET
    private struct ProfileDatePickerSheet: View {
        @ObservedObject var viewModel: ProfileViewModel

        var body: some View {
            VStack {
                DatePicker(
                    "Select a Date",
                    selection: $viewModel.selectedDate,
                    in: ...Date(),
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .padding()
                .onChange(of: viewModel.selectedDate) {
                    viewModel.filterAttendanceLogs()
                }

                Button {
                    let generator = UIImpactFeedbackGenerator(style: .medium)
                    generator.impactOccurred()

                    viewModel.isShowingDatePicker = false
                } label: {
                    Text("Done")
                        .fontWeight(.semibold)
                        .frame(maxWidth: .infinity)
                }
                .padding()
                .background(Color.blue)
                .foregroundColor(.white)
                .cornerRadius(10)
                .padding(.horizontal)
            }
            .padding(.vertical)
            .presentationDetents([.medium])
        }
    }



    private struct ProfileImageCropperFullScreen: View {
        let image: UIImage
        @ObservedObject var viewModel: ProfileViewModel
        @Binding var isPresented: Bool

        var body: some View {
            ImageCropService(
                image: image,
                onCrop: { cropped in
                    if let data = cropped.jpegData(compressionQuality: 0.5) {
                        viewModel.profileImageData = data
                    }
                },
                isPresented: $isPresented
            )
            .ignoresSafeArea()
        }
    }
}

#Preview {
    ProfileView(isShowingProfileView: .constant(true))
        .modelContainer(for: Subject.self, inMemory: true)
        .environmentObject(AuthenticationService())
        .preferredColorScheme(.dark)
}

extension DateFormatter {
    static let shortTime: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()
}
