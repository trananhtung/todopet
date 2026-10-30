import Foundation

// The little game around your work: chests for real work time, seasonal outfits, things the pet knits while you
// focus, a trip once the plan is done, and weekly chapters. Rewards are cosmetic and never sold; the odds are shown.
// Random rewards motivate finishing more than fixed ones (Shen, Fishbach & Hsee 2015), and a pet that makes things
// and goes on trips is what Focus Friend and Finch are loved for. All rules here are pure and covered by `--selftest`.

// MARK: - Seasons

enum Season: String, CaseIterable {
    case tet, trungthu, halloween, christmas

    var name: String {
        switch self {
        case .tet: L("Tết", "Tết (Lunar New Year)")
        case .trungthu: L("Trung Thu", "Mid-Autumn")
        case .halloween: "Halloween"
        case .christmas: L("Giáng sinh", "Christmas")
        }
    }

    var emoji: String {
        switch self {
        case .tet: "🧧"
        case .trungthu: "🥮"
        case .halloween: "🎃"
        case .christmas: "🎄"
        }
    }
}

struct ActiveSeason: Equatable {
    var season: Season
    var start: String
    var end: String
    /// Days left after today (0 on the last day).
    var daysLeft: Int
}

enum SeasonRules {
    /// Tết and Trung Thu by the Vietnamese lunar calendar (Hồ Ngọc Đức's algorithm, UTC+7). Outside this table there are
    /// no lunar seasons.
    static let lunar: [Int: (tet: String, trungThu: String)] = [
        2026: ("02-17", "09-25"), 2027: ("02-06", "09-15"), 2028: ("01-26", "10-03"), 2029: ("02-13", "09-22"),
        2030: ("02-02", "09-12"), 2031: ("01-23", "10-01"), 2032: ("02-11", "09-19"),
    ]

    /// Tết: a week either side of the lunar new year. Trung Thu: 3 days either side of the 15th of the 8th month.
    /// Halloween: Oct 20–Nov 1. Christmas: Dec 15–Jan 1.
    static func active(on date: Date) -> ActiveSeason? {
        let today = DayMath.key(date)
        let year = Calendar.current.component(.year, from: date)
        var windows: [(Season, String, String)] = []
        for y in [year - 1, year] {
            if let l = lunar[y] {
                windows.append((.tet, LifeRules.addDays("\(y)-\(l.tet)", -7), LifeRules.addDays("\(y)-\(l.tet)", 7)))
                windows.append((.trungthu, LifeRules.addDays("\(y)-\(l.trungThu)", -3), LifeRules.addDays("\(y)-\(l.trungThu)", 3)))
            }
            windows.append((.halloween, "\(y)-10-20", "\(y)-11-01"))
            windows.append((.christmas, "\(y)-12-15", "\(y + 1)-01-01"))
        }
        guard let w = windows.first(where: { $0.1 <= today && today <= $0.2 }) else { return nil }
        return ActiveSeason(season: w.0, start: w.1, end: w.2, daysLeft: DayMath.daysBetween(today, w.2))
    }
}

// MARK: - Chests

enum ChestTier: String { case common, rare, legendary }

enum ChestReward: Equatable {
    case xp(Int)
    case snack
    case accessory(Accessory)
    case golden
}

struct ChestResult: Equatable {
    var tier: ChestTier
    var reward: ChestReward
    var xp: Int
}

enum ChestRules {
    /// A chest for every 30 minutes of real work: at the Mac, in work hours, not on a distraction, not in a meeting.
    static let everySeconds = 1800.0
    static let maxPerDay = 3
    static let maxHeld = 3
    /// Shown in the wardrobe.
    static let odds: [(ChestTier, Double)] = [(.common, 0.70), (.rare, 0.25), (.legendary, 0.05)]

    /// Counts work time; returns true when it earns a chest.
    static func addWork(_ s: inout LifeState, seconds: Double) -> Bool {
        guard s.chestsToday < maxPerDay, s.chests < maxHeld else { return false }
        s.workSec += seconds
        guard s.workSec >= everySeconds else { return false }
        s.workSec -= everySeconds
        s.chests += 1
        s.chestsToday += 1
        return true
    }

