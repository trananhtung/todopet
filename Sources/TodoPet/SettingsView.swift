import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @ObservedObject var prefs: Prefs
    @ObservedObject var brain: Brain
    @State private var token = ""
    @State private var busy = false
    @State private var message: String?
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    private func hour(_ h: Int) -> String { String(format: "%02d:00", h) }

    var body: some View {
        Form {
            Section(L("Chung", "General")) {
                Picker(L("Ngôn ngữ", "Language"), selection: $prefs.lang) {
                    ForEach(Lang.allCases) { Text($0.label).tag($0) }
                }
                TextField(L("Tên pet", "Pet name"), text: $prefs.petName)
                HStack {
                    Text(L("Kích thước", "Size"))
                    Slider(value: $prefs.petScale, in: 0.7...1.6, step: 0.1)
                    Text(String(format: "%.0f%%", prefs.petScale * 100)).monospacedDigit().frame(width: 44, alignment: .trailing)
                }
                Toggle(L("Âm thanh", "Sounds"), isOn: $prefs.soundOn)
                Toggle(L("Khi nổi cáu thì đuổi theo con trỏ chuột", "Chase the mouse cursor when grumpy"), isOn: $prefs.chaseWhenAngry)
                Toggle(L("Mở cùng macOS", "Open at login"), isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, on in
                        do {
                            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                        } catch {
                            message = error.localizedDescription
                            launchAtLogin = SMAppService.mainApp.status == .enabled
                        }
                    }
            }

            Section("Todoist") {
                if brain.hasToken && !brain.isDemo {
                    HStack {
                        Label(L("Đã kết nối", "Connected"), systemImage: "checkmark.seal.fill").foregroundColor(.green)
                        Spacer()
                        Button(L("Ngắt kết nối", "Disconnect"), role: .destructive) { brain.removeToken() }
                    }
                }
                SecureField(brain.hasToken && !brain.isDemo ? L("Token mới (tuỳ chọn)", "New token (optional)") : "API token", text: $token)
                HStack {
                    Button(L("Lưu token", "Save token")) {
                        busy = true
                        Task {
                            let ok = await brain.setToken(token)
                            message = ok ? L("Đã kết nối ✔︎", "Connected ✔︎") : (brain.errorText ?? L("Không kết nối được", "Could not connect"))
                            if ok { token = "" }
                            busy = false
                        }
                    }
                    .disabled(token.isEmpty || busy)
                    Link(L("Lấy token ↗", "Get token ↗"), destination: URL(string: "https://app.todoist.com/app/settings/integrations/developer")!)
                    if busy { ProgressView().controlSize(.small) }
                }
                TextField(L("Bộ lọc “việc của tôi hôm nay”", "“My day” filter"), text: $prefs.filterQuery)
                Text(L("Cú pháp bộ lọc Todoist, vd: (today | overdue) & #Công việc", "Todoist filter syntax, e.g. (today | overdue) & #Work"))
                    .font(.caption).foregroundColor(.secondary)
            }

            Section(L("Nhịp làm việc", "Work rhythm")) {
                Stepper(L("Số việc cần lên kế hoạch mỗi ngày: \(prefs.dailyTarget)", "Tasks to plan each day: \(prefs.dailyTarget)"),
                        value: $prefs.dailyTarget, in: 1...10)
                Stepper(L("Bắt đầu làm việc: \(hour(prefs.workStart))", "Work starts: \(hour(prefs.workStart))"),
                        value: $prefs.workStart, in: 0...(max(0, prefs.workEnd - 1)))
                Stepper(L("Kết thúc: \(hour(prefs.workEnd))", "Work ends: \(hour(prefs.workEnd))"),
                        value: $prefs.workEnd, in: (prefs.workStart + 1)...24)
                Stepper(L("Hạn lên kế hoạch: \(hour(prefs.planDeadline))", "Plan by: \(hour(prefs.planDeadline))"),
                        value: $prefs.planDeadline, in: prefs.workStart...max(prefs.workStart, prefs.workEnd))
                Toggle(L("Làm việc Thứ 7", "Work on Saturday"), isOn: $prefs.workSaturday)
                Toggle(L("Làm việc Chủ nhật", "Work on Sunday"), isOn: $prefs.workSunday)
                Stepper(L("Nhắc việc mỗi \(prefs.remindEvery) phút", "Nudge every \(prefs.remindEvery) min"),
                        value: $prefs.remindEvery, in: 15...180, step: 15)
                Stepper(L("Phiên tập trung: \(prefs.focusMinutes) phút", "Focus session: \(prefs.focusMinutes) min"),
                        value: $prefs.focusMinutes, in: 5...90, step: 5)
                Stepper(L("Nghỉ giữa phiên: \(prefs.breakMinutes) phút", "Break: \(prefs.breakMinutes) min"),
                        value: $prefs.breakMinutes, in: 1...30)
            }

            Section(L("Chống xao nhãng", "Distractions")) {
                TextField(L("Ứng dụng gây xao nhãng", "Distracting apps"), text: $prefs.distractionApps)
                Text(L("Tên app cách nhau bởi dấu phẩy. Mở app này hơn 2 phút trong giờ làm, pet sẽ cáu.",
                       "Comma-separated app names. Using one for 2+ minutes during work hours makes the pet grumpy."))
                    .font(.caption).foregroundColor(.secondary)
            }

            if let message {
                Text(message).font(.callout)
            }
        }
        .formStyle(.grouped)
        .frame(width: 480, height: 640)
    }
}
