export const downloads = {
  ios: {
    url: "https://apps.apple.com/cn/app/myleafy/id6763968535",
    requirement: "iOS / iPadOS 17 或更新版本",
  },
  android: {
    version: "1.1.0",
    url: "https://github.com/IsaacHuo/MyLeafy/releases/download/android-v1.1.0/MyLeafy-Android-1.1.0.apk",
    releaseUrl: "https://github.com/IsaacHuo/MyLeafy/releases/tag/android-v1.1.0",
    checksumUrl: "https://github.com/IsaacHuo/MyLeafy/releases/download/android-v1.1.0/MyLeafy-Android-1.1.0.apk.sha256",
    requirement: "Android 10 或更新版本",
  },
} as const;

export const supportEmail = "support@myleafy.space";
export const features = [
  { id: "timetable", label: "课表", title: "一周课表", description: "按周查看课程、教室、考试与个人日程，可为课程添加备注与提醒。", details: ["按周查看课程与教室", "为课程添加备注与提醒", "通过邀请码分享只读课表"], image: "/media/app-timetable.webp", caption: "iOS · 课表", alt: "MyLeafy iOS 一周课表中的课程、时间和教室" },
  { id: "community", label: "社区", title: "校园社区", description: "浏览与搜索校园帖子，发布图文、参与评论，并接收互动通知。", details: ["浏览分类与热门讨论", "发布图文与评论", "收藏帖子并查看通知"], image: "/media/app-community.webp", caption: "iOS · 社区", alt: "MyLeafy iOS 校园社区的帖子列表" },
  { id: "schedule", label: "日迹", title: "个人日程与随记", description: "管理个人日程，记录支持 Markdown 与标签的随记，数据保存在本机。", details: ["个人日程与课表一同查看", "随记支持 Markdown 与标签", "数据保存在本机"], image: null, caption: "", alt: "" },
  { id: "campus", label: "校园", title: "教务与校园工具", description: "查询成绩、考试、空闲教室、校历与作息等常用信息。", details: ["成绩、考试与教学培养", "空闲教室、校历与作息", "校园生活与评价工具"], image: "/media/app-academics.webp", caption: "iOS · 校园工具", alt: "MyLeafy iOS 校园页中的教务与校园工具" },
] as const;

export const faqs = [
  { question: "支持哪些学校？", answer: "目前接入北京林业大学教务系统。通用学校入口和免登录入口可用于本机手动添加或导入数据，不代表已接入其他学校的教务系统；社区可用性取决于校园身份。" },
  { question: "Android 版怎么下载和更新？", answer: "通过本页的 Android 下载入口获取官方 GitHub Release 中的 APK。安装时按系统提示允许当前下载来源安装应用。更新可使用 App 内“检查更新”，也可下载新版 APK 覆盖安装，无需先卸载。" },
  { question: "为什么课表或成绩没有更新？", answer: "最近一次成功同步的数据可以离线查看，更新数据需要连接学校教务系统。请先检查校园网或北林 VPN，再在对应页面发起同步；如果 App 提示登录已过期，按提示重新验证。" },
  { question: "iOS 和 Android 的功能完全一样吗？", answer: "两个平台都提供课表、社区、日迹与校园工具。系统集成和部分扩展功能有差异：iOS 提供系统小组件及原生日历集成；Android 通过 ICS 文件导出日程。具体可用功能以当前平台和校园身份为准。" },
  { question: "换设备后，随记会自动同步吗？", answer: "随记与个人日程保存在当前设备，不通过 MyLeafy 服务跨设备同步。换机或卸载前，请使用已有导出能力妥善保存需要的内容。社区资料与内容由独立的社区服务保存。" },
  { question: "分享链接打不开怎么办？", answer: "请确认安装了最新版本的 MyLeafy。共享课表也可以复制完整邀请码，在“我的 → 共享课表”中添加。邀请码有效期为 7 天且只能接受一次；帖子被删除或不可见时，App 会提示原因。" },
] as const;

