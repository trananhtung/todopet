import SwiftUI

/// "Xin vía": the things you want to achieve, a blessing from the pet, and one small step at a time.
struct WishesView: View {
    @ObservedObject var store: WishStore
    @ObservedObject var brain: Brain
    @ObservedObject var state: BoardState
    @State private var editing: Wish?
    @State private var isNew = false
    @State private var stepFor: UUID?
    @State private var stepText = ""
    @State private var busy = false
    @State private var confirmDelete: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button {
                    if editing != nil { editing = nil } else { state.showWishes = false }
                } label: { Image(systemName: "chevron.left") }
                    .buttonStyle(.borderless)
                Text(L("✨ Xin vía", "✨ Wishes")).font(.headline)
                Spacer()
                if editing == nil {
                    Button(L("＋ Điều ước", "＋ Wish")) {
                        isNew = true
                        editing = Wish(title: "")
                    }
                    .buttonStyle(PillButtonStyle(primary: true))
                }
            }
            if let w = editing {
                WishForm(wish: w, isNew: isNew) { saved in
                    if isNew { store.add(saved) } else { store.update(saved) }
                    editing = nil
                } onCancel: {
                    editing = nil
                }
            } else {
                Text(L("Ghi điều bạn muốn đạt được. Pet sẽ nhắc lại mỗi ngày, truyền vía, và rủ bạn làm một bước nhỏ thật trong Todoist.",
                       "Write down what you want to achieve. The pet brings it up every day, sends good vibes, and nudges you to take one real small step in Todoist."))
                    .font(.callout).foregroundColor(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if store.wishes.isEmpty {
                    Text(L("Chưa có điều ước nào. Ví dụ: “Nói tiếng Anh trôi chảy”, “Chạy được 10 km”, “Tiết kiệm 100 triệu”.",
                           "No wishes yet. For example: “Speak fluent English”, “Run 10 km”, “Save $5,000”."))
                        .font(.callout).padding(.vertical, 6)
                }
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(store.wishes) { card($0) }
                    }
                }
                .frame(maxHeight: 380)
            }
        }
        .padding(14)
        .onAppear {
            if let id = state.wishFocus {
                stepFor = id
                state.wishFocus = nil
            }
        }
    }

    private func card(_ w: Wish) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 8) {
                Text(w.emoji).font(.title2)
                VStack(alignment: .leading, spacing: 2) {
                    Text(w.title).font(.system(size: 14, weight: .semibold)).fixedSize(horizontal: false, vertical: true)
                    if !w.why.isEmpty {
                        Text(w.why).font(.caption).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
                    }
                }
                Spacer()
                Button {
                    isNew = false
                    editing = w
                } label: { Image(systemName: "pencil") }
                    .buttonStyle(.borderless).help(L("Sửa", "Edit"))
                Button { confirmDelete = w.id } label: { Image(systemName: "trash") }
                    .buttonStyle(.borderless).foregroundColor(.red.opacity(0.8)).help(L("Xoá", "Delete"))
            }
            if !w.plan.isEmpty {
                Text("📝 " + w.plan).font(.caption).fixedSize(horizontal: false, vertical: true)
            } else if !w.obstacle.isEmpty {
                Text("⚠️ " + L("Trở ngại: ", "Obstacle: ") + w.obstacle).font(.caption).fixedSize(horizontal: false, vertical: true)
            }
            Text(progress(w)).font(.caption2).foregroundColor(.secondary)
            HStack(spacing: 6) {
                Button(L("🙏 Xin vía", "🙏 Bless it")) { brain.bless(w) }
                    .buttonStyle(PillButtonStyle())
                Button(L("＋ Bước nhỏ hôm nay", "＋ Small step today")) {
                    stepFor = w.id
                    stepText = ""
                }
                .buttonStyle(PillButtonStyle(primary: true))
                .disabled(!brain.hasToken)
            }
            if stepFor == w.id {
                HStack(spacing: 6) {
                    TextField(L("vd: Học 10 từ mới (15')", "e.g. Learn 10 new words (15')"), text: $stepText)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { addStep(w) }
                        .disabled(busy)
                    Button {
                        addStep(w)
                    } label: {
                        if busy { ProgressView().controlSize(.small) } else { Image(systemName: "plus.circle.fill").font(.title3) }
                    }
                    .buttonStyle(.borderless)
                    .disabled(stepText.trimmingCharacters(in: .whitespaces).isEmpty || busy)
                }
                Text(L("Bước nhỏ sẽ thành một việc hôm nay trong Todoist. Xong việc đó là vía về ✨",
                       "The step becomes a task for today in Todoist. Finish it and the vibes come back ✨"))
                    .font(.caption2).foregroundColor(.secondary)
            }
            if confirmDelete == w.id {
                HStack {
                    Text(L("Xoá điều ước này?", "Delete this wish?")).font(.caption).foregroundColor(.red)
                    Spacer()
                    Button(L("Huỷ", "Cancel")) { confirmDelete = nil }
                    Button(L("Xoá", "Delete")) {
                        store.remove(w.id)
                        confirmDelete = nil
                    }
                    .foregroundColor(.red)
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10).fill(Color.yellow.opacity(0.10)))
    }

    private func progress(_ w: Wish) -> String {
        var s = L("✅ \(w.steps) bước đã làm", "✅ \(w.steps) step(s) done")
        if let last = w.lastStepAt {
            let days = DayMath.daysBetween(DayMath.key(last), DayMath.key(Date()))
            s += " · " + (days == 0 ? L("gần nhất: hôm nay", "last: today") : L("gần nhất: \(days) ngày trước", "last: \(days) day(s) ago"))
        }
        return s
    }

    private func addStep(_ w: Wish) {
        let text = stepText
        guard !text.trimmingCharacters(in: .whitespaces).isEmpty, !busy else { return }
        busy = true
        Task {
            if await brain.addWishStep(w, step: text) {
                stepText = ""
                stepFor = nil
            }
            busy = false
        }
    }
}

