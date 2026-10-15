import SwiftUI

enum AppUpdateCopy {
    static func upToDate(_ version: String) -> String {
        "已是最新版本 \(version)。"
    }

    static func failure(_ reason: AppUpdateFailure) -> String {
        switch reason {
        case .unparseableCurrentVersion:
            return "当前版本号无法识别。"
        case .feedUnavailable:
            return "无法连接更新服务。请稍后再试。"
        case .noStableRelease:
            return "没有找到可用的发布版本。"
        case .missingDiskImage:
            return "最新版本没有可安装的磁盘映像。"
        case .missingChecksum:
            return "最新版本没有校验文件，已取消更新。"
        case .untrustedAssetUrl:
            return "更新地址不受信任，已取消更新。"
        case .checksumUnavailable:
            return "无法读取更新校验。"
        case .invalidChecksum:
            return "更新校验无效，已取消更新。"
        }
    }

    static func installFailure(_ failure: AppUpdateInstallFailure) -> String {
        switch failure {
        case .untrustedURL:
            return "更新地址不受信任，已取消更新。"
        case .downloadFailed:
            return "下载更新失败。"
        case .checksumMismatch:
            return "安装包校验失败，已取消更新。"
        case .mountFailed(let published):
            return published
                ? "无法打开更新磁盘映像。已下载的安装包放在「下载」中。"
                : "无法打开更新磁盘映像。"
        case .bundleMissing:
            return "磁盘映像里没有 LumenPDF。"
        case .versionMismatch:
            return "安装包版本与发布版本不一致，已取消更新。"
        case .locationBlocked(let reason, let published):
            return blocked(reason, publishedToDownloads: published)
        case .replaceFailed:
            return "替换当前应用失败，原版本仍保留。"
        case .cancelled:
            return "已取消更新。"
        }
    }

    static func blocked(_ reason: AppInstallBlock, publishedToDownloads: Bool) -> String {
        let location = publishedToDownloads
            ? "已下载的安装包放在「下载」中。"
            : "已保留安装包，但无法把它放入「下载」。"
        switch reason {
        case .diskImage:
            return "当前从只读磁盘映像运行。请先把 LumenPDF 拖到「应用程序」文件夹。\(location)"
        case .translocated:
            return "当前副本由系统隔离运行。请先把 LumenPDF 拖到「应用程序」文件夹。\(location)"
        case .notWritable:
            return "没有权限替换当前位置的 LumenPDF。\(location)可以手动把它拖入「应用程序」。"
        }
    }
}

struct AppUpdateBanner: View {
    @ObservedObject var updates: AppUpdateCenter

    var body: some View {
        if updates.showsBanner, let version = updates.offer?.version {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.circle")
                Text("LumenPDF \(version) 可用")
                    .font(.callout)
                Spacer(minLength: 12)
                Button("稍后", action: updates.deferCurrentOffer)
                    .buttonStyle(.borderless)
                Button("查看", action: updates.presentDetails)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
            .padding(.top, 8)
            .padding(.horizontal, 16)
            .accessibilityIdentifier("update.banner")
        }
    }
}

struct AppUpdateSheet: View {
    @ObservedObject var updates: AppUpdateCenter

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("发现新版本 \(updates.offer?.version ?? "")")
                .font(.title2.weight(.semibold))
            Text("当前版本 \(AppUpdateCenter.currentVersion)")
                .foregroundStyle(.secondary)
            ScrollView {
                Text(notes)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
            .frame(minHeight: 140, maxHeight: 260)
            progress
            if !updates.statusMessage.isEmpty {
                Text(updates.statusMessage)
                    .foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Toggle("启动时检查更新", isOn: $updates.checksOnLaunch)
            HStack {
                Spacer()
                Button("稍后", action: updates.deferCurrentOffer)
                    .disabled(updates.activity == .installing)
                if updates.activity == .downloading {
                    Button("取消", action: updates.cancelInstall)
                }
                Button("立即更新", action: updates.installCurrentOffer)
                    .buttonStyle(.borderedProminent)
                    .disabled(updates.isBusy)
                    .accessibilityIdentifier("update.install")
            }
        }
        .padding(20)
        .frame(width: 480)
    }

    private var notes: String {
        let text = updates.offer?.notes.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return text.isEmpty ? "这个版本没有发布说明。" : text
    }

    @ViewBuilder
    private var progress: some View {
        if updates.activity == .downloading {
            ProgressView(value: updates.downloadFraction) {
                Text("正在下载更新…")
            }
        } else if updates.activity == .installing {
            ProgressView {
                Text("正在替换并重新打开…")
            }
        }
    }
}

struct AppUpdateSettingsPage: View {
    @ObservedObject var updates: AppUpdateCenter

    var body: some View {
        Form {
            Section("当前版本") {
                LabeledContent("版本", value: AppUpdateCenter.currentVersion)
                Toggle("启动时检查更新", isOn: $updates.checksOnLaunch)
                Text("启动后向 GitHub 上的官方发布检查新版本。发现更新后需要确认，才会下载并替换当前应用。")
                    .foregroundStyle(.secondary)
            }

            Section {
                Button(updates.activity == .checking ? "正在检查…" : "检查更新") {
                    updates.checkManually()
                }
                .disabled(updates.isBusy)
                if !updates.statusMessage.isEmpty {
                    Text(updates.statusMessage)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let offer = updates.offer {
                Section("可用更新") {
                    LabeledContent("新版本", value: offer.version)
                    Text(offer.notes.isEmpty ? "这个版本没有发布说明。" : offer.notes)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    if updates.activity == .downloading {
                        ProgressView(value: updates.downloadFraction)
                    }
                    HStack {
                        if updates.activity == .downloading {
                            Button("取消", action: updates.cancelInstall)
                        }
                        Button("立即更新", action: updates.installCurrentOffer)
                            .disabled(updates.isBusy)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle("更新")
    }
}
