<p align="center"><img src="docs/icon.png" width="128" alt="Biểu tượng TodoPet"></p>

<h1 align="center">TodoPet</h1>

<p align="center">
Một chú pet nhỏ cho macOS, đi dạo trên thanh Dock, đọc công việc từ <a href="https://todoist.com">Todoist</a>,
<b>vui khi bạn làm việc</b> và <b>nổi cáu khi bạn lười</b>.<br>
<a href="README.md">English</a> · Tiếng Việt
</p>

![Các tâm trạng](docs/moods.png)

## Pet làm được gì

- **Đi dạo trên màn hình.** Mochi đi qua đi lại trên Dock, nhìn theo con trỏ, và đứng lại khi bạn rê chuột vào. Kéo thả đi đâu cũng được, thả ra nó sẽ rơi xuống lại.
- **Hỏi "Hôm nay làm gì?".** Nếu hôm nay chưa có đủ **3 việc** (chỉnh được), pet sẽ nhắc bạn lên kế hoạch: buổi sáng hỏi nhẹ nhàng, qua giờ hạn chót thì nhắc gắt dần.
- **Nhắc đúng việc cần làm.** Pet chọn việc tiếp theo theo kiểu "ăn con ếch trước" (ưu tiên cao nhất, rồi giờ sớm nhất), nhắc mỗi 45 phút, và báo trước 10 phút với việc có giờ cụ thể.
- **Có tâm trạng thật.** Pet ăn mừng mỗi việc bạn xong (kể cả việc tích trong app Todoist), và nhăn nhó, rồi nổi cáu, khi có việc quá hạn, nhiều giờ không tiến triển, hoặc bạn ngồi lâu trong app gây xao nhãng. Lúc cáu nó còn hầm hầm đi về phía con trỏ chuột 😤
- **Làm việc với Todoist ngay trên pet.** Bấm vào pet để xem việc hôm nay, tích hoàn thành, thêm việc mới (Hôm nay / Ngày mai / Không hạn, độ ưu tiên, hoặc cú pháp quick-add của Todoist như `Gọi Lan 3pm p1 #Work`), dời việc sang hôm nay hoặc ngày mai, và xem chuỗi ngày (streak) trên Todoist.
- **Có hẹn giờ tập trung.** Bắt đầu phiên 25 phút cho một việc, pet đeo băng đô rồi ngồi im trong góc. Hết giờ, pet hỏi bạn xong chưa; nếu xong, pet tự đánh dấu hoàn thành trên Todoist và bắt đầu giờ nghỉ.
- **Tổng kết cuối ngày.** 30 phút trước giờ tan làm, pet cho bạn xem đã xong bao nhiêu việc và đề nghị dời phần còn lại sang mai.
- **Nói tiếng Việt và tiếng Anh**, đổi trong Cài đặt.

| Bảng việc | Bong bóng thoại |
|---|---|
| ![Bảng việc](docs/board-vi.png) | ![Bong bóng](docs/bubble-vi.png) |

## Cài đặt

Cần macOS 14 trở lên và Xcode Command Line Tools (`xcode-select --install`). Không cần cài Xcode.

```bash
git clone https://github.com/trananhtung/todopet.git
cd todopet
scripts/build.sh
cp -R build/TodoPet.app /Applications/
open /Applications/TodoPet.app
```

`UNIVERSAL=1 scripts/build.sh` build cho cả chip Apple và Intel.

Muốn xem thử trước? Chạy `open build/TodoPet.app --args --demo` để dùng dữ liệu mẫu, không cần tài khoản.

## Kết nối Todoist

