import {
  BellSimple,
  BookOpen,
  Browser,
  CalendarBlank,
  ChatsCircle,
  Cloud,
  Database,
  DeviceMobile,
  EnvelopeSimple,
  GraduationCap,
  Images,
  Lifebuoy,
  LockKey,
  ShieldCheck,
  Star,
  Trash,
  UserCircle,
  WarningCircle
} from "@phosphor-icons/react";
import type { IconComponent } from "./types";

export const site = {
  domain: "myleafy.space",
  homeUrl: "https://myleafy.space/",
  supportUrl: "https://myleafy.space/support",
  privacyUrl: "https://myleafy.space/privacy",
  appStoreUrl: "https://apps.apple.com/cn/search?term=MyLeafy%20%E5%8C%97%E4%BA%AC%E6%9E%97%E4%B8%9A%E5%A4%A7%E5%AD%A6",
  privacyChoicesUrl: "https://myleafy.space/privacy#privacy-rights",
  supportEmail: "support@myleafy.space",
  operatorName: "MyLeafy Developer",
  operatorNote: "公开开发者名称与 App Store 产品页显示一致。",
  updatedAt: "2026 年 8 月 9 日"
};

export const navItems = [
  { label: "首页", href: "/" },
  { label: "功能", href: "/features" },
  { label: "支持", href: "/support" },
  { label: "隐私", href: "/privacy" }
];

export const appStoreLinks = [
  { label: "支持页面", value: site.supportUrl },
  { label: "隐私政策", value: site.privacyUrl },
  { label: "产品官网", value: site.homeUrl },
  { label: "隐私选择", value: site.privacyChoicesUrl }
];

export const capabilityStats = [
  { label: "服务校园", value: "北京林业大学" },
  { label: "默认入口", value: "课表" },
  { label: "教务数据", value: "教务系统" },
  { label: "社区内容", value: "独立保存" },
  { label: "技术支持", value: "App 内反馈" }
];

export const productCards: Array<{
  icon: IconComponent;
  label: string;
  title: string;
  body: string;
  detail: string;
}> = [
  {
    icon: CalendarBlank,
    label: "课表",
    title: "先看今天",
    body: "当前周、今日课程、课程详情、考试和提醒都围绕课表组织。",
    detail: "默认"
  },
  {
    icon: GraduationCap,
    label: "教务",
    title: "教务工具集中管理",
    body: "成绩、考试、学习计划、毕业要求、学分和教室查询集中在教务入口。",
    detail: "直达"
  },
  {
    icon: ChatsCircle,
    label: "社区",
    title: "社区与学校登录分开",
    body: "帖子、图片、评论、点赞、收藏、公告与通知保存在独立的 MyLeafy 社区服务中，与学校登录数据相互独立。",
    detail: "校园"
  },
  {
    icon: UserCircle,
    label: "我的",
    title: "设置与安全集中管理",
    body: "共享课表、主题、缓存同步、链接、数据安全、支持与隐私控制集中在“我的”。",
    detail: "设备"
  },
  {
    icon: Star,
    label: "评价",
    title: "轻量评价",
    body: "课程与教师评价使用星级摘要，快速提供参考，不增加繁重的反馈流程。",
    detail: "简洁"
  },
  {
    icon: BellSimple,
    label: "反馈",
    title: "反馈附带必要上下文",
    body: "App 内反馈可包含设备、系统、App 版本、登录状态和上次同步时间。",
    detail: "更快"
  },
  {
    icon: LockKey,
    label: "隐私",
    title: "数据来源清晰列明",
    body: "学校教务数据、本地缓存、社区服务和官网托管分别说明。",
    detail: "清楚"
  },
  {
    icon: Cloud,
    label: "链接",
    title: "公共链接保持稳定",
    body: "支持、隐私政策、产品官网和隐私选择链接可用于 App Store Connect。",
    detail: "公开"
  }
];

