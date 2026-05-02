import SwiftUI

// MARK: - NearbyAddView
// Both devices advertise their profile via BLE and scan for each other.
// When a peer is discovered (profile already read), the user taps "加好友"
// to add them. The add happens on both sides independently since each device
// reads the other's characteristic.

struct NearbyAddView: View {
    let session: SISSession?
    /// Called when the user confirms adding a peer.
    let onAddPeer: (NearbyPeerProfile) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var nearbyService = NearbyFriendService.shared
    @State private var addedIds: Set<String> = []

    var body: some View {
        NavigationStack {
            List {
                // MARK: Status header
                Section {
                    HStack(spacing: 12) {
                        ZStack {
                            Circle()
                                .fill(nearbyService.isActive ? Color.green.opacity(0.15) : Color.secondary.opacity(0.12))
                                .frame(width: 40, height: 40)
                            Image(systemName: nearbyService.isActive
                                  ? "antenna.radiowaves.left.and.right"
                                  : "antenna.radiowaves.left.and.right.slash")
                                .foregroundStyle(nearbyService.isActive ? .green : .secondary)
                        }
                        VStack(alignment: .leading, spacing: 2) {
                            Text(nearbyService.isActive ? "正在搜尋附近的朋友" : "未啟動")
                                .font(.body.weight(.medium))
                            Text("雙方都需要開啟此畫面")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if nearbyService.isActive {
                            ProgressView().controlSize(.small)
                        }
                    }
                    .padding(.vertical, 4)
                }

                // MARK: Discovered peers (profile already read — ready to add)
                let pending = nearbyService.discoveredPeers.filter { !addedIds.contains($0.id) }
                let added   = nearbyService.discoveredPeers.filter {  addedIds.contains($0.id) }

                if !pending.isEmpty {
                    Section("附近的人") {
                        ForEach(pending) { peer in
                            peerRow(peer, isAdded: false)
                        }
                    }
                }

                if !added.isEmpty {
                    Section("已新增") {
                        ForEach(added) { peer in
                            peerRow(peer, isAdded: true)
                        }
                    }
                }

                if nearbyService.isActive && nearbyService.discoveredPeers.isEmpty {
                    Section {
                        HStack {
                            Spacer()
                            VStack(spacing: 8) {
                                Image(systemName: "person.2.slash")
                                    .font(.title2)
                                    .foregroundStyle(.secondary)
                                Text("附近尚未找到朋友\n請確認對方也開啟此畫面")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .multilineTextAlignment(.center)
                            }
                            .padding(.vertical, 16)
                            Spacer()
                        }
                        .listRowBackground(Color.clear)
                    }
                }
            }
            .navigationTitle("附近加好友")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("關閉") {
                        nearbyService.stop()
                        dismiss()
                    }
                }
            }
            .task {
                guard let session else { return }
                let payload = ProfileQRService.makeMutualPayload(
                    userId: session.userId,
                    empNo: session.empNo,
                    displayName: session.userName
                )
                nearbyService.start(profile: payload)
            }
            .onDisappear {
                nearbyService.stop()
            }
        }
    }

    // MARK: - Peer Row

    @ViewBuilder
    private func peerRow(_ peer: NearbyPeerProfile, isAdded: Bool) -> some View {
        HStack(spacing: 12) {
            Circle()
                .fill(AppTheme.accent.opacity(0.15))
                .frame(width: 44, height: 44)
                .overlay {
                    Text(String(peer.displayName.prefix(1)))
                        .font(.headline)
                        .foregroundStyle(AppTheme.accent)
                }

            VStack(alignment: .leading, spacing: 2) {
                Text(peer.displayName).font(.body)
                Text(peer.empNo).font(.caption).foregroundStyle(.secondary)
            }

            Spacer()

            if isAdded {
                Label("已新增", systemImage: "checkmark.circle.fill")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.green)
            } else {
                Button("加好友") {
                    addedIds.insert(peer.id)
                    onAddPeer(peer)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.vertical, 2)
    }
}
