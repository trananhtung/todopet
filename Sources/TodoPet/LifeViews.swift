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
                if s.chests > 0 {
                    Button { state.wardrobe = true } label: {
                        Text("🎁 \(s.chests)").font(.caption.bold())
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(Capsule().fill(Color.yellow.opacity(0.25)))
                    }
                    .buttonStyle(.borderless)
                    .help(L("Rương quà đang giữ: xong việc tiếp theo là mở được một rương", "Chests held: your next finished task opens one"))
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

/// Accessories to wear, chests, the sticker book, the home corner and souvenirs.
struct WardrobeView: View {
    @ObservedObject var life: PetLife
    @ObservedObject var state: BoardState
    @ObservedObject var prefs: Prefs
    let mood: Mood

    var body: some View {
        let s = life.state
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button { state.wardrobe = false } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.borderless)
                Text(L("Tủ đồ & thành tích", "Wardrobe & achievements")).font(.headline)
                Spacer()
                Picker("", selection: $prefs.species) {
                    Text("Mochi").tag(Species.mochi)
                    Text("Bảnh Bao").tag(Species.person)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                .help(L("Đổi hình dáng pet; đồ, tuổi và kỷ niệm vẫn giữ nguyên", "Switch your pet's look; outfits, growth and memories stay"))
            }
            ScrollView {
                VStack(alignment: .leading, spacing: 12) {
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
                            stat("📖", L("Tuần này", "This week"), L("\(s.week.done) việc · \(s.week.trips) chuyến đi", "\(s.week.done) tasks · \(s.week.trips) trips"))
                        }
                    }
                    chests(s)
                    stickers(s)
                    section(L("Đồ để mặc", "Things to wear"))
                    ForEach(Accessory.allCases.filter { s.unlocked.contains($0.rawValue) || $0.season == nil
                        || $0.season == SeasonRules.active(on: Date())?.season }) { a in accessoryRow(a, s) }
                    home(s)
                    souvenirs(s)
                }
            }
            .frame(maxHeight: 430)
        }
        .padding(14)
    }

    @ViewBuilder private func chests(_ s: LifeState) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            section(L("Rương quà 🎁", "Chests 🎁"))
            Text(L("Mỗi 30 phút làm việc thật được 1 rương (tối đa \(ChestRules.maxPerDay)/ngày). Xong việc tiếp theo là mở. Đang giữ: \(s.chests)",
                   "A chest for every 30 minutes of real work (up to \(ChestRules.maxPerDay) a day), opened by your next finished task. Held: \(s.chests)"))
                .font(.caption).fixedSize(horizontal: false, vertical: true)
            ProgressView(value: min(s.workSec, ChestRules.everySeconds), total: ChestRules.everySeconds)
                .tint(.yellow)
                .help(L("Tới rương tiếp theo: \(Int((ChestRules.everySeconds - s.workSec) / 60)) phút làm việc",
                        "Next chest in \(Int((ChestRules.everySeconds - s.workSec) / 60)) minutes of work"))
            Text(L("Tỉ lệ: thường 70% (XP hoặc 🍪) · hiếm 25% (đồ mới) · huyền thoại 5% (đồ theo mùa hoặc bánh vàng). Không bán gì cả.",
                   "Odds: common 70% (XP or a 🍪) · rare 25% (a new outfit) · legendary 5% (a seasonal outfit or a golden treat). Nothing is ever sold."))
                .font(.caption2).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            if let season = SeasonRules.active(on: Date()) {
                Text(L("\(season.season.emoji) Đang mùa \(season.season.name): còn \(season.daysLeft) ngày để có đồ theo mùa",
                       "\(season.season.emoji) \(season.season.name) season: \(season.daysLeft) day(s) left for its outfits"))
                    .font(.caption.bold()).foregroundColor(.orange)
            }
        }
    }

    @ViewBuilder private func stickers(_ s: LifeState) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            section(L("Sổ sticker · trang \(s.stickerPage)", "Sticker book · page \(s.stickerPage)"))
            HStack(spacing: 3) {
                ForEach(0..<StickerRules.pageSize, id: \.self) { i in
                    Text(i < StickerRules.pageGifts ? "🎁" : (i < s.pageFilled ? "🌟" : "▫️")).font(.system(size: 15))
                }
            }
            Text(L("\(s.pageFilled)/\(StickerRules.pageSize) · còn \(StickerRules.pageSize - s.pageFilled) ngày làm trọn kế hoạch nữa là đầy trang (+50 XP, +1 🍪)",
                   "\(s.pageFilled)/\(StickerRules.pageSize) · \(StickerRules.pageSize - s.pageFilled) more perfect days fill the page (+50 XP, +1 🍪)"))
                .font(.caption2).foregroundColor(.secondary)
        }
    }

    private func accessoryRow(_ a: Accessory, _ s: LifeState) -> some View {
        let owned = s.unlocked.contains(a.rawValue)
        let worn = s.wearing.contains(a.rawValue)
        return HStack(spacing: 10) {
            Canvas { ctx, size in
                var pose = PetPose(mood: .happy, t: 0.3)
                pose.stageScale = 1
                pose.wearing = [a]
                PetArt.draw(&ctx, size: size, pose: pose)
            }
            .frame(width: 40, height: 40)
            .opacity(owned ? 1 : 0.35)
            VStack(alignment: .leading, spacing: 0) {
                Text(a.name).font(.callout.weight(.semibold)).foregroundColor(owned ? .primary : .secondary)
                Text(owned ? L("Đã có", "Unlocked") : "🔒 " + a.requirement)
                    .font(.caption2).foregroundColor(.secondary)
            }
            Spacer()
            if owned {
                Button(worn ? L("Cởi ra", "Take off") : L("Đeo", "Wear")) { life.toggle(a) }
                    .buttonStyle(PillButtonStyle(primary: !worn))
            }
        }
    }

    @ViewBuilder private func home(_ s: LifeState) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            section(L("Góc nhà 🏠 (\(s.decor.count)/\(Decor.allCases.count))", "Home corner 🏠 (\(s.decor.count)/\(Decor.allCases.count))"))
            Text(L("Pet đan đồ trang trí trong lúc bạn tập trung (một phiên 25 phút được một món). Chọn tối đa 3 món bày ở góc màn hình.",
                   "The pet knits decorations while you focus (a 25-minute session makes one). Pick up to 3 for the corner of your screen."))
                .font(.caption2).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            if s.craft > 0 {
                HStack(spacing: 6) {
                    Text("🧶").font(.caption)
                    ProgressView(value: s.craft).tint(.pink)
                    Text("\(Int(s.craft * 100))%").font(.caption2.monospacedDigit()).foregroundColor(.secondary)
                }
            }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 6), spacing: 6) {
                ForEach(Decor.allCases) { d in
                    let owned = s.decor.contains(d.rawValue)
                    let shown = s.home.contains(d.rawValue)
                    Button {
                        life.toggleHome(d)
                    } label: {
                        Text(owned ? d.emoji : "❔").font(.system(size: 20))
                            .frame(width: 40, height: 36)
                            .background(RoundedRectangle(cornerRadius: 8).fill(shown ? Color.accentColor.opacity(0.22) : Color.primary.opacity(0.05)))
                            .overlay(RoundedRectangle(cornerRadius: 8).stroke(shown ? Color.accentColor : .clear, lineWidth: 1.5))
                    }
                    .buttonStyle(.plain)
                    .disabled(!owned)
                    .help(owned ? d.name + (shown ? L(" (đang bày)", " (on display)") : "") : L("Chưa đan", "Not knitted yet"))
                }
            }
        }
    }

    @ViewBuilder private func souvenirs(_ s: LifeState) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            section(L("Kệ quà lưu niệm 🧳 (\(s.souvenirs.count)/\(TripRules.souvenirs.count))",
                      "Souvenir shelf 🧳 (\(s.souvenirs.count)/\(TripRules.souvenirs.count))"))
            Text(L("Xong hết kế hoạch sớm, pet sẽ xin đi chơi tối đa 2 giờ và mang quà về.",
                   "Finish your plan early and the pet asks to go on a trip for up to 2 hours, then brings back a souvenir."))
                .font(.caption2).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 8), spacing: 4) {
                ForEach(TripRules.souvenirs) { x in
                    let owned = s.souvenirs.contains(x.id)
                    Text(owned ? x.emoji : "·").font(.system(size: 18)).frame(width: 34, height: 30)
                        .background(RoundedRectangle(cornerRadius: 6).fill(Color.primary.opacity(0.05)))
                        .help(owned ? "\(x.itemName) · \(x.placeName)\n\(x.postcardText)" : L("Chưa có", "Not yet"))
                }
            }
        }
    }

    private func section(_ title: String) -> some View {
        Text(title).font(.caption.bold()).foregroundColor(.secondary).padding(.top, 2)
    }

    private func stat(_ icon: String, _ label: String, _ value: String) -> some View {
        HStack(spacing: 4) {
            Text(icon).font(.caption)
            Text(label + ":").font(.caption).foregroundColor(.secondary)
            Text(value).font(.caption.weight(.semibold))
        }
    }
}
