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
- **Làm việc với Todoist ngay trên pet.** Bấm vào pet để xem việc hôm nay, tích hoàn thành, thêm việc mới (Hôm nay / Ngày mai / Không hạn, độ ưu tiên, hoặc cú pháp quick-add của Todoist như `Gọi Lan 3pm p1 #Work`), dời việc sang hôm nay hoặc ngày mai, xoá việc (có bước xác nhận, vì Todoist không khôi phục được), và xem chuỗi ngày (streak) trên Todoist.
- **Có hẹn giờ tập trung.** Bắt đầu phiên 25 phút cho một việc, pet đeo băng đô rồi ngồi im trong góc. Hết giờ, pet hỏi bạn xong chưa; nếu xong, pet tự đánh dấu hoàn thành trên Todoist và bắt đầu giờ nghỉ.
- **Tổng kết cuối ngày.** 30 phút trước giờ tan làm, pet cho bạn xem đã xong bao nhiêu việc và đề nghị dời phần còn lại sang mai.
- **Bắt quả tang trang web gây xao nhãng.** Pet đọc tab đang mở trong Safari, Chrome, Arc, Edge, Brave, Cốc Cốc và các trình duyệt Chromium khác. Ngồi YouTube hay Facebook quá 2 phút trong giờ làm là pet bắt đầu nhăn nhó. Bạn tự chọn danh sách trang; quy tắc như `youtube.com/shorts` chỉ bắt đúng một phần của trang.
- **Biết lịch họp của bạn.** Pet đọc các sự kiện hôm nay từ Lịch của macOS (gồm cả tài khoản Google, Outlook đã thêm vào Lịch). Pet nhắc trước giờ họp 5 phút kèm nút **Vào họp**, im lặng khi bạn đang họp, và không tính giờ họp là lười. Ngày nào họp nhiều thì pet hạ mục tiêu, khoảng 2 giờ trống cho 1 việc quan trọng.
- **Gợi ý khung giờ.** Pet xếp các việc tiếp theo vào khoảng trống trong ngày ("10:00–11:00 Viết báo cáo"). Một cú bấm là đặt giờ đó cho việc trong Todoist, và pet sẽ nhắc bạn đúng giờ.
- **Phát hiện việc bị dời mãi.** Việc nào nằm trong danh sách từ 3 ngày trở lên, pet hỏi bạn muốn chia nhỏ hay bỏ khỏi kế hoạch. Chia nhỏ là tách thành các bước 15–30 phút, thêm vào Todoist dưới dạng việc con, bước 1 vào kế hoạch hôm nay. Nếu có API key Claude, nút **Nhờ Claude gợi ý** sẽ đề xuất các bước giúp bạn.
- **Nói tiếng Việt và tiếng Anh**, đổi trong Cài đặt.

### Một chú pet sống cùng công việc của bạn

![Lớn lên, đói, phụ kiện và ăn mừng](docs/life-vi.png)