export const appScreenshots = [
  {
    label: "课表",
    title: "一周课表",
    body: "当前周、今日课程、课程详情与提醒位于第一层。",
    image: "/media/app-timetable.webp",
    alt: "iPhone 17 Pro 上的 MyLeafy 一周课表"
  },
  {
    label: "社区",
    title: "校园社区",
    body: "动态、分类、热门帖子、公告与通知集中在独立入口。",
    image: "/media/app-community.webp",
    alt: "iPhone 17 Pro 上的 MyLeafy 校园社区"
  },
  {
    label: "教务",
    title: "教务工具",
    body: "成绩、考试、教室、校历、学习计划与评价集中管理。",
    image: "/media/app-academics.webp",
    alt: "iPhone 17 Pro 上的 MyLeafy 教务工具"
  }
];

export const featureShowcases = [
  {
    label: "课表",
    title: "一周课表",
    body: "打开 MyLeafy 即可查看本周课程，并按真实教学节奏排列每天的安排。",
    image: "/media/app-timetable.webp",
    alt: "iPhone 17 Pro 上的 MyLeafy 一周课表"
  },
  {
    label: "教务",
    title: "教务工具",
    body: "成绩、荣誉、学习计划、培养方案和其他教务记录集中在一个区域。",
    image: "/media/app-academics.webp",
    alt: "iPhone 17 Pro 上的 MyLeafy 教务工具"
  },
  {
    label: "社区",
    title: "校园社区",
    body: "浏览校园帖子、搜索讨论、关注公告，参与日常交流。",
    image: "/media/app-community.webp",
    alt: "iPhone 17 Pro 上的 MyLeafy 校园社区"
  },
  {
    label: "成绩",
    title: "成绩概览",
    body: "集中查看 GPA、加权平均分、学分、风险课程与学期成绩。",
    image: "/media/app-grades.webp",
    alt: "iPhone 17 Pro 上的 MyLeafy 成绩概览"
  },
  {
    label: "校历",
    title: "教学日历",
    body: "直接了解当前教学周、学期节奏和即将到来的假期，无需手动数日期。",
    image: "/media/app-calendar.webp",
    alt: "iPhone 17 Pro 上的 MyLeafy 教学日历"
  },
  {
    label: "学习空间",
    title: "学习资料",
    body: "从微信或 QQ 导入文件，整理学习资料，让课程内容靠近校园工具。",
    image: "/media/app-study-space.webp",
    alt: "iPhone 17 Pro 上的 MyLeafy 学习空间"
  },
  {
    label: "教室",
    title: "空闲教室",
    body: "按日期、教室或节次查询空闲教室，并收藏常用教室。",
    image: "/media/app-classroom.webp",
    alt: "iPhone 17 Pro 上的 MyLeafy 空闲教室查询"
  },
  {
    label: "校园",
    title: "场馆信息",
    body: "查看东西校区体育场馆的开放规则与实用信息。",
    image: "/media/app-venues.webp",
    alt: "iPhone 17 Pro 上的 MyLeafy 校园场馆信息"
  },
  {
    label: "校园政策",
    title: "健康政策",
    body: "将密集的校园通知整理为易读的结构化信息，同时保留原始来源。",
    image: "/media/app-health-policy.webp",
    alt: "iPhone 17 Pro 上的 MyLeafy 校园健康政策"
  },
  {
    label: "评价",
    title: "教师评价",
    body: "通过清晰筛选与简明摘要，浏览轻量的教师与课程评价。",
    image: "/media/app-ratings.webp",
    alt: "iPhone 17 Pro 上的 MyLeafy 教师评价"
  }
];

export const workflowCards: Array<{
  icon: IconComponent;
  title: string;
  body: string;
}> = [
  {
    icon: DeviceMobile,
    title: "适合每天快速查看",
    body: "课表优先，社区独立，教务工具集中，“我的”负责设置与安全。"
  },
  {
    icon: Database,
    title: "数据边界清晰",
    body: "学校教务数据、设备数据、校园社区内容与官网公开信息分别说明。"
  },
  {
    icon: Lifebuoy,
    title: "支持与隐私长期公开",
    body: "支持、隐私政策、产品官网与隐私选择均使用稳定的公开链接。"
  }
];