    /// Opens a held chest (when a task is finished). `roll` picks the tier, `pick` the reward within it.
    static func open(_ s: inout LifeState, roll: Double, pick: Double, season: Season?) -> ChestResult? {
        guard s.chests > 0 else { return nil }
        s.chests -= 1
        let tier: ChestTier = roll < 0.70 ? .common : (roll < 0.95 ? .rare : .legendary)
        switch tier {
        case .common:
            if pick < 0.25 && s.snacks < LifeRules.maxSnacks {
                s.snacks += 1
                return ChestResult(tier: tier, reward: .snack, xp: 0)
            }
            s.xp += 20
            return ChestResult(tier: tier, reward: .xp(20), xp: 20)
        case .rare:
            let pool = Accessory.chestPool.filter { !s.unlocked.contains($0.rawValue) }
            if let a = pool.isEmpty ? nil : pool[min(Int(pick * Double(pool.count)), pool.count - 1)] {
                give(&s, a)
                return ChestResult(tier: tier, reward: .accessory(a), xp: 0)
            }
            s.xp += 40
            return ChestResult(tier: tier, reward: .xp(40), xp: 40)
        case .legendary:
            let pool = Accessory.allCases.filter { $0.season != nil && $0.season == season && !s.unlocked.contains($0.rawValue) }
            if let a = pool.isEmpty ? nil : pool[min(Int(pick * Double(pool.count)), pool.count - 1)] {
                give(&s, a)
                return ChestResult(tier: tier, reward: .accessory(a), xp: 0)
            }
            s.xp += 50
            s.goldens += 1
            return ChestResult(tier: tier, reward: .golden, xp: 50)
        }
    }

    /// Todoist couldn't close the task: the chest goes back (an accessory stays, it was already shown).
    static func undo(_ s: inout LifeState, _ r: ChestResult) {
        s.chests = min(maxHeld, s.chests + 1)
        s.xp = max(0, s.xp - r.xp)
        if r.reward == .snack { s.snacks = max(0, s.snacks - 1) }
        if r.reward == .golden { s.goldens = max(0, s.goldens - 1) }
    }

    /// A new accessory goes on if nothing is in its slot.
    static func give(_ s: inout LifeState, _ a: Accessory) {
        guard !s.unlocked.contains(a.rawValue) else { return }
        s.unlocked.append(a.rawValue)
        if !s.wornAccessories.contains(where: { $0.slot == a.slot }) { s.wearing.append(a.rawValue) }
    }
}

// MARK: - Knitting during focus

/// Home decorations the pet knits while you focus.
enum Decor: String, CaseIterable, Identifiable {
    case rug, plant, lamp, cushion, bookshelf, mug, poster, garland, fishbowl, radio, blanket, lantern

    var id: String { rawValue }

    var emoji: String {
        switch self {
        case .rug: "🧶"
        case .plant: "🪴"
        case .lamp: "🪔"
        case .cushion: "🛋️"
        case .bookshelf: "📚"
        case .mug: "☕"
        case .poster: "🖼️"
        case .garland: "🎏"
        case .fishbowl: "🐠"
        case .radio: "📻"
        case .blanket: "🛏️"
        case .lantern: "🏮"
        }
    }

    var name: String {
        switch self {
        case .rug: L("Thảm len", "Knitted rug")
        case .plant: L("Chậu cây", "Potted plant")
        case .lamp: L("Đèn dầu", "Oil lamp")
        case .cushion: L("Ghế nệm", "Cozy couch")
        case .bookshelf: L("Kệ sách", "Bookshelf")
        case .mug: L("Cốc trà", "Tea mug")
        case .poster: L("Tranh treo tường", "Wall picture")
        case .garland: L("Dây cờ cá chép", "Carp streamers")
        case .fishbowl: L("Bể cá", "Fishbowl")
        case .radio: L("Radio cũ", "Old radio")
        case .blanket: L("Giường chăn ấm", "Warm bed")
        case .lantern: L("Đèn lồng", "Lantern")
        }
    }
}

