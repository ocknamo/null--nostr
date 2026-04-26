import SwiftUI
import PhotosUI

/// プロフィール編集シート — Mirrors Android EditProfileModal composable.
/// Usage: .sheet(isPresented:) { EditProfileSheet(profile:repository:onSave:onDismiss:) }
struct EditProfileSheet: View {
    let profile:    UserProfile
    let repository: NostrRepository?   // 画像アップロード用 (nil = アップロード無効)
    let onSave:     (UserProfile) -> Void
    let onDismiss:  () -> Void

    @State private var name:     String
    @State private var about:    String
    @State private var picture:  String
    @State private var banner:   String
    @State private var nip05:    String
    @State private var lud16:    String
    @State private var website:  String
    @State private var birthday: String

    @State private var pickerItem:        PhotosPickerItem? = nil
    @State private var bannerPickerItem:  PhotosPickerItem? = nil
    @State private var isUploadingPicture = false
    @State private var isUploadingBanner  = false
    @State private var uploadError:        String? = nil

    @Environment(\.nuruTheme) private var theme

    private var isUploading: Bool { isUploadingPicture || isUploadingBanner }

    init(profile: UserProfile, repository: NostrRepository? = nil, onSave: @escaping (UserProfile) -> Void, onDismiss: @escaping () -> Void) {
        self.profile    = profile
        self.repository = repository
        self.onSave     = onSave
        self.onDismiss  = onDismiss
        _name     = State(initialValue: profile.name     ?? "")
        _about    = State(initialValue: profile.about    ?? "")
        _picture  = State(initialValue: profile.picture  ?? "")
        _banner   = State(initialValue: profile.banner   ?? "")
        _nip05    = State(initialValue: profile.nip05    ?? "")
        _lud16    = State(initialValue: profile.lud16    ?? "")
        _website  = State(initialValue: profile.website  ?? "")
        _birthday = State(initialValue: profile.birthday ?? "")
    }