export const featureBands: Array<{
  icon: IconComponent;
  label: string;
  title: string;
  body: string;
}> = [
  {
    icon: CalendarBlank,
    label: "课表",
    title: "打开就看今天",
    body: "课表是默认入口，包含当前周、每日摘要、课程详情和最近一次成功同步。"
  },
  {
    icon: GraduationCap,
    label: "教务",
    title: "教务工具集中在一个入口",
    body: "成绩、考试、学习计划、教室、校历与评价集中在教务入口。"
  },
  {
    icon: UserCircle,
    label: "我的",
    title: "个人资料、分享与支持",
    body: "在“我的”中管理共享课表、个人内容、链接、主题、缓存同步、数据安全与支持。"
  },
  {
    icon: ChatsCircle,
    label: "社区",
    title: "校园讨论",
    body: "社区资料、帖子、图片、评论、点赞、公告、反馈、评价与共享课表数据保存在 MyLeafy 社区服务中。"
  }
];

export const homeDataBoundaries = [
  {
    label: "学校系统",
    value: "教务系统",
    body: "登录、课表、成绩、考试、学习计划、毕业要求与教室查询来自学校系统。"
  },
  {
    label: "设备数据",
    value: "当前设备",
    body: "最近同步的课程、成绩、笔记、提醒、收藏与倒计时保存在当前设备。"
  },
  {
    label: "校园社区",
    value: "MyLeafy 社区",
    body: "社区资料、帖子、评论、点赞、通知、公告、反馈、评价与共享课表数据由独立的社区服务保存。"
  },
  {
    label: "官方网站",
    value: "公开网页",
    body: "提供产品介绍、支持页面、隐私政策与 App Store 公共链接。"
  }
];

export const resourceLinks = [
  {
    title: "技术支持",
    body: "处理登录、同步、解析、社区、评价和共享课表问题。",
    href: site.supportUrl,
    cta: "前往支持"
  },
  {
    title: "隐私政策",
    body: "了解 MyLeafy 如何处理学校登录、设备数据、社区数据、反馈与分享。",
    href: site.privacyUrl,
    cta: "阅读政策"
  },
  {
    title: "隐私选择",
    body: "提交社区资料、反馈或内容数据的访问、更正与删除请求。",
    href: site.privacyChoicesUrl,
    cta: "查看选择"
  }
];

export const footerGroups = [
  {
    title: "产品",
    links: [
      { label: "功能", href: "/features" },
      { label: "数据来源", href: "/features#data" },
      { label: "共享课表", href: "/share/timetable" }
    ]
  },
  {
    title: "资源",
    links: [
      { label: "技术支持", href: "/support" },
      { label: "App 内反馈", href: "/support#in-app" },
      { label: "数据边界", href: "/features#data" },
      { label: "联系邮箱", href: `mailto:${site.supportEmail}` }
    ]
  },
  {
    title: "法律信息",
    links: [
      { label: "隐私政策", href: "/privacy" },
      { label: "隐私选择", href: "/privacy#privacy-rights" },
      { label: "第三方服务", href: "/privacy#third-party" },
      { label: "保留与删除", href: "/privacy#retention" }
    ]
  },
  {
    title: "App Store",
    links: appStoreLinks.map((link) => ({ label: link.label, href: link.value }))
  }
];

export const supportChecklist = [
  "设备型号，例如 iPhone 15、iPad Air 或 Apple 芯片 Mac。",
  "iOS、iPadOS 或 macOS 版本，以及 MyLeafy App 版本。",
  "问题出现的页面路径，例如“教务 → 成绩”。",
  "上次同步时间，以及屏幕上的完整错误信息或截图文字。",
  "是否连接校园网，以及是否已重新登录学校系统。"
];