struct CraftDone: Equatable {
    var decor: Decor?
    var xp: Int
}

enum CraftRules {
    /// A distraction during focus drops a few stitches (never the whole thing, unlike apps that kill your tree).
    static let dropped = 0.10
    static let xpPerItem = 30
    static let maxXpPerDay = 90

    /// Knits `seconds` of a focus session: a whole session of 25+ minutes makes one item, a shorter one its share.
    static func knit(_ s: inout LifeState, seconds: Double, sessionMinutes: Int, pick: Double, today: String) -> CraftDone? {
        s.craft += seconds / (Double(max(sessionMinutes, 25)) * 60)
        guard s.craft >= 1 - 1e-6 else { return nil }
        s.craft = 0
        let missing = Decor.allCases.filter { !s.decor.contains($0.rawValue) }
        if !missing.isEmpty {
            let d = missing[min(Int(pick * Double(missing.count)), missing.count - 1)]
            s.decor.append(d.rawValue)
            return CraftDone(decor: d, xp: 0)
        }
        if s.craftXpDay != today {
            s.craftXpDay = today
            s.craftXpToday = 0
        }
        let xp = min(xpPerItem, max(0, maxXpPerDay - s.craftXpToday))
        s.craftXpToday += xp
        s.xp += xp
        return CraftDone(decor: nil, xp: xp)
    }

    /// 30 seconds on a distraction during focus: a few stitches come undone, once per episode.
    static func dropStitches(_ s: inout LifeState) -> Bool {
        guard s.craft > 0 else { return false }
        s.craft = max(0, s.craft - dropped)
        return true
    }
}

// MARK: - Trips

struct Souvenir: Identifiable {
    let id: String
    let emoji: String
    let place: (vi: String, en: String)
    let item: (vi: String, en: String)
    let postcard: (vi: String, en: String)

    var placeName: String { L(place.vi, place.en) }
    var itemName: String { L(item.vi, item.en) }
    var postcardText: String { L(postcard.vi, postcard.en) }
}

struct TripState: Codable, Equatable {
    var start: Date
    var back: Date
    /// The souvenir id of the place it went.
    var place: String
}

struct TripReturn {
    var souvenir: Souvenir
    /// A new souvenir for the shelf (else +20 XP).
    var isNew: Bool
    var xp: Int
    /// Called back before 30 minutes: no souvenir, and the day's trip isn't used up.
    var early: Bool
}

enum TripRules {
    static let maxMinutes = 120.0
    static let souvenirAfterMinutes = 30.0
    /// The offer needs at least this long before work ends.
    static let minMinutesLeft = 60.0