- **Làm xong việc là cho pet ăn.** Mỗi việc xong là một món ngon rơi vào miệng pet (+25% độ no). Độ no giảm khoảng 7% mỗi giờ làm việc, nên lười cả ngày thì pet gầy, đói, bụng réo. Mỗi ngày làm việc mà không xong việc nào, pet bẩn thêm một lớp, tối đa 3 lớp, kèm ruồi bay quanh. Mỗi việc xong tắm sạch một lớp. Tất cả giữ nguyên sang ngày hôm sau.
- **Nhìn pet lớn lên.** Việc xong cho XP, và pet lớn dần từ Em bé (có mầm lá trên đầu) lên Nhóc, Thiếu niên, Trưởng thành, Cao thủ.
- **Ăn mừng bất ngờ.** Mỗi việc xong là một kiểu ngẫu nhiên: nhảy, xoay, lộn nhào, nhảy disco. 1/10 lần là bánh vàng hiếm, pet hoá vàng. Xong việc liên tiếp trong vòng 30 phút sẽ thành combo ×2, ×3…, nhiều XP hơn, và kết bằng pháo hoa.
- **Mở khoá đồ để mặc.** Nơ, khăn, kính râm, mũ quý ông, vương miện, mũ tốt nghiệp, mở theo các cột mốc: việc đầu tiên, chuỗi 3 ngày, combo ×3, 25 việc, chuỗi 7 ngày… Có thêm sổ sticker ghi lại những ngày bạn làm trọn kế hoạch.
- **Quậy leo thang khi bạn lười.** Nhăn nhó 10 phút thì pet thở dài, giậm chân. Cáu 10 phút thì pet diễu hành ngang màn hình, kéo theo tấm biển ghi tên việc bạn đang né. Đang cáu mà ngồi YouTube 5 phút thì pet nhảy lên giữa màn hình kèm (╯°□°)╯︵ ┻━┻. Cuối ngày, pet hờn dỗi báo bạn đã lướt mạng bao lâu. Pet có thể nói thành tiếng bằng giọng Linh của macOS (mặc định tắt).
- **Quậy có luật.** Không quậy khi bạn đang họp, đang tập trung hay đã rời máy. Trò lớn tối đa 20 phút một lần. Mỗi trò có nút **Tha cho tôi 15'**, và bấm vào pet là pet thôi quậy. Bạn có thể tắt hẳn trò quậy trong Cài đặt.

| Tủ đồ | Trò quậy |
|---|---|
| ![Tủ đồ](docs/wardrobe-vi.png) | ![Biển](docs/sign.png)<br>![Lật bàn](docs/bubble-block-vi.png) |

| Bảng việc | Bong bóng thoại | Chia nhỏ việc |
|---|---|---|
| ![Bảng việc](docs/board-vi.png) | ![Bong bóng](docs/bubble-vi.png)<br>![Việc bị dời mãi](docs/bubble-stuck-vi.png) | ![Chia nhỏ](docs/split-vi.png) |

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

**Nên làm nếu bạn hay build lại:** cho các bản build một chữ ký cố định. macOS gắn quyền Lịch và quyền điều khiển trình duyệt vào chữ ký, nên không phải cấp lại sau mỗi lần cập nhật. Keychain thì khác: với app không có Apple Developer ID, "Luôn cho phép" bị gắn vào đúng bản build, nên mỗi lần cập nhật có thay đổi code Keychain vẫn hỏi lại một lần.

```bash
scripts/setup-signing.sh   # tạo chứng chỉ "TodoPet Local Signing" trong một keychain riêng
scripts/trust-signing.sh   # đánh dấu tin cậy để ký code, chỉ cho tài khoản của bạn (macOS hỏi mật khẩu)
```

Sau đó `scripts/build.sh` tự ký bằng chứng chỉ này. Muốn gỡ: xoá thư mục `~/Library/Application Support/TodoPet-Signing` và chứng chỉ trong Keychain Access.

Muốn xem thử trước? Chạy `open build/TodoPet.app --args --demo` để dùng dữ liệu mẫu, không cần tài khoản.

## Kết nối Todoist