export const supportTopics: Array<{
  icon: IconComponent;
  title: string;
  body: string;
}> = [
  {
    icon: Lifebuoy,
    title: "技术支持",
    body: "发送邮件或使用 App 内反馈。请尽量附上页面路径、错误信息、设备型号与 App 版本。"
  },
  {
    icon: DeviceMobile,
    title: "App 内反馈",
    body: "打开“我的 → 支持 → 反馈”，可一并提供设备型号、系统版本、App 版本、登录状态与上次同步时间。"
  },
  {
    icon: WarningCircle,
    title: "教务同步问题",
    body: "学校网络中断、会话过期或学校页面调整都可能导致同步失败。请先重新登录，再重试同步。"
  },
  {
    icon: Trash,
    title: "数据请求",
    body: "如需访问、更正或删除社区资料、帖子或反馈数据，请使用 App 内反馈或发送邮件。"
  }
];

export const privacySummaryCards: Array<{
  icon: IconComponent;
  title: string;
  body: string;
}> = [
  {
    icon: LockKey,
    title: "学校登录相互独立",
    body: "学校密码用于向教务系统发起登录。社区功能使用独立的 MyLeafy 会话。"
  },
  {
    icon: Database,
    title: "本地缓存支持离线查看",
    body: "课表、成绩、笔记、提醒、收藏与同步状态保存在当前设备；iPhone、iPad 与 Mac 的缓存彼此独立。"
  },
  {
    icon: Cloud,
    title: "社区数据单独保存",
    body: "昵称、头像、帖子、私有图片与附件、评论、点赞、通知、反馈、评价与共享课表数据保存在独立的 MyLeafy 社区服务中。"
  },
  {
    icon: ShieldCheck,
    title: "政策与支持链接公开可用",
    body: "支持邮箱与隐私政策可在 myleafy.space 访问；新的数据处理方式会同步更新到隐私政策。"
  }
];