    static let souvenirs: [Souvenir] = [
        Souvenir(id: "hoian", emoji: "🏮", place: ("Hội An", "Hội An"), item: ("Đèn lồng Hội An", "A Hội An lantern"),
                 postcard: ("Phố cổ lên đèn lồng đủ màu, mình thả một chiếc hoa đăng cầu cho bạn làm việc suôn sẻ 🏮",
                            "The old town lit up with lanterns, and I floated one on the river for your good work 🏮")),
        Souvenir(id: "dalat", emoji: "🍓", place: ("Đà Lạt", "Đà Lạt"), item: ("Dâu Đà Lạt", "Đà Lạt strawberries"),
                 postcard: ("Đà Lạt se lạnh, mình hái dâu ở vườn rồi ngồi uống sữa đậu nành nóng 🍓",
                            "Chilly Đà Lạt: I picked strawberries and sipped hot soy milk 🍓")),
        Souvenir(id: "halong", emoji: "🐚", place: ("Hạ Long", "Hạ Long Bay"), item: ("Vỏ sò Hạ Long", "A Hạ Long shell"),
                 postcard: ("Mình chèo kayak giữa mấy hòn đảo đá, nhặt được chiếc vỏ sò đẹp nhất cho bạn 🐚",
                            "I kayaked between the limestone islands and found the prettiest shell for you 🐚")),
        Souvenir(id: "sapa", emoji: "🏔️", place: ("Sa Pa", "Sa Pa"), item: ("Bưu thiếp Fansipan", "A Fansipan postcard"),
                 postcard: ("Ruộng bậc thang vàng óng, mây bay ngang tầm mắt luôn 🏔️",
                            "Golden rice terraces, and clouds at eye level 🏔️")),
        Souvenir(id: "bentre", emoji: "🥥", place: ("Bến Tre", "Bến Tre"), item: ("Kẹo dừa Bến Tre", "Bến Tre coconut candy"),
                 postcard: ("Đi xuồng qua rặng dừa nước, được mời ăn kẹo dừa mới nấu 🥥",
                            "A boat ride under the water palms, and fresh coconut candy 🥥")),
        Souvenir(id: "hanoi", emoji: "☕", place: ("Hà Nội", "Hà Nội"), item: ("Cà phê trứng", "Egg coffee"),
                 postcard: ("Ngồi phố cổ Hà Nội nhâm nhi cà phê trứng, ngắm người qua lại ☕",
                            "Egg coffee in Hà Nội's old quarter, watching the streets go by ☕")),
        Souvenir(id: "saigon", emoji: "🥖", place: ("Sài Gòn", "Sài Gòn"), item: ("Bánh mì Sài Gòn", "A Sài Gòn bánh mì"),
                 postcard: ("Sài Gòn nhộn nhịp quá! Mình xếp hàng mua ổ bánh mì ngon nhất phố 🥖",
                            "Busy Sài Gòn! I queued for the best bánh mì on the street 🥖")),
        Souvenir(id: "hue", emoji: "🍬", place: ("Huế", "Huế"), item: ("Mè xửng Huế", "Huế sesame candy"),
                 postcard: ("Đi thuyền trên sông Hương, nghe ca Huế, nhai mè xửng giòn giòn 🍬",
                            "A boat on the Perfume River, Huế songs and crunchy sesame candy 🍬")),
        Souvenir(id: "phuquoc", emoji: "🦪", place: ("Phú Quốc", "Phú Quốc"), item: ("Ngọc trai Phú Quốc", "A Phú Quốc pearl"),
                 postcard: ("Biển xanh, cát trắng, hoàng hôn đỏ rực. Mình mang về một viên ngọc trai 🦪",
                            "Blue sea, white sand, a red sunset. I brought you a pearl 🦪")),
        Souvenir(id: "kyoto", emoji: "🪭", place: ("Kyoto", "Kyoto"), item: ("Quạt giấy Kyoto", "A Kyoto fan"),
                 postcard: ("Lá phong đỏ rơi đầy đền cổ, yên tĩnh đến lạ 🪭", "Red maple leaves over old temples, so quiet 🪭")),
        Souvenir(id: "seoul", emoji: "🥞", place: ("Seoul", "Seoul"), item: ("Bánh hotteok", "Hotteok pancakes"),
                 postcard: ("Chợ đêm Seoul thơm mùi bánh hotteok nóng hổi 🥞", "Seoul's night market smells of warm hotteok 🥞")),
        Souvenir(id: "bangkok", emoji: "🥭", place: ("Bangkok", "Bangkok"), item: ("Xôi xoài", "Mango sticky rice"),
                 postcard: ("Đi chợ nổi, ăn xôi xoài ngọt lịm 🥭", "A floating market and the sweetest mango sticky rice 🥭")),
        Souvenir(id: "paris", emoji: "🥐", place: ("Paris", "Paris"), item: ("Bánh sừng bò", "A croissant"),
                 postcard: ("Bữa sáng bên sông Seine với bánh sừng bò giòn tan 🥐", "Breakfast by the Seine with a flaky croissant 🥐")),
        Souvenir(id: "bali", emoji: "🌺", place: ("Bali", "Bali"), item: ("Hoa đại Bali", "A Bali frangipani"),
                 postcard: ("Ruộng lúa xanh mướt và hoa đại thơm ngát khắp nơi 🌺", "Green rice fields and frangipani everywhere 🌺")),
        Souvenir(id: "reykjavik", emoji: "🌌", place: ("Reykjavík", "Reykjavík"), item: ("Thiệp cực quang", "An aurora card"),
                 postcard: ("Đêm qua bầu trời nhảy múa ánh xanh của cực quang 🌌", "Last night the sky danced with green aurora 🌌")),
        Souvenir(id: "swiss", emoji: "🧀", place: ("Thuỵ Sĩ", "Switzerland"), item: ("Phô mai Thuỵ Sĩ", "Swiss cheese"),
                 postcard: ("Núi tuyết, đồng cỏ và những chú bò đeo chuông 🧀", "Snowy peaks, meadows and cows with bells 🧀")),
    ]