/// Add or edit a wish, WOOP-style: wish, outcome, obstacle, if-then plan.
struct WishForm: View {
    @State private var wish: Wish
    let isNew: Bool
    let onSave: (Wish) -> Void
    let onCancel: () -> Void

    init(wish: Wish, isNew: Bool, onSave: @escaping (Wish) -> Void, onCancel: @escaping () -> Void) {
        _wish = State(initialValue: wish)
        self.isNew = isNew
        self.onSave = onSave
        self.onCancel = onCancel
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(isNew ? L("Điều ước mới", "New wish") : L("Sửa điều ước", "Edit wish")).font(.subheadline.bold())
            HStack(spacing: 4) {
                ForEach(Wish.emojis, id: \.self) { e in
                    Button(e) { wish.emoji = e }
                        .buttonStyle(.borderless)
                        .padding(3)
                        .background(RoundedRectangle(cornerRadius: 6).fill(wish.emoji == e ? Color.accentColor.opacity(0.25) : .clear))
                }
            }
            field(L("Bạn mong muốn đạt được điều gì?", "What do you want to achieve?"), $wish.title)
            field(L("Đạt được thì sẽ thế nào? (tuỳ chọn)", "What will it be like when you get there? (optional)"), $wish.why)
            field(L("Trở ngại lớn nhất trong bạn là gì? (tuỳ chọn)", "What's your biggest inner obstacle? (optional)"), $wish.obstacle)
            field(L("Kế hoạch: Nếu … thì mình sẽ … (tuỳ chọn)", "Plan: If … then I will … (optional)"), $wish.plan)
            Text(L("Mẹo (WOOP): chỉ mơ thôi thì dễ mất động lực. Hình dung kết quả, nghĩ trước trở ngại và đặt kế hoạch “nếu… thì…” giúp bạn dễ làm được hơn.",
                   "Tip (WOOP): dreaming alone can sap motivation. Picturing the outcome, naming the obstacle and making an if-then plan makes it more likely to happen."))
                .font(.caption2).foregroundColor(.secondary).fixedSize(horizontal: false, vertical: true)
            HStack {
                Button(L("Huỷ", "Cancel"), action: onCancel)
                Spacer()
                Button(L("Lưu", "Save")) {
                    var w = wish
                    w.title = w.title.trimmingCharacters(in: .whitespacesAndNewlines)
                    onSave(w)
                }
                .keyboardShortcut(.defaultAction)
                .disabled(wish.title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func field(_ prompt: String, _ text: Binding<String>) -> some View {
        TextField(prompt, text: text).textFieldStyle(.roundedBorder)
    }
}