    var body: some View {
        VStack(spacing: 0) {
            // Navigation bar
            HStack {
                Button("キャンセル", action: onDismiss)
                    .font(NuruFont.bodyMedium())
                    .foregroundStyle(theme.textSecondary)

                Spacer()

                Text("プロフィール編集")
                    .font(NuruFont.bodyMedium())
                    .fontWeight(.bold)
                    .foregroundStyle(theme.textPrimary)

                Spacer()

                Button {
                    saveProfile()
                } label: {
                    if isUploading {
                        ProgressView().tint(NuruColors.lineGreen).scaleEffect(0.8)
                    } else {
                        Text("保存")
                            .font(NuruFont.bodyMedium())
                            .fontWeight(.bold)
                            .foregroundStyle(NuruColors.lineGreen)
                    }
                }
                .disabled(isUploading)
            }
            .padding(.horizontal, NuruSpacing.space4)
            .frame(height: 56)

            Divider().background(theme.borderColor)

            // Form
            ScrollView {
                VStack(alignment: .leading, spacing: NuruSpacing.space4) {
                    profileField("名前", text: $name, placeholder: "表示名")
                    imageField(label: "アイコン画像",
                               urlBinding: $picture,
                               pickerBinding: $pickerItem,
                               isUploading: isUploadingPicture)
                    imageField(label: "バナー画像",
                               urlBinding: $banner,
                               pickerBinding: $bannerPickerItem,
                               isUploading: isUploadingBanner)
                    profileField("自己紹介", text: $about, placeholder: "自己紹介", axis: .vertical, minHeight: 80)
                    profileField("NIP-05", text: $nip05, placeholder: "name@example.com")
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    profileField("ライトニングアドレス", text: $lud16, placeholder: "you@wallet.com")
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    profileField("ウェブサイト", text: $website, placeholder: "https://example.com")
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                    VStack(alignment: .leading, spacing: 4) {
                        profileField("誕生日", text: $birthday, placeholder: "MM-DD または YYYY-MM-DD")
                        Text("例: 01-15 または 2000-01-15")
                            .font(NuruFont.labelSmall())
                            .foregroundStyle(theme.textTertiary)
                    }

                    Spacer(minLength: 40)
                }
                .padding(NuruSpacing.space4)
            }
        }
        .background(theme.bgPrimary)
        .overlay(alignment: .bottom) {
            if let error = uploadError {
                Text(error)
                    .font(NuruFont.labelSmall())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(Color.red.opacity(0.85))
                    .clipShape(RoundedRectangle(cornerRadius: 8))
                    .padding(.bottom, 16)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .onTapGesture { uploadError = nil }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: uploadError)
        .onChange(of: pickerItem) { _, item in
            guard let item else { return }
            Task { await uploadPhoto(item: item, target: .picture) }
        }
        .onChange(of: bannerPickerItem) { _, item in
            guard let item else { return }
            Task { await uploadPhoto(item: item, target: .banner) }
        }
    }

    // MARK: - Field Builders

    @ViewBuilder
    private func profileField(
        _ label: String,
        text: Binding<String>,
        placeholder: String,
        axis: Axis = .horizontal,
        minHeight: CGFloat = 0
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(NuruFont.labelSmall())
                .foregroundStyle(theme.textSecondary)
            TextField(placeholder, text: text, axis: axis)
                .font(.system(size: 14))
                .foregroundStyle(theme.textPrimary)
                .padding(NuruSpacing.space3)
                .frame(minHeight: minHeight == 0 ? nil : minHeight, alignment: .topLeading)
                .background(theme.bgSecondary)
                .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusSm))
                .overlay(
                    RoundedRectangle(cornerRadius: NuruSpacing.radiusSm)
                        .stroke(theme.borderColor.opacity(0.5), lineWidth: 0.5)
                )
        }
    }

    @ViewBuilder
    private func imageField(
        label: String,
        urlBinding: Binding<String>,
        pickerBinding: Binding<PhotosPickerItem?>,
        isUploading: Bool
    ) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(NuruFont.labelSmall())
                .foregroundStyle(theme.textSecondary)
            HStack(spacing: NuruSpacing.space2) {
                TextField("https://...", text: urlBinding)
                    .font(.system(size: 14))
                    .foregroundStyle(theme.textPrimary)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
                    .padding(NuruSpacing.space3)
                    .background(theme.bgSecondary)
                    .clipShape(RoundedRectangle(cornerRadius: NuruSpacing.radiusSm))
                    .overlay(
                        RoundedRectangle(cornerRadius: NuruSpacing.radiusSm)
                            .stroke(theme.borderColor.opacity(0.5), lineWidth: 0.5)
                    )

                PhotosPicker(selection: pickerBinding, matching: .images) {
                    ZStack {
                        RoundedRectangle(cornerRadius: NuruSpacing.radiusSm)
                            .fill(theme.bgTertiary)
                            .frame(width: 44, height: 44)
                        if isUploading {
                            ProgressView().tint(NuruColors.lineGreen).scaleEffect(0.8)
                        } else {
                            Image(systemName: "square.and.arrow.up")
                                .font(.system(size: 18))
                                .foregroundStyle(theme.textPrimary)
                        }
                    }
                }
                .disabled(self.isUploading)
            }
        }
    }

    // MARK: - Helpers

    private func saveProfile() {
        var updated = profile
        updated.name     = name.isEmpty     ? nil : name
        updated.about    = about.isEmpty    ? nil : about
        updated.picture  = picture.isEmpty  ? nil : picture
        updated.banner   = banner.isEmpty   ? nil : banner
        updated.nip05    = nip05.isEmpty    ? nil : nip05
        updated.lud16    = lud16.isEmpty    ? nil : lud16
        updated.website  = website.isEmpty  ? nil : website
        updated.birthday = birthday.isEmpty ? nil : birthday
        onSave(updated)
    }

    private enum UploadTarget { case picture, banner }

    private func uploadPhoto(item: PhotosPickerItem, target: UploadTarget) async {
        switch target {
        case .picture: isUploadingPicture = true
        case .banner:  isUploadingBanner  = true
        }
        uploadError = nil

        defer {
            switch target {
            case .picture: isUploadingPicture = false
            case .banner:  isUploadingBanner  = false
            }
        }

        guard let data = try? await item.loadTransferable(type: Data.self),
              !data.isEmpty else {
            uploadError = "画像の読み込みに失敗しました"
            return
        }

        guard let repo = repository else {
            uploadError = "アップロードが利用できません"
            return
        }

        let server        = await repo.prefs.uploadServerEnum
        let signer        = await repo.signer
        let uploadService = ImageUploadService(signer: signer)
        let compressed    = uploadService.compressImage(data: data, maxSize: 1920, quality: 0.85)

        do {
            let url = try await uploadService.uploadImage(
                imageData:  compressed,
                server:     server
            )
            switch target {
            case .picture: picture = url
            case .banner:  banner  = url
            }
        } catch {
            uploadError = error.localizedDescription
        }
    }
}
