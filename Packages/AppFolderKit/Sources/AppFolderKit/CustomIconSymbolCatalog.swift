import Foundation

/// The one allowlist for selectable and persisted SF Symbols. Search metadata
/// is local UI data; it never enters a saved icon or its content-addressed hash.
public enum CustomIconSymbolCatalog {
    public enum Category: String, CaseIterable, Sendable, Identifiable {
        case essentials, communication, media, productivity, technology
        case travel, shopping, food, nature, health

        public var id: String { rawValue }
        public var titleKey: String {
            switch self {
            case .essentials: "常用符号"
            case .communication: "通讯与人物"
            case .media: "媒体与创作"
            case .productivity: "工作与学习"
            case .technology: "设备与工具"
            case .travel: "交通与出行"
            case .shopping: "购物与财务"
            case .food: "餐饮与生活"
            case .nature: "自然与天气"
            case .health: "健康与运动"
            }
        }
    }

    public struct Entry: Identifiable, Sendable, Hashable {
        public let id: String
        public let titleKey: String
        public let category: Category
        public let keywords: [String]

        fileprivate init(_ id: String, _ titleKey: String, _ category: Category, _ keywords: [String]) {
            self.id = id
            self.titleKey = titleKey
            self.category = category
            self.keywords = keywords
        }
    }