export const privacySections: Array<{
  id?: string;
  title: string;
  icon: IconComponent;
  items: string[];
}> = [
  {
    title: "我们处理的数据",
    icon: Database,
    items: [
      "学校教务数据：学号、验证码、学校登录状态、课表、成绩、考试、学习计划、毕业要求、空闲教室与教室占用信息来自教务系统。",
      "登录凭据：学校密码会提交给教务系统用于登录；本网站不收集学校密码。",
      "设备数据：最近同步的课程、成绩、课堂笔记、提醒、收藏教室、链接、倒计时、主题偏好、同步时间与失败信息保存在当前设备；iPhone、iPad 与 Mac 分别保存各自的数据。",
      "社区资料：匿名社区登录状态、绑定学号、显示名称、昵称、头像、专业、年级、邮箱验证状态与资料更新时间用于建立社区身份。",
      "社区内容：帖子、私有图片、文档附件、评论、点赞、公告阅读状态、教师星级评价与评价摘要保存在 MyLeafy 社区服务中。",
      "共享课表：分享由你在 App 中主动创建。发布的课表数据包括课程名称、教师、地点、周次、节次、学期与发布时间。",
      "反馈：你提交的反馈、可选联系方式、设备类型、系统版本、App 版本、登录状态与最近课表同步时间用于技术支持。",
      "照片与文件：MyLeafy 只读取你主动选择的内容。帖子图片与附件在上传前会复制到受保护的 App 存储空间，用于后台发布。",
      "位置与日历：位置仅用于天气与通勤建议；日历权限仅在你导出课表或提醒时使用。"
    ]
  },
  {
    title: "处理目的",
    icon: BookOpen,
    items: [
      "从学校系统请求并显示课表、成绩、考试、学习计划与教室信息。",
      "在当前设备保存最近一次成功同步的数据，便于离线查看。",
      "提供社区资料、发帖、私有图片与附件上传、分层评论、点赞、通知、公告、反馈与评价。",
      "在你主动发布后，通过 7 天有效、仅可使用一次的邀请码共享只读课表。",
      "处理同步失败、登录、解析与社区服务问题。",
      "通过删除机制、发布限制、图片限制与必要的安全记录维护社区安全。"
    ]
  },
  {
    id: "third-party",
    title: "第三方服务",
    icon: Cloud,
    items: [
      "北京林业大学教务系统用于学校登录与教务数据查询。",
      "Supabase 为 MyLeafy 社区服务提供账号、数据和文件存储，以及通知、反馈、评价、共享课表等功能。",
      "Cloudflare 为 myleafy.space 提供官网访问和 support@myleafy.space 邮件转发。",
      "Apple 系统能力用于 App 分发、照片与文件选择、位置、日历、系统分享、通知与本地存储。"
    ]
  },
  {
    id: "retention",
    title: "保留与删除",
    icon: Trash,
    items: [
      "本地设备数据保存在当前设备；iPhone、iPad 与 Mac 的缓存彼此独立。你可以在 App 中清理课表、成绩、笔记、提醒、收藏与相关缓存。",
      "退出登录会清除学校与社区的登录状态。保存在设备上的课表和成绩可能继续保留，以便离线查看，直至你主动清理。",
      "分享者可以撤销共享课表访问，查看者也可以移除已接受的课表；未使用的邀请码会自动过期。",
      "社区帖子与评论删除后，可能继续保留必要的通知和安全记录。删除的帖子图片和附件通常保留 30 天；未解决的举报或管理隐藏状态会暂停文件清理。",
      "未完成的社区上传草稿会在 24 小时后删除。附件类型与容器校验不等同于恶意软件或病毒扫描。",
      "你可以通过 App 内反馈或 support@myleafy.space 请求访问、更正或删除社区资料、反馈或内容数据。"
    ]
  },
  {
    id: "privacy-rights",
    title: "隐私选择与权利",
    icon: ShieldCheck,
    items: [
      "是否完善社区资料由你决定，但发帖、评论与点赞需要设置社区昵称。",
      "共享课表由你主动发布，你可以随时停止分享或撤销查看者。",
      "照片、文件、位置与日历权限由你控制；无需这些权限的课表、成绩、教务工具与社区功能仍可独立使用。",
      "提交请求时，请说明需要访问、更正或删除的数据。我们可能通过 App 内登录状态或其他合理方式确认你的身份。"
    ]
  },
  {
    title: "安全与限制",
    icon: WarningCircle,
    items: [
      "MyLeafy 仅为上述功能处理必要数据，但学校页面调整、校园网络限制与第三方服务中断仍可能影响可用性。",
      "请勿在支持请求中发送学校密码、验证码或完整身份证件。",
      "社区图片与附件使用非公开存储，并通过短时有效的安全链接读取。附件检查不包含病毒扫描；仅打开可信来源的文件，也不要上传他人的隐私信息。"
    ]
  },
  {
    title: "联系我们",
    icon: EnvelopeSimple,
    items: [
      `支持与隐私请求：${site.supportEmail}。`,
      "你也可以在 App 中打开“我的 → 支持 → 反馈”。",
      `运营者：${site.operatorName}。${site.operatorNote}`,
      `最后更新：${site.updatedAt}。`
    ]
  }
];

export const metadataNotes: Array<{
  icon: IconComponent;
  title: string;
  body: string;
}> = [
  {
    icon: Browser,
    title: "Cloudflare Pages",
    body: "根目录：site；构建命令：npm run build；输出目录：dist。"
  },
  {
    icon: EnvelopeSimple,
    title: "邮件转发",
    body: "通过 Cloudflare Email Routing 转发 support@myleafy.space，再将支持页面提交到 App Store Connect。"
  },
  {
    icon: Images,
    title: "公开联系方式",
    body: "支持邮箱与隐私政策链接可公开访问。"
  },
  {
    icon: BellSimple,
    title: "App 内反馈",
    body: "需要设备与同步上下文的问题，建议使用 App 内反馈。"
  },
  {
    icon: Star,
    title: "评价",
    body: "评价目前使用一至五星摘要。"
  }
];
