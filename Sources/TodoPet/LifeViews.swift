import SwiftUI

/// Fullness, dirt, growth and streak at a glance, under the board header.
struct LifeBar: View {
    @ObservedObject var life: PetLife
    @ObservedObject var state: BoardState

    var body: some View {
        let s = life.state
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 10) {
                HStack(spacing: 4) {
                    Text("🍙").fixedSize()
                    ProgressView(value: s.satiety, total: 100)
                        .tint(s.satiety < 30 ? .red : (s.satiety < 60 ? .orange : .green))
                        .frame(width: 44)
                    Text("\(Int(s.satiety))%").font(.caption2.monospacedDigit()).foregroundColor(.secondary).fixedSize()
                }
                .help(L("Độ no: mỗi việc xong +25%, đói dần trong giờ làm", "Fullness: +25% per finished task, drops during work hours"))
                if s.dirt > 0 {
                    Text("🪰 ×\(s.dirt)").font(.caption).foregroundColor(.brown)
                        .help(L("Bẩn sau những ngày không làm gì; mỗi việc xong tắm sạch 1 lớp", "Dirty after lazy days; each finished task washes one layer off"))
                }
                if s.streak > 0 {
                    Text("🔥 \(s.streak)").font(.caption.bold())
                        .help(L("Chuỗi ngày làm việc có ít nhất 1 việc xong (ngày nghỉ, ngày tắt máy không tính)",
                                "Workdays in a row with at least one task done (days off and days the Mac was off don't count)"))
                }
                if s.snacks > 0 {
                    Text(String(repeating: "🍪", count: s.snacks)).font(.caption)
                        .help(L("Bánh dự phòng: lỡ một ngày làm việc thì 1 bánh giữ chuỗi cho bạn. Ngày đạt mục tiêu được thêm bánh (tối đa \(LifeRules.maxSnacks)).",
                                "Spare snacks: a missed workday eats one instead of your streak. Goal days add one (up to \(LifeRules.maxSnacks))."))
                }
                Spacer()
                Button {
                    state.showWishes = true
                } label: {
                    Text(L("✨ Xin vía", "✨ Wishes")).font(.caption)
                }
                .buttonStyle(.borderless)
                .help(L("Những điều bạn muốn đạt được", "The things you want to achieve"))
                Button {
                    state.wardrobe = true
                } label: {
                    Text(L("👗 Tủ đồ", "👗 Wardrobe")).font(.caption)
                }
                .buttonStyle(.borderless)
            }
            HStack(spacing: 6) {
                Text("⭐ \(s.stage.name)").font(.caption.bold())
                if let next = s.stage.nextXP {
                    let base = Stage.thresholds[s.stage.rawValue]
                    ProgressView(value: Double(s.xp - base), total: Double(next - base)).tint(.yellow)
                    Text("\(s.xp)/\(next) XP").font(.caption2.monospacedDigit()).foregroundColor(.secondary)
                } else {
                    Text("\(s.xp) XP · MAX").font(.caption2.monospacedDigit()).foregroundColor(.secondary)
                    Spacer()
                }
            }
            if let r = LifeRules.activeRepair(s) {
                let done = min(s.dayCompleted, LifeRules.repairTasks)
                Text("🔧 " + (r.restoredFrom != nil
                    ? L("Đã nối lại chuỗi \(s.streak) ngày!", "Your \(s.streak)-day streak is back!")
                    : L("Nối lại chuỗi \(r.streak) ngày: xong \(done)/\(LifeRules.repairTasks) việc hôm nay", "Mend your \(r.streak)-day streak: \(done)/\(LifeRules.repairTasks) tasks today")))
                    .font(.caption2).foregroundColor(.orange)
            }
            if s.distractionTotal >= 60 {
                let top = s.distraction.sorted { $0.value > $1.value }.prefix(3)
                    .map { "\($0.key) \(Int($0.value / 60))'" }.joined(separator: " · ")
                Text("👀 " + L("Xao nhãng hôm nay: ", "Distracted today: ") + top)
                    .font(.caption2).foregroundColor(.orange)
            }
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 8)
    }
}

/// Accessories to wear and the pet's achievements.
struct WardrobeView: View {
    @ObservedObject var life: PetLife
    @ObservedObject var state: BoardState
    let mood: Mood

    var body: some View {
        let s = life.state
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button { state.wardrobe = false } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.borderless)
                Text(L("Tủ đồ & thành tích", "Wardrobe & achievements")).font(.headline)
            }
            HStack(alignment: .center, spacing: 12) {
                TimelineView(.animation(minimumInterval: 1.0 / 20)) { tl in
                    Canvas { ctx, size in
                        var pose = PetPose(mood: mood == .sleeping ? .normal : mood, t: tl.date.timeIntervalSinceReferenceDate)
                        pose.decorate(s)
                        PetArt.draw(&ctx, size: size, pose: pose)
                    }
                }
                .frame(width: 96, height: 96)
                VStack(alignment: .leading, spacing: 3) {
                    stat("⭐", L("Giai đoạn", "Stage"), "\(s.stage.name) · \(s.xp) XP")
                    stat("✅", L("Việc đã xong", "Tasks done"), "\(s.totalDone)")
                    stat("🔥", L("Chuỗi ngày", "Streak"), L("\(s.streak) (kỷ lục \(s.bestStreak))", "\(s.streak) (best \(s.bestStreak))"))
                    stat("⚡️", L("Combo cao nhất", "Best combo"), "×\(s.bestCombo)")
                    stat("🍰", L("Bánh vàng hiếm", "Golden treats"), "\(s.goldens)")
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(L("Sổ sticker — ngày làm trọn kế hoạch: \(s.perfectDays.count)", "Sticker book — perfect days: \(s.perfectDays.count)"))
                    .font(.caption.bold()).foregroundColor(.secondary)
                if s.perfectDays.isEmpty {
                    Text(L("Làm xong hết kế hoạch một ngày để nhận sticker 🌟 đầu tiên.", "Finish a whole day's plan to earn your first 🌟 sticker."))
                        .font(.caption).foregroundColor(.secondary)
                } else {
                    Text(s.perfectDays.suffix(14).map { _ in "🌟" }.joined())
                        .font(.system(size: 16))
                        .help(s.perfectDays.suffix(14).joined(separator: ", "))
                }
            }
            Divider()
            ForEach(Accessory.allCases) { a in
                let owned = s.unlocked.contains(a.rawValue)
                let worn = s.wearing.contains(a.rawValue)
                HStack(spacing: 10) {
                    Text(a.emoji).font(.title3).opacity(owned ? 1 : 0.3)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(a.name).font(.callout.weight(.semibold)).foregroundColor(owned ? .primary : .secondary)
                        Text(owned ? L("Đã mở khoá", "Unlocked") : "🔒 " + a.requirement)
                            .font(.caption2).foregroundColor(.secondary)
                    }
                    Spacer()
                    if owned {
                        Button(worn ? L("Cởi ra", "Take off") : L("Đeo", "Wear")) { life.toggle(a) }
                            .buttonStyle(PillButtonStyle(primary: !worn))
                    }
                }
            }
        }
        .padding(14)
    }

    private func stat(_ icon: String, _ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(icon).font(.caption)
            Text(label + ":").font(.caption).foregroundColor(.secondary)
            Text(value).font(.caption.weight(.semibold))
        }
    }
}