    /// The original 70 entries keep their exact order; additions follow them.
    /// Neither a translated title nor a search term can create a new symbol ID.
    public static let entries: [Entry] = [
        .init("star.fill", "星星", .essentials, ["星标", "星星", "收藏", "star", "favorite", "favourite"]),
        .init("heart.fill", "爱心", .essentials, ["喜欢", "心形", "heart", "love", "like"]),
        .init("bolt.fill", "闪电", .essentials, ["快速", "电力", "bolt", "lightning", "power"]),
        .init("moon.fill", "月亮", .nature, ["夜晚", "睡眠", "moon", "night", "sleep"]),
        .init("sun.max.fill", "太阳", .nature, ["晴天", "白天", "sun", "sunny", "day"]),
        .init("house.fill", "家", .food, ["住宅", "家庭", "房屋", "家", "home", "house"]),
        .init("briefcase.fill", "工作", .productivity, ["公文包", "办公", "工作", "briefcase", "work", "office"]),
        .init("book.fill", "书籍", .productivity, ["书本", "阅读", "学习", "book", "read", "study"]),
        .init("bookmark.fill", "书签", .productivity, ["收藏", "阅读", "bookmark", "save", "reading"]),
        .init("graduationcap.fill", "毕业帽", .productivity, ["学校", "教育", "graduation", "school", "education"]),
        .init("paperplane.fill", "纸飞机", .communication, ["发送", "分享", "paper plane", "send", "share"]),
        .init("envelope.fill", "信封", .communication, ["邮件", "邮箱", "envelope", "mail", "email"]),
        .init("bubble.left.and.bubble.right.fill", "聊天", .communication, ["对话", "聊天", "消息", "短信", "chat", "message", "sms"]),
        .init("phone.fill", "电话", .communication, ["拨号", "通话", "phone", "call", "dial"]),
        .init("person.fill", "人物", .communication, ["用户", "联系人", "person", "user", "contact"]),
        .init("person.2.fill", "两个人", .communication, ["双人", "朋友", "团队", "people", "friends", "team"]),
        .init("camera.fill", "相机", .media, ["拍照", "摄影", "camera", "photo", "photography"]),
        .init("photo.fill", "照片", .media, ["图片", "相册", "photo", "picture", "image", "album"]),
        .init("video.fill", "视频", .media, ["摄像机", "录像", "视频", "video", "camera", "movie"]),
        .init("music.note", "音乐", .media, ["音符", "音乐", "歌曲", "music", "song", "note"]),
        .init("headphones", "耳机", .media, ["音乐", "收听", "headphones", "audio", "listen"]),
        .init("play.fill", "播放", .media, ["开始", "音乐", "play", "start", "media"]),
        .init("gamecontroller.fill", "游戏", .media, ["游戏手柄", "游戏", "娱乐", "game", "controller", "gaming"]),
        .init("film.fill", "胶片", .media, ["电影", "影院", "film", "movie", "cinema"]),
        .init("paintpalette.fill", "调色板", .media, ["调色盘", "绘画", "美术", "palette", "paint", "art", "color"]),
        .init("pencil", "铅笔", .media, ["编辑", "书写", "pencil", "edit", "write"]),
        .init("note.text", "备忘录", .productivity, ["笔记", "备忘录", "记录", "note", "memo", "write"]),
        .init("checklist", "清单", .productivity, ["待办", "任务", "checklist", "todo", "task"]),
        .init("calendar", "日历", .productivity, ["日期", "日程", "calendar", "date", "schedule"]),
        .init("clock.fill", "时钟", .productivity, ["时间", "提醒", "clock", "time", "alarm"]),
        .init("timer", "计时器", .productivity, ["倒计时", "秒表", "timer", "countdown", "stopwatch"]),
        .init("bell.fill", "铃铛", .essentials, ["通知", "提醒", "bell", "notification", "reminder"]),
        .init("gearshape.fill", "设置", .technology, ["齿轮", "偏好", "settings", "gear", "preferences"]),
        .init("wrench.and.screwdriver.fill", "工具", .technology, ["维修工具", "扳手", "螺丝刀", "修理", "tools", "repair", "wrench"]),
        .init("lock.fill", "锁", .technology, ["安全", "隐私", "lock", "security", "privacy"]),
        .init("key.fill", "钥匙", .technology, ["密码", "解锁", "key", "password", "unlock"]),
        .init("shield.fill", "盾牌", .technology, ["保护", "安全", "shield", "protect", "security"]),
        .init("qrcode", "二维码", .technology, ["扫码", "扫描", "qr", "scan", "code"]),
        .init("barcode", "条形码", .technology, ["扫码", "商品", "barcode", "scan", "product"]),
        .init("doc.fill", "文档", .productivity, ["文件", "资料", "document", "file", "paper"]),
        .init("folder.fill", "文件夹", .productivity, ["目录", "分组", "folder", "directory", "group"]),
        .init("tray.fill", "收件箱", .productivity, ["收件盘", "收件箱", "整理", "tray", "inbox", "organize"]),
        .init("archivebox.fill", "归档盒", .productivity, ["归档", "存储", "archive", "storage", "box"]),
        .init("externaldrive.fill", "硬盘", .technology, ["外置硬盘", "备份", "磁盘", "external drive", "disk", "backup"]),
        .init("network", "网络", .technology, ["联网", "连接", "network", "internet", "connection"]),
        .init("globe", "地球", .travel, ["全球", "网站", "globe", "world", "website", "web"]),
        .init("safari.fill", "指南针", .technology, ["浏览器", "网页", "上网", "safari", "browser", "web"]),
        .init("map.fill", "地图", .travel, ["导航", "路线", "map", "navigation", "route"]),
        .init("location.fill", "位置", .travel, ["定位", "位置", "导航", "location", "position", "gps"]),
        .init("car.fill", "汽车", .travel, ["开车", "驾驶", "car", "drive", "vehicle"]),
        .init("bicycle", "自行车", .travel, ["骑行", "单车", "bicycle", "bike", "cycling"]),
        .init("airplane", "飞机", .travel, ["航班", "飞行", "airplane", "flight", "fly"]),
        .init("tram.fill", "电车", .travel, ["有轨电车", "电车", "轨道", "tram", "streetcar", "transit"]),
        .init("figure.walk", "步行", .health, ["散步", "运动", "walk", "walking", "steps"]),
        .init("figure.run", "跑步", .health, ["运动", "锻炼", "run", "running", "exercise"]),
        .init("cart.fill", "购物", .shopping, ["购物车", "购物", "购买", "cart", "shopping", "buy"]),
        .init("bag.fill", "购物袋", .shopping, ["商店", "购买", "bag", "shop", "purchase"]),
        .init("creditcard.fill", "银行卡", .shopping, ["信用卡", "支付", "银行卡", "credit card", "payment", "bank"]),
        .init("gift.fill", "礼物", .shopping, ["赠送", "节日", "gift", "present", "holiday"]),
        .init("cup.and.saucer.fill", "咖啡杯", .food, ["咖啡", "茶", "coffee", "cafe", "tea", "cup"]),
        .init("fork.knife", "餐饮", .food, ["餐具", "吃饭", "餐厅", "food", "restaurant", "dining"]),
        .init("leaf.fill", "叶子", .nature, ["树叶", "植物", "环保", "leaf", "plant", "green"]),
        .init("flame.fill", "火焰", .nature, ["热量", "火", "flame", "fire", "heat"]),
        .init("drop.fill", "水滴", .nature, ["饮水", "水", "drop", "water", "drink"]),
        .init("pawprint.fill", "爪印", .nature, ["宠物", "动物", "paw", "pet", "animal"]),
        .init("cross.case.fill", "医疗箱", .health, ["急救", "医疗", "medical", "first aid", "health"]),
        .init("pills.fill", "药品", .health, ["药丸", "吃药", "药品", "pills", "medicine", "medication"]),
        .init("dumbbell.fill", "哑铃", .health, ["健身", "力量", "dumbbell", "fitness", "gym"]),
        .init("lightbulb.fill", "灯泡", .technology, ["照明", "创意", "lightbulb", "light", "idea"]),
        .init("wifi", "无线网络", .technology, ["联网", "无线", "wifi", "wireless", "internet"]),
        .init("checkmark.circle.fill", "完成", .essentials, ["确认", "勾选", "check", "done", "complete"]),
        .init("xmark.circle.fill", "取消", .essentials, ["关闭", "叉号", "cancel", "close", "remove"]),
        .init("plus.circle.fill", "添加", .essentials, ["新增", "加号", "add", "plus", "new"]),
        .init("minus.circle.fill", "减少", .essentials, ["减号", "移除", "minus", "subtract", "remove"]),
        .init("exclamationmark.triangle.fill", "警告", .essentials, ["注意", "错误", "warning", "alert", "error"]),
        .init("questionmark.circle.fill", "帮助", .essentials, ["问题", "说明", "help", "question", "support"]),
        .init("flag.fill", "旗帜", .essentials, ["标记", "目标", "flag", "mark", "goal"]),
        .init("tag.fill", "标签", .essentials, ["分类", "标记", "tag", "label", "category"]),
        .init("person.crop.circle.fill", "个人头像", .communication, ["账户", "用户", "profile", "account", "avatar"]),
        .init("person.3.fill", "群组", .communication, ["团队", "多人", "group", "team", "people"]),
        .init("person.badge.plus", "添加联系人", .communication, ["新增", "朋友", "add contact", "person", "friend"]),
        .init("phone.arrow.up.right", "拨出电话", .communication, ["拨号", "呼出", "phone", "outgoing", "call"]),
        .init("phone.arrow.down.left", "接听电话", .communication, ["来电", "呼入", "phone", "incoming", "call"]),
        .init("bubble.left.fill", "消息气泡", .communication, ["聊天", "短信", "bubble", "chat", "message", "sms"]),
        .init("at", "电子邮件地址", .communication, ["邮箱", "邮件", "email", "address", "mail"]),
        .init("antenna.radiowaves.left.and.right", "无线电波", .communication, ["信号", "广播", "antenna", "signal", "broadcast"]),
        .init("mic.fill", "麦克风", .media, ["录音", "说话", "microphone", "record", "voice"]),
        .init("speaker.wave.2.fill", "扬声器", .media, ["音量", "声音", "speaker", "volume", "sound"]),
        .init("record.circle", "录制", .media, ["录音", "录像", "record", "recording", "capture"]),
        .init("stop.fill", "停止", .media, ["结束", "播放", "stop", "end", "playback"]),
        .init("pause.fill", "暂停", .media, ["等待", "播放", "pause", "hold", "playback"]),
        .init("backward.fill", "快退", .media, ["倒退", "上一首", "backward", "rewind", "previous"]),
        .init("forward.fill", "快进", .media, ["前进", "下一首", "forward", "fast", "next"]),
        .init("tv.fill", "电视", .media, ["节目", "屏幕", "tv", "television", "show"]),
        .init("waveform", "波形", .media, ["声音", "音频", "waveform", "audio", "sound"]),
        .init("scissors", "剪刀", .media, ["裁剪", "剪切", "scissors", "cut", "trim"]),
        .init("doc.text.fill", "文字文档", .productivity, ["文章", "文件", "text", "document", "article"]),
        .init("doc.on.doc.fill", "复制文档", .productivity, ["复制", "副本", "copy", "duplicate", "document"]),
        .init("clipboard.fill", "剪贴板", .productivity, ["粘贴", "复制", "clipboard", "paste", "copy"]),
        .init("list.bullet", "项目列表", .productivity, ["清单", "条目", "list", "bullet", "items"]),
        .init("paperclip", "回形针", .productivity, ["附件", "附加", "paperclip", "attachment", "attach"]),
        .init("signature", "签名", .productivity, ["签字", "手写", "signature", "sign", "handwriting"]),
        .init("books.vertical.fill", "书架", .productivity, ["图书馆", "阅读", "books", "library", "reading"]),
        .init("chart.bar.fill", "柱状图", .productivity, ["统计", "数据", "bar chart", "statistics", "data"]),
        .init("chart.pie.fill", "饼图", .productivity, ["统计", "占比", "pie chart", "statistics", "share"]),
        .init("magnifyingglass", "搜索", .productivity, ["查找", "放大镜", "search", "find", "magnify"]),
        .init("iphone", "手机", .technology, ["设备", "移动", "iphone", "phone", "mobile"]),
        .init("ipad", "平板电脑", .technology, ["设备", "屏幕", "ipad", "tablet", "device"]),
        .init("laptopcomputer", "笔记本电脑", .technology, ["电脑", "便携", "laptop", "computer", "notebook"]),
        .init("desktopcomputer", "台式电脑", .technology, ["电脑", "显示器", "desktop", "computer", "monitor"]),
        .init("keyboard", "键盘", .technology, ["打字", "输入", "keyboard", "type", "input"]),
        .init("printer.fill", "打印机", .technology, ["打印", "纸张", "printer", "print", "paper"]),
        .init("computermouse.fill", "鼠标", .technology, ["点击", "电脑", "mouse", "click", "computer"]),
        .init("server.rack", "服务器", .technology, ["主机", "存储", "server", "host", "storage"]),
        .init("battery.100", "电池", .technology, ["电量", "充电", "battery", "charge", "power"]),
        .init("icloud.fill", "云盘", .technology, ["云端", "同步", "icloud", "cloud", "sync"]),
        .init("bus.fill", "公交车", .travel, ["巴士", "公共交通", "bus", "coach", "transit"]),
        .init("ferry.fill", "渡轮", .travel, ["船舶", "过海", "ferry", "boat", "ship"]),
        .init("sailboat.fill", "帆船", .travel, ["航海", "海洋", "sailboat", "sailing", "boat"]),
        .init("train.side.front.car", "火车", .travel, ["铁路", "列车", "train", "railway", "rail"]),
        .init("car.side.fill", "汽车侧面", .travel, ["开车", "车辆", "car", "vehicle", "drive"]),
        .init("parkingsign.circle.fill", "停车", .travel, ["停车场", "车位", "parking", "park", "car"]),
        .init("signpost.right.fill", "路标", .travel, ["方向", "路线", "signpost", "direction", "route"]),
        .init("airplane.departure", "航班出发", .travel, ["起飞", "机场", "departure", "takeoff", "flight"]),
        .init("airplane.arrival", "航班到达", .travel, ["降落", "机场", "arrival", "landing", "flight"]),
        .init("binoculars.fill", "望远镜", .travel, ["探索", "远眺", "binoculars", "explore", "view"]),
        .init("wallet.pass.fill", "钱包", .shopping, ["票卡", "支付", "wallet", "pass", "payment"]),
        .init("banknote.fill", "纸币", .shopping, ["现金", "钞票", "banknote", "cash", "money"]),
        .init("dollarsign.circle.fill", "美元", .shopping, ["货币", "金额", "dollar", "usd", "currency"]),
        .init("yensign.circle.fill", "人民币与日元", .shopping, ["货币", "金额", "人民币", "日元", "yuan", "yen", "cny", "jpy"]),
        .init("eurosign.circle.fill", "欧元", .shopping, ["货币", "金额", "euro", "eur", "currency"]),
        .init("percent", "百分比", .shopping, ["折扣", "比率", "percent", "discount", "rate"]),
        .init("mug.fill", "马克杯", .food, ["水杯", "饮料", "mug", "cup", "drink"]),
        .init("wineglass.fill", "酒杯", .food, ["红酒", "饮料", "wineglass", "wine", "drink"]),
        .init("birthday.cake.fill", "生日蛋糕", .food, ["庆祝", "甜点", "birthday", "cake", "dessert"]),
        .init("carrot.fill", "胡萝卜", .food, ["蔬菜", "食物", "carrot", "vegetable", "food"]),
        .init("bed.double.fill", "床", .food, ["睡觉", "休息", "bed", "sleep", "rest"]),
        .init("sofa.fill", "沙发", .food, ["客厅", "家具", "sofa", "couch", "furniture"]),
        .init("cloud.fill", "云朵", .nature, ["多云", "天气", "cloud", "cloudy", "weather"]),
        .init("cloud.rain.fill", "下雨", .nature, ["雨天", "天气", "rain", "rainy", "weather"]),
        .init("cloud.snow.fill", "下雪", .nature, ["雪天", "天气", "snow", "snowy", "weather"]),
        .init("snowflake", "雪花", .nature, ["冬天", "寒冷", "snowflake", "winter", "cold"]),
        .init("rainbow", "彩虹", .nature, ["天空", "色彩", "rainbow", "sky", "color"]),
        .init("tree.fill", "树木", .nature, ["森林", "植物", "tree", "forest", "plant"]),
        .init("heart.text.square.fill", "健康记录", .health, ["心脏", "医疗", "heart", "health", "medical"]),
        .init("bandage.fill", "创可贴", .health, ["急救", "伤口", "bandage", "first aid", "wound"]),
        .init("stethoscope", "听诊器", .health, ["医生", "医疗", "stethoscope", "doctor", "medical"]),
        .init("figure.mind.and.body", "身心放松", .health, ["冥想", "正念", "mind", "body", "meditation", "mindfulness"]),
        .init("sportscourt.fill", "运动场", .health, ["球场", "比赛", "sport", "court", "game"]),
        .init("trophy.fill", "奖杯", .health, ["获胜", "比赛", "trophy", "award", "winner"]),
    ]