1. Trong Todoist, vào **Cài đặt → Tích hợp → Developer** ([link thẳng](https://app.todoist.com/app/settings/integrations/developer)) và sao chép **API token**.
2. Bấm vào pet, dán token rồi bấm **Lưu & kết nối**.

Token được lưu trong **Keychain** của macOS và chỉ được gửi tới `api.todoist.com` (Todoist API v1). Sau khi build lại app, macOS có thể hỏi một lần xem TodoPet có được đọc Keychain không; chọn **Luôn cho phép**.

### Các quyền macOS sẽ hỏi

| Hộp thoại | Để làm gì | Nếu bạn từ chối |
|---|---|---|
| Lịch | Giờ họp, giờ trống, gợi ý khung giờ | Bảng việc hiện nút **Cho phép**; các tính năng khác vẫn chạy |
| "TodoPet muốn điều khiển Safari / Chrome…" (mỗi trình duyệt một lần) | Đọc địa chỉ tab đang mở để bắt trang gây xao nhãng | Tắt phát hiện trang web cho trình duyệt đó; phát hiện app vẫn chạy |

Với chữ ký ad-hoc, macOS hỏi lại quyền Lịch và trình duyệt sau mỗi lần build; với chứng chỉ ký riêng (xem phần Cài đặt) thì giữ nguyên. Keychain vẫn hỏi lại mỗi khi code của app thay đổi; chỉ chữ ký Apple Developer ID mới tránh được.

### Chia nhỏ việc bằng Claude (tuỳ chọn)

Thêm API key Anthropic trong **Cài đặt → Việc bị dời mãi** ([lấy key](https://console.anthropic.com/settings/keys)). Khi bạn bấm **Nhờ Claude gợi ý**, tên và ghi chú của việc được gửi tới Claude API, và Claude trả về 3–5 bước nhỏ. App dùng `claude-opus-5-5` ở mức effort thấp, có bật fallback phía máy chủ phòng khi yêu cầu bị từ chối. Mỗi lần khoảng 1–2 xu Mỹ; bạn đổi được model trong Cài đặt. Không có key thì bạn vẫn tự gõ các bước hoặc dùng mẫu nhanh.

### Dùng Todoist qua Claude hoặc AI khác (MCP)

TodoPet nói chuyện trực tiếp với Todoist bằng API token. Nếu bạn muốn quản lý việc bằng cách chat với trợ lý AI, hãy kết nối MCP server chính thức của Todoist tại `https://ai.todoist.net/mcp`. Với Claude Code: `claude mcp add --transport http todoist https://ai.todoist.net/mcp`; với Claude Desktop thì thêm làm custom connector. Việc tạo ở đó sẽ hiện trên pet trong vòng 3 phút, hoặc ngay khi bạn bấm vào pet.

## Cách dùng

| Thao tác | Kết quả |
|---|---|
| Bấm vào pet | Mở bảng việc |
| Rê chuột vào một việc trên bảng | ▶︎ tập trung · ✂️ chia nhỏ · → dời · 🗑 xoá (hỏi lại trước khi xoá; việc con và cả chuỗi lặp lại cũng bị xoá, không hoàn tác được) |
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
| Giờ họp được tính là làm việc | Tới −35 khi ở trong app hoặc trang web gây xao nhãng hơn 2 phút |
| | −3 cho mỗi việc bị dời mãi (tối đa −9) |
| | Tới −15 khi pet đói (dưới 30% no) |
| | −5 cho mỗi lớp bẩn |

Từ 75 điểm là vui, từ 50 là bình thường, từ 30 là nhăn nhó, thấp hơn nữa là nổi cáu. Ngoài giờ làm, ban đêm, khi đang họp, hoặc khi bạn rời máy 10 phút, pet dịu lại hoặc ngủ, và không bao giờ cằn nhằn lúc bạn vắng mặt.

## Khi nào pet lên tiếng

Theo thứ tự ưu tiên, mỗi lúc chỉ một bong bóng:

1. Vài phút trước giờ họp (kể cả khi đang tập trung), sau đó im lặng tới khi họp xong
2. 10 phút trước và đúng giờ của việc có giờ cụ thể
3. Chào buổi sáng kèm kế hoạch hôm nay (hoặc nhắc lên kế hoạch) và tóm tắt lịch họp, giờ trống
4. "Hôm nay mình làm 3 việc gì nào?" mỗi 30 phút sau hạn lên kế hoạch, cho tới khi đủ việc
5. Mở app hoặc trang web gây xao nhãng quá 2 phút
6. Việc bị dời mãi: chia nhỏ hay bỏ khỏi kế hoạch
7. Đói: xin bạn xong một việc, tối đa mỗi giờ một lần
8. Quậy khi bạn lười: càu nhàu, rồi diễu hành với tấm biển (trò lật bàn đi kèm mục 5)
9. Việc quá hạn, mỗi 90 phút
10. Mỗi ngày một lần, gợi ý khung giờ cho việc tiếp theo
11. Tổng kết cuối ngày, rồi báo cáo hờn dỗi nếu bạn xao nhãng từ 10 phút trở lên
12. Nhắc việc tiếp theo, mỗi 45 phút
13. Thỉnh thoảng một mẹo năng suất, chỉ khi pet đang vui

Mọi mốc thời gian đều chỉnh được trong **Cài đặt**: số việc mỗi ngày, giờ làm, ngày làm việc, hạn lên kế hoạch, khoảng nhắc, độ dài phiên tập trung và giờ nghỉ, app và trang web gây xao nhãng, tuỳ chọn Lịch, sau bao nhiêu ngày thì tính là bị dời mãi, bộ lọc Todoist riêng cho "việc của tôi" (ví dụ `(today | overdue) & #Work`), kích thước pet, âm thanh, trò quậy, giọng nói, bảo vệ tập trung, và mở cùng macOS.

## Thiết kế để không làm bạn mất tập trung

Một app nhắc việc mà cắt ngang lúc bạn đang tập trung thì hại nhiều hơn lợi. Vì vậy pet làm theo các khuyến nghị từ nghiên cứu về sự gián đoạn:

| Nguyên tắc | Vì sao |
|---|---|
| **Chỉ ngắt ở điểm nghỉ.** Lời nhắc không gấp đợi tới khi bạn ngừng gõ vài giây hoặc chuyển app. Nhắc họp và việc tới giờ vẫn đến đúng lúc. | Bị ngắt ở ranh giới giữa các việc đỡ bực và quay lại việc nhanh hơn bị ngắt giữa chừng (Adamczyk & Bailey 2004; Iqbal & Bailey 2008). |
| **Bảo vệ lúc vào guồng.** Gõ phím đều đặn 10 phút trong app làm việc thì pet hiện 🎧, giữ lại mọi lời nhắc không gấp và tính thời gian đó là tiến độ. Không nhăn nhó, không quậy. | Quay lại mạch làm việc sau khi bị ngắt rất chậm và gây căng thẳng (Mark và cộng sự 2008). |
| **Ít bong bóng hơn.** Hai lời nhắc tự phát cách nhau ít nhất 15 phút (chỉnh được), mỗi lúc một cái. | Thông báo được gom lại, ít hơn giúp tập trung và dễ chịu hơn (Fitz và cộng sự 2019). |
| **Đứng yên khi bạn gõ phím.** Pet thôi đi lại, cử động nhẹ đi; khi bạn nghỉ tay pet mới đi tiếp. | Chuyển động ở rìa tầm mắt kéo sự chú ý một cách vô thức (Bartram và cộng sự 2003). |
| **Mặc định yên lặng.** Âm thanh để ở mức "chỉ khi quan trọng" (sắp họp, việc tới giờ, hết phiên tập trung, xong việc) và nhỏ. Bong bóng thường hiện lặng lẽ, mờ dần vào. | "Calm technology": báo tin ở vùng ngoại vi, chỉ chiếm trung tâm khi thật cần (Weiser & Brown 1996). |
| **Chỉ quậy khi bạn lười, không quậy khi bạn làm.** Không quậy khi bạn đang gõ phím, đang họp, đang tập trung hoặc đã rời máy. | Cằn nhằn người đang làm việc chỉ làm đứt mạch của họ. |

Âm thanh có 3 mức trong Cài đặt: **Tắt**, **Chỉ khi quan trọng** (mặc định) và **Tất cả**.

### Nhật ký pet

Để chỉnh mọi thứ cho hợp với cách bạn thực sự làm việc, pet ghi nhật ký (nút 📜 trên bảng việc, hoặc trên thanh menu). Nhật ký ghi lại:
- mỗi lời nhắc và lý do pet nhắc
- bạn đã làm gì với lời nhắc đó (bấm nút nào, tự đóng, hay để nó tự ẩn)
- mỗi lần pet hoãn nhắc (bạn đang vào guồng, đang gõ phím, hoặc pet vừa nhắc gần đây)
- cuộc họp, phiên tập trung, lúc tâm trạng đổi kèm lý do chính, thời gian ở trang gây xao nhãng, lúc pet được ăn và kết quả chốt ngày

Dòng tóm tắt cho biết bạn nhận bao nhiêu lời nhắc và bỏ qua bao nhiêu. Nút **Sao chép** chép cả ngày, để bạn dán cho Claude và nhờ chỉnh lại. Nhật ký chỉ nằm trên máy bạn (`~/Library/Application Support/TodoPet/log`), giữ 14 ngày, và tắt được trong Cài đặt.

![Nhật ký pet](docs/diary-vi.png)

## Vì sao có những tính năng này

Hành vi của pet dựa trên các phương pháp năng suất phổ biến, cố tình giữ đơn giản:

- **Quy tắc 3 việc**: mỗi ngày chọn ba kết quả quan trọng thay vì một danh sách dài vô tận (J.D. Meier, *Getting Results the Agile Way*).
- **Ăn con ếch trước**: bắt đầu bằng việc quan trọng nhất (Brian Tracy).
- **Ý định thực hiện**: việc có giờ cụ thể ("14h mình sẽ…") dễ được làm hơn (Peter Gollwitzer). Pet nhắc bạn đúng giờ.
- **Pomodoro**: các phiên tập trung ngắn có hẹn giờ, xen kẽ nghỉ (Francesco Cirillo).
- **Bị gián đoạn rất tốn kém**: quay lại việc sau khi chuyển sang thứ khác mất khá lâu (nghiên cứu của Gloria Mark), nên pet nhắc khi bạn mở app hoặc trang web gây xao nhãng, và im lặng khi bạn tập trung hoặc đang họp.
- **Chặn lịch (time blocking)**: gắn cho việc một khung giờ trong lịch giúp giữ thời gian cho nó; pet tìm các khoảng trống giữa các cuộc họp.
- **Trì hoãn thường do việc quá to hoặc mơ hồ**: tách ra một bước đầu nhỏ, cụ thể sẽ dễ bắt tay vào hơn, nên pet gợi ý chia nhỏ những việc bạn cứ dời mãi.
- **Nghi thức kết thúc ngày**: khép lại ngày bằng cách xem lại và dời việc (Cal Newport).
- **Phản hồi cảm xúc**: một nhân vật phản ứng rõ ràng với tiến độ của bạn khiến việc hoàn thành có cảm giác được thưởng, còn lười thì hơi áy náy.
- **Chăm một con pet** ("hiệu ứng Tamagotchi", app Finch đang dùng): bạn làm việc một phần để pet được no và sạch, và hậu quả kéo dài qua nhiều ngày. Sợ mất thứ đang có thúc đẩy mạnh hơn mong được thêm.
- **Phần thưởng bất ngờ**: màn ăn mừng ngẫu nhiên và bánh vàng hiếm giữ được hứng thú lâu hơn phần thưởng cố định, nên game nào cũng dùng.

## Quyền riêng tư

- Không thu thập dữ liệu, không có máy chủ riêng. Kết nối mạng chỉ tới `api.todoist.com`, và tới `api.anthropic.com` khi bạn bấm **Nhờ Claude gợi ý**.
- Phát hiện xao nhãng đọc **tên app đang mở phía trước** và, nếu đó là trình duyệt, **địa chỉ tab đang mở**. Địa chỉ chỉ nằm trong bộ nhớ, không được lưu hay gửi đi đâu. Không cần quay màn hình hay quyền trợ năng.
- Lịch được đọc ngay trên máy qua macOS (EventKit); sự kiện không rời khỏi máy bạn.
- Nhật ký "việc bị dời mãi" chỉ gồm mã việc và ngày, lưu trong cài đặt cục bộ của app. Đời sống của pet (độ no, XP, phụ kiện, số phút xao nhãng hôm nay theo từng trang) cũng lưu cục bộ như vậy.
- Giọng nói dùng giọng có sẵn của macOS, chạy offline.
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