    static func souvenir(_ id: String) -> Souvenir { souvenirs.first { $0.id == id } ?? souvenirs[0] }

    /// The plan is done, in work hours, an hour or more before work ends, no trip and no "Stay" today.
    static func shouldOffer(planDone: Bool, inWork: Bool, minutesToEnd: Double, today: String, tripDay: String?,
                            declined: String?, away: Bool) -> Bool {
        planDone && inWork && minutesToEnd >= minMinutesLeft && tripDay != today && declined != today && !away
    }

    /// Off it goes, back after two hours at most (never after work ends). It heads for a place whose souvenir is missing.
    static func start(_ s: inout LifeState, now: Date, workEnd: Date, pick: Double) -> TripState {
        let missing = souvenirs.filter { !s.souvenirs.contains($0.id) }
        let pool = missing.isEmpty ? souvenirs : missing
        let place = pool[min(Int(pick * Double(pool.count)), pool.count - 1)]
        let trip = TripState(start: now, back: min(now.addingTimeInterval(maxMinutes * 60), max(now, workEnd)), place: place.id)
        s.trip = trip
        s.tripDay = DayMath.key(now)
        return trip
    }

    /// Back home: a souvenir after 30+ minutes away (or +20 XP if it's already on the shelf).
    static func finish(_ s: inout LifeState, now: Date) -> TripReturn? {
        guard let trip = s.trip else { return nil }
        s.trip = nil
        let place = souvenir(trip.place)
        let minutes = now.timeIntervalSince(trip.start) / 60
        if minutes < souvenirAfterMinutes {
            // A short trip doesn't use up the day's trip.
            s.tripDay = nil
            return TripReturn(souvenir: place, isNew: false, xp: 0, early: true)
        }
        s.week.trips += 1
        if s.souvenirs.contains(place.id) {
            s.xp += 20
            return TripReturn(souvenir: place, isNew: false, xp: 20, early: false)
        }
        s.souvenirs.append(place.id)
        return TripReturn(souvenir: place, isNew: true, xp: 0, early: false)
    }
}

// MARK: - Sticker book and weekly chapters

struct WeekStats: Codable, Equatable {
    /// The week's Monday, "yyyy-MM-dd".
    var key = ""
    var done = 0
    var stickers = 0
    var trips = 0
}

enum WeekRules {
    /// The Monday of `date`'s week.
    static func key(_ date: Date) -> String {
        var cal = Calendar(identifier: .gregorian)
        cal.firstWeekday = 2
        cal.timeZone = .current
        let start = cal.dateInterval(of: .weekOfYear, for: date)?.start ?? date
        return DayMath.key(start)
    }

    /// A new week started: last week is kept for the Monday recap and this week starts at zero.
    static func roll(_ s: inout LifeState, today: Date) {
        let k = key(today)
        guard s.week.key != k else { return }
        if !s.week.key.isEmpty { s.lastWeek = s.week }
        s.week = WeekStats(key: k)
    }
}

enum StickerRules {
    static let pageSize = 10
    /// Every page starts with two gift stickers, so you're never at zero (Nunes & Drèze 2006).
    static let pageGifts = 2

    /// A perfect day's sticker. A full page gives +50 XP and a snack, and a new page starts with its gifts.
    @discardableResult
    static func add(_ s: inout LifeState) -> Bool {
        s.pageFilled += 1
        s.week.stickers += 1
        guard s.pageFilled >= pageSize else { return false }
        s.xp += 50
        s.stickerPage += 1
        s.pageFilled = pageGifts
        if s.snacks < LifeRules.maxSnacks { s.snacks += 1 }
        return true
    }
}