    private static let entriesByID = Dictionary(uniqueKeysWithValues: entries.map { ($0.id, $0) })

    public static func entry(id: String) -> Entry? { entriesByID[id] }

    /// Whitespace-separated terms use AND matching across the entry's known
    /// metadata. The resolver receives only catalog title/category keys, never
    /// a query or arbitrary ID. Filtering retains the catalog's stable order.
    public static func search(
        query: String,
        category: Category? = nil,
        localizedText: (String) -> String = { $0 }
    ) -> [Entry] {
        let terms = folded(query).split(whereSeparator: \.isWhitespace).map(String.init)
        let candidates = entries.filter { category == nil || $0.category == category }
        guard !terms.isEmpty else { return candidates }
        let categoryText = Dictionary(uniqueKeysWithValues: Category.allCases.map {
            ($0, localizedText($0.titleKey))
        })
        return candidates.filter { entry in
            let text = folded(([entry.id, entry.titleKey, entry.category.titleKey,
                                localizedText(entry.titleKey), categoryText[entry.category] ?? ""] + entry.keywords)
                .joined(separator: " "))
            return terms.allSatisfy { text.contains($0) }
        }
    }

    private static func folded(_ text: String) -> String {
        text.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive],
                     locale: Locale(identifier: "en_US_POSIX"))
    }
}
