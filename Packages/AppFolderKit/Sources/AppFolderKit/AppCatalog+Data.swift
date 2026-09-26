import Foundation

// Data file. `AppCatalog.swift` holds the logic; everything here is content.
//
// To regenerate the `LSApplicationQueriesSchemes` array in
// `Config/AppFolder-Info.plist`:
//
//     swift run --package-path Packages/AppFolderKit appfolder-schemes
//
// `--check` fails if the plist and the catalog disagree, which CI should run.
extension AppCatalog {
    /// Every app we can draw a tile for.
    ///
    /// Ordered Chinese-apps-first, because that is this app's audience. Within a
    /// category, roughly by how many people have it installed.
    ///
    /// Being in this list is cheap and unrestricted: a tile's URL is opened with
    /// `UIApplication.open(_:)`, which Apple documents as *not* gated by
    /// `LSApplicationQueriesSchemes`. The list is therefore a catalogue of names
    /// and icons, not a declaration of intent to anything.
    public static let all: [KnownApp] = [
        // MARK: 社交 / 通讯
        KnownApp(id: "wechat", name: "微信", englishName: "WeChat",
                 scheme: "weixin://", appStoreID: 414478124, category: "社交"),
        KnownApp(id: "qq", name: "QQ", englishName: "QQ",
                 scheme: "mqq://", appStoreID: 444934666, category: "社交"),
        KnownApp(id: "weibo", name: "微博", englishName: "Weibo",
                 scheme: "sinaweibo://", appStoreID: 350962117, category: "社交"),
        KnownApp(id: "xiaohongshu", name: "小红书", englishName: "Xiaohongshu",
                 scheme: "xhsdiscover://", appStoreID: 741292507, category: "社交"),
        KnownApp(id: "douyin", name: "抖音", englishName: "Douyin",
                 scheme: "snssdk1128://", appStoreID: 1142110895, category: "社交"),
        KnownApp(id: "kuaishou", name: "快手", englishName: "Kuaishou",
                 scheme: "kwai://", appStoreID: 440948110, category: "社交"),
        KnownApp(id: "dingtalk", name: "钉钉", englishName: "DingTalk",
                 scheme: "dingtalk://", appStoreID: 930368978, category: "办公"),
        KnownApp(id: "wework", name: "企业微信", englishName: "WeCom",
                 scheme: "wxwork://", appStoreID: 1087897068, category: "办公"),
        KnownApp(id: "feishu", name: "飞书", englishName: "Feishu",
                 scheme: "lark://", appStoreID: 1401729613, category: "办公"),

        // MARK: 支付 / 购物
        KnownApp(id: "alipay", name: "支付宝", englishName: "Alipay",
                 scheme: "alipay://", appStoreID: 333206289, category: "支付"),
        KnownApp(id: "taobao", name: "淘宝", englishName: "Taobao",
                 scheme: "taobao://", appStoreID: 387682726, category: "购物"),
        KnownApp(id: "tmall", name: "天猫", englishName: "Tmall",
                 scheme: "tmall://", appStoreID: 518966501, category: "购物"),
        KnownApp(id: "jd", name: "京东", englishName: "JD",
                 scheme: "openapp.jdmobile://", appStoreID: 414245413, category: "购物"),
        KnownApp(id: "pinduoduo", name: "拼多多", englishName: "Pinduoduo",
                 scheme: "pinduoduo://", appStoreID: 1044283059, category: "购物"),

        // MARK: 出行 / 生活
        KnownApp(id: "amap", name: "高德地图", englishName: "Amap",
                 scheme: "iosamap://", appStoreID: 461703208, category: "出行"),
        KnownApp(id: "baidu-map", name: "百度地图", englishName: "Baidu Maps",
                 scheme: "baidumap://", appStoreID: 452186370, category: "出行"),
        KnownApp(id: "meituan", name: "美团", englishName: "Meituan",
                 scheme: "imeituan://", appStoreID: 423084029, category: "生活"),
        KnownApp(id: "eleme", name: "饿了么", englishName: "Ele.me",
                 scheme: "eleme://", appStoreID: 507161324, category: "生活"),
        KnownApp(id: "dianping", name: "大众点评", englishName: "Dianping",
                 scheme: "dianping://", appStoreID: 351091731, category: "生活"),
        KnownApp(id: "ctrip", name: "携程", englishName: "Trip.com",
                 scheme: "CtripWireless://", appStoreID: 379395415, category: "出行"),

        // MARK: 影音 / 阅读
        KnownApp(id: "bilibili", name: "哔哩哔哩", englishName: "Bilibili",
                 scheme: "bilibili://", appStoreID: 736536022, category: "影音"),
        KnownApp(id: "netease-music", name: "网易云音乐", englishName: "NetEase Cloud Music",
                 scheme: "orpheus://", appStoreID: 590338362, category: "影音"),
        KnownApp(id: "qqmusic", name: "QQ音乐", englishName: "QQ Music",
                 scheme: "qqmusic://", appStoreID: 414603431, category: "影音"),
        KnownApp(id: "kugou", name: "酷狗音乐", englishName: "Kugou",
                 scheme: "kugouURL://", appStoreID: 472208016, category: "影音"),
        KnownApp(id: "youku", name: "优酷", englishName: "Youku",
                 scheme: "youku://", appStoreID: 336141475, category: "影音"),
        KnownApp(id: "iqiyi", name: "爱奇艺", englishName: "iQIYI",
                 scheme: "qiyi-iphone://", appStoreID: 393765873, category: "影音"),
        KnownApp(id: "tencent-video", name: "腾讯视频", englishName: "Tencent Video",
                 scheme: "tenvideo://", appStoreID: 458318329, category: "影音"),
        KnownApp(id: "weread", name: "微信读书", englishName: "WeRead",
                 scheme: "weread://", appStoreID: 952059546, category: "阅读"),
        KnownApp(id: "zhihu", name: "知乎", englishName: "Zhihu",
                 scheme: "zhihu://", appStoreID: 432274380, category: "阅读"),
        KnownApp(id: "douban", name: "豆瓣", englishName: "Douban",
                 scheme: "douban://", appStoreID: 907002334, category: "阅读"),
        KnownApp(id: "toutiao", name: "今日头条", englishName: "Toutiao",
                 scheme: "snssdk141://", appStoreID: 529092160, category: "阅读"),

        // MARK: 国际
        KnownApp(id: "instagram", name: "Instagram", englishName: "Instagram",
                 scheme: "instagram://", appStoreID: 389801252, category: "社交"),
        KnownApp(id: "whatsapp", name: "WhatsApp", englishName: "WhatsApp",
                 scheme: "whatsapp://", appStoreID: 310633997, category: "社交"),
        KnownApp(id: "facebook", name: "Facebook", englishName: "Facebook",
                 scheme: "fb://", appStoreID: 284882215, category: "社交"),
        KnownApp(id: "x", name: "X", englishName: "X",
                 scheme: "twitter://", appStoreID: 333903271, category: "社交"),
        KnownApp(id: "youtube", name: "YouTube", englishName: "YouTube",
                 scheme: "youtube://", appStoreID: 544007664, category: "影音"),
        KnownApp(id: "google-maps", name: "Google 地图", englishName: "Google Maps",
                 scheme: "comgooglemaps://", appStoreID: 585027354, category: "出行"),
        KnownApp(id: "gmail", name: "Gmail", englishName: "Gmail",
                 scheme: "googlegmail://", appStoreID: 422689480, category: "效率"),
        KnownApp(id: "chrome", name: "Chrome", englishName: "Chrome",
                 scheme: "googlechrome://", appStoreID: 535886823, category: "效率"),
        KnownApp(id: "spotify", name: "Spotify", englishName: "Spotify",
                 scheme: "spotify://", appStoreID: 324684580, category: "影音"),
        KnownApp(id: "netflix", name: "Netflix", englishName: "Netflix",
                 scheme: "nflx://", appStoreID: 363590051, category: "影音"),
        KnownApp(id: "telegram", name: "Telegram", englishName: "Telegram",
                 scheme: "tg://", appStoreID: 686449807, category: "社交"),
        KnownApp(id: "slack", name: "Slack", englishName: "Slack",
                 scheme: "slack://", appStoreID: 618783545, category: "办公"),
        KnownApp(id: "discord", name: "Discord", englishName: "Discord",
                 scheme: "discord://", appStoreID: 985746746, category: "社交"),
        KnownApp(id: "reddit", name: "Reddit", englishName: "Reddit",
                 scheme: "reddit://", appStoreID: 1064216828, category: "社交"),
        KnownApp(id: "snapchat", name: "Snapchat", englishName: "Snapchat",
                 scheme: "snapchat://", appStoreID: 447188370, category: "社交"),
        KnownApp(id: "linkedin", name: "LinkedIn", englishName: "LinkedIn",
                 scheme: "linkedin://", appStoreID: 288429040, category: "社交"),
        KnownApp(id: "teams", name: "Microsoft Teams", englishName: "Microsoft Teams",
                 scheme: "msteams://", appStoreID: 1113153706, category: "办公"),
        KnownApp(id: "zoom", name: "Zoom", englishName: "Zoom",
                 scheme: "zoomus://", appStoreID: 546505307, category: "办公"),
        KnownApp(id: "notion", name: "Notion", englishName: "Notion",
                 scheme: "notion://", appStoreID: 1232780281, category: "效率"),
        KnownApp(id: "github", name: "GitHub", englishName: "GitHub",
                 scheme: "github://", appStoreID: 1477376905, category: "效率"),
        KnownApp(id: "figma", name: "Figma", englishName: "Figma",
                 scheme: "figma://", appStoreID: 1152747299, category: "效率"),
        KnownApp(id: "obsidian", name: "Obsidian", englishName: "Obsidian",
                 scheme: "obsidian://", appStoreID: 1557175442, category: "效率"),
        KnownApp(id: "uber", name: "Uber", englishName: "Uber",
                 scheme: "uber://", appStoreID: 368677368, category: "出行"),
        KnownApp(id: "airbnb", name: "Airbnb", englishName: "Airbnb",
                 scheme: "airbnb://", appStoreID: 401626263, category: "出行"),

        // MARK: 系统
        KnownApp(id: "shortcuts", name: "快捷指令", englishName: "Shortcuts",
                 scheme: "shortcuts://", appStoreID: nil, category: "系统"),

        // MARK: 待验证
        // Real apps whose scheme we have only from a single unverified source.
        // Kept out of the default picker (`Confidence.unverified`), and excluded
        // from the query budget, but available if a user searches for them —
        // adding a tile for one of these is a bet, and the editor is where the
        // user finds out whether it paid off.
        KnownApp(id: "ximalaya", name: "喜马拉雅", englishName: "Ximalaya",
                 scheme: "ximalaya.mainapp://", appStoreID: 876336838, category: "影音",
                 confidence: .unverified),
        KnownApp(id: "goofish", name: "闲鱼", englishName: "Goofish",
                 scheme: "fleamarket://", appStoreID: 510909506, category: "购物",
                 confidence: .unverified),
        KnownApp(id: "tencent-meeting", name: "腾讯会议", englishName: "Tencent Meeting",
                 scheme: "wemeet://", appStoreID: 1484048379, category: "办公",
                 confidence: .unverified),
        KnownApp(id: "baidu", name: "百度", englishName: "Baidu",
                 scheme: "baiduboxapp://", appStoreID: 382201985, category: "效率",
                 confidence: .unverified),
        KnownApp(id: "xianyu-custom", name: "自定义链接", englishName: "Custom Link",
                 scheme: "https://", appStoreID: nil, category: "系统",
                 confidence: .unverified),
    ]
}