1. Trong Todoist, vào **Cài đặt → Tích hợp → Developer** ([link thẳng](https://app.todoist.com/app/settings/integrations/developer)) và sao chép **API token**.
2. Bấm vào pet, dán token rồi bấm **Lưu & kết nối**.

Token được lưu trong **Keychain** của macOS và chỉ được gửi tới `api.todoist.com` (Todoist API v1). Sau khi build lại app, macOS có thể hỏi một lần xem TodoPet có được đọc Keychain không; chọn **Luôn cho phép**.

### Dùng Todoist qua Claude hoặc AI khác (MCP)

TodoPet nói chuyện trực tiếp với Todoist bằng API token. Nếu bạn muốn quản lý việc bằng cách chat với trợ lý AI, hãy kết nối MCP server chính thức của Todoist tại `https://ai.todoist.net/mcp`. Với Claude Code: `claude mcp add --transport http todoist https://ai.todoist.net/mcp`; với Claude Desktop thì thêm làm custom connector. Việc tạo ở đó sẽ hiện trên pet trong vòng 3 phút, hoặc ngay khi bạn bấm vào pet.

## Cách dùng

| Thao tác | Kết quả |
|---|---|
| Bấm vào pet | Mở bảng việc |
| Kéo pet | Di chuyển; thả ra pet rơi xuống Dock |
| Rê chuột vào | Pet đứng lại và đỏ mặt |
| Chuột phải / biểu tượng trên thanh menu | Menu nhanh: thêm việc, tập trung, ẩn 1 giờ, im lặng 1 giờ, cài đặt |
| <kbd>⌃</kbd><kbd>⌥</kbd><kbd>T</kbd> | Mở bảng việc với ô thêm việc sẵn sàng, từ bất kỳ app nào |

Thanh menu hiện tâm trạng và tiến độ hôm nay (`😊 2/3`), hoặc đồng hồ khi đang tập trung (`🍅 18:42`).

## Tâm trạng được tính thế nào

Mochi có điểm hạnh phúc từ 0 đến 100, tính lại mỗi 15 giây. Rê chuột vào dòng lý do trên bảng việc để xem chi tiết.

| Làm pet vui hơn | Làm pet cáu hơn |
|---|---|
| +8 cho mỗi việc xong hôm nay | −7 cho mỗi việc quá hạn |
| +30 khi xong hết kế hoạch hôm nay | −4 cho mỗi việc đã trễ giờ |
| Tới +15 ngay sau khi bạn xong một việc | −12 đến −50 khi qua hạn lên kế hoạch mà chưa đủ 3 việc |
| +10 khi đang tập trung | Tới −30 khi hơn 90 phút không có tiến triển |
| | Tới −35 khi ở trong app gây xao nhãng hơn 2 phút |

Từ 75 điểm là vui, từ 50 là bình thường, từ 30 là nhăn nhó, thấp hơn nữa là nổi cáu. Ngoài giờ làm, ban đêm, hoặc khi bạn rời máy 10 phút, pet dịu lại hoặc ngủ, và không bao giờ cằn nhằn lúc bạn vắng mặt.

## Khi nào pet lên tiếng

Theo thứ tự ưu tiên, mỗi lúc chỉ một bong bóng:

1. 10 phút trước và đúng giờ của việc có giờ cụ thể
2. Chào buổi sáng kèm kế hoạch hôm nay (hoặc nhắc lên kế hoạch)
3. "Hôm nay mình làm 3 việc gì nào?" mỗi 30 phút sau hạn lên kế hoạch, cho tới khi đủ việc
4. Mở app gây xao nhãng quá 2 phút
5. Việc quá hạn, mỗi 90 phút
6. Tổng kết cuối ngày
7. Nhắc việc tiếp theo, mỗi 45 phút
8. Thỉnh thoảng một mẹo năng suất, chỉ khi pet đang vui

Mọi mốc thời gian đều chỉnh được trong **Cài đặt**: số việc mỗi ngày, giờ làm, ngày làm việc, hạn lên kế hoạch, khoảng nhắc, độ dài phiên tập trung và giờ nghỉ, app gây xao nhãng, bộ lọc Todoist riêng cho "việc của tôi" (ví dụ `(today | overdue) & #Work`), kích thước pet, âm thanh, và mở cùng macOS.

## Vì sao có những tính năng này

Hành vi của pet dựa trên các phương pháp năng suất phổ biến, cố tình giữ đơn giản:

- **Quy tắc 3 việc**: mỗi ngày chọn ba kết quả quan trọng thay vì một danh sách dài vô tận (J.D. Meier, *Getting Results the Agile Way*).
- **Ăn con ếch trước**: bắt đầu bằng việc quan trọng nhất (Brian Tracy).
- **Ý định thực hiện**: việc có giờ cụ thể ("14h mình sẽ…") dễ được làm hơn (Peter Gollwitzer). Pet nhắc bạn đúng giờ.
- **Pomodoro**: các phiên tập trung ngắn có hẹn giờ, xen kẽ nghỉ (Francesco Cirillo).
- **Bị gián đoạn rất tốn kém**: quay lại việc sau khi chuyển sang thứ khác mất khá lâu (nghiên cứu của Gloria Mark), nên pet nhắc khi bạn mở app gây xao nhãng và im lặng khi bạn tập trung.
- **Nghi thức kết thúc ngày**: khép lại ngày bằng cách xem lại và dời việc (Cal Newport).
- **Phản hồi cảm xúc**: một nhân vật phản ứng rõ ràng với tiến độ của bạn khiến việc hoàn thành có cảm giác được thưởng, còn lười thì hơi áy náy.

## Quyền riêng tư

- Không thu thập dữ liệu, không có máy chủ riêng. Kết nối mạng duy nhất là tới `api.todoist.com`.
- Phát hiện xao nhãng chỉ đọc **tên app đang mở phía trước** (không quay màn hình, không cần quyền trợ năng, không đọc tab trình duyệt).
- Phát hiện vắng mặt chỉ đọc "số giây từ lần gõ phím/di chuột cuối", không cần cấp quyền.

## Phát triển

```bash
scripts/build.sh                                    # build ra build/TodoPet.app
build/TodoPet.app/Contents/MacOS/TodoPet --selftest   # test logic (ngày giờ, đọc API, tâm trạng)
build/TodoPet.app/Contents/MacOS/TodoPet --demo       # chạy với dữ liệu mẫu
build/TodoPet.app/Contents/MacOS/TodoPet --snapshot out/  # xuất ảnh PNG các tâm trạng, bảng việc, bong bóng
```

Viết bằng Swift, SwiftUI và AppKit thuần, không thư viện ngoài, build bằng `swiftc`. Xem bảng cấu trúc file trong [README tiếng Anh](README.md#development).

## Giấy phép

[MIT](LICENSE)
