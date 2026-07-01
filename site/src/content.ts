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
  operatorName: "MyLeafy 开发者",
  operatorNote: "公开开发者名称以 App Store 产品页显示为准。",
  updatedAt: "2026 年 6 月 24 日"
};

export const navItems = [
  { label: "Product", href: "/#product" },
  { label: "Data", href: "/#data" },
  { label: "Community", href: "/#community" },
  { label: "Support", href: "/support" },
  { label: "Privacy", href: "/privacy" }
];

export const appStoreLinks = [
  { label: "技术支持网址", value: site.supportUrl },
  { label: "隐私政策网址", value: site.privacyUrl },
  { label: "Marketing URL", value: site.homeUrl },
  { label: "User Privacy Choices URL", value: site.privacyChoicesUrl }
];

export const capabilityStats = [
  { label: "课表", value: "当前周缓存" },
  { label: "教务", value: "校园网直连" },
  { label: "社区", value: "校园交流" },
  { label: "隐私", value: "边界清晰" },
  { label: "支持", value: "App 内反馈" }
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
    label: "Timetable",
    title: "打开后先看今天",
    body: "当前周、今日课程、课程详情、课前提醒和最近一次同步状态放在同一个入口。",
    detail: "离线可看"
  },
  {
    icon: GraduationCap,
    label: "Academics",
    title: "学业工具集中收口",
    body: "成绩、考试、荣誉记录、教学计划、培养方案和空教室都可以在学业入口查看。",
    detail: "教务直连"
  },
  {
    icon: ChatsCircle,
    label: "Community",
    title: "校园讨论有边界",
    body: "帖子、评论、点赞、收藏、公告和通知由社区服务承接，和教务密码分开处理。",
    detail: "匿名会话"
  },
  {
    icon: UserCircle,
    label: "Profile",
    title: "个人资料与常用入口",
    body: "共享课表、个性化、主题、缓存同步、反馈和隐私入口都放在我的页面。",
    detail: "设备优先"
  },
  {
    icon: Star,
    label: "Ratings",
    title: "评教保持轻量",
    body: "课程和教师评分以星级统计呈现，帮助同学快速了解整体反馈。",
    detail: "低负担"
  },
  {
    icon: BellSimple,
    label: "Feedback",
    title: "问题可以带上下文",
    body: "App 内反馈可附带设备、版本、登录状态和最近同步时间，定位同步异常更快。",
    detail: "少来回"
  },
  {
    icon: LockKey,
    label: "Privacy",
    title: "把来源讲清楚",
    body: "学校教务、本机缓存、社区服务和官网托管分开说明，使用前就能了解数据来源。",
    detail: "可解释"
  },
  {
    icon: Cloud,
    label: "Hosting",
    title: "官网保持静态透明",
    body: "公开站承接介绍、支持、隐私政策和 App Store 链接，信息保持简单清楚。",
    detail: "无 Cookie"
  }
];

export const appScreenshots = [
  {
    label: "Timetable",
    title: "课表",
    body: "当前周课程、今日日期和底部主入口清晰呈现。",
    image: "/media/leafy-shot-timetable.png",
    alt: "MyLeafy 课表页截图"
  },
  {
    label: "Community",
    title: "社区",
    body: "学习交流、闲聊和公告以轻量卡片组织。",
    image: "/media/leafy-shot-community.png",
    alt: "MyLeafy 社区页截图"
  },
  {
    label: "Academics",
    title: "学业",
    body: "成绩、考试和荣誉记录作为独立学业入口。",
    image: "/media/leafy-shot-academics.png",
    alt: "MyLeafy 学业页截图"
  },
  {
    label: "Profile",
    title: "我的",
    body: "共享课表、个性化、缓存和支持入口集中在资料页。",
    image: "/media/leafy-shot-profile.png",
    alt: "MyLeafy 我的页截图"
  }
];

export const workflowCards: Array<{
  icon: IconComponent;
  title: string;
  body: string;
}> = [
  {
    icon: DeviceMobile,
    title: "面向每天打开的手机场景",
    body: "MyLeafy 围绕学生每天会打开的入口组织内容，让课表、学业、社区和个人功能更容易找到。"
  },
  {
    icon: Database,
    title: "数据来源分层展示",
    body: "学校页面、本机缓存、社区服务和静态官网分工清楚，用户可以了解每类数据的来源和用途。"
  },
  {
    icon: Lifebuoy,
    title: "支持入口可直接用于 App Store",
    body: "技术支持、隐私政策、Marketing URL 和隐私选择链接都保持公开、稳定、可提交。"
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
    title: "打开后先看今天",
    body: "课表是默认首页。MyLeafy 展示当前周课程、今日摘要、课程详情和最近一次成功同步的数据，用于教务系统不可用时兜底。"
  },
  {
    icon: GraduationCap,
    label: "发现",
    title: "教务工具集中到一个入口",
    body: "成绩、考试安排、教学培养、自习室、校历、通知、社区和评教放在发现页，底部只保留课表、发现和我的三个主入口。"
  },
  {
    icon: UserCircle,
    label: "我的",
    title: "资料、收藏和支持收口",
    body: "我的页管理社区资料、发帖记录、点赞评论、共享课表、常用链接、主题色、深色模式、缓存同步、数据安全和联系入口。"
  },
  {
    icon: ChatsCircle,
    label: "社区",
    title: "校园讨论连接社区服务",
    body: "社区资料、帖子、图片、评论、点赞、通知、公告、反馈、评教和你主动发布的共享课表快照由 MyLeafy 社区服务承接。"
  }
];

export const homeDataBoundaries = [
  {
    label: "学校教务",
    value: "强智系统",
    body: "登录、课表、成绩、考试、教学计划、培养方案和空教室来自学校教务页面。"
  },
  {
    label: "本机缓存",
    value: "SwiftData",
    body: "最近同步的课程、成绩、备注、提醒、收藏和倒计时保存在当前设备。"
  },
  {
    label: "社区服务",
    value: "Supabase",
    body: "资料、帖子、评论、点赞、通知、公告、反馈、评教评分和你主动发布的共享课表快照保存在 MyLeafy 社区服务。"
  },
  {
    label: "官网托管",
    value: "Cloudflare",
    body: "本网站用于公开介绍、技术支持和隐私政策，同时提供 App Store 所需的公开链接。"
  }
];

export const resourceLinks = [
  {
    title: "技术支持",
    body: "登录、同步、解析、社区或评教问题都可以从这里开始。",
    href: site.supportUrl,
    cta: "打开支持页"
  },
  {
    title: "隐私政策",
    body: "查看 MyLeafy 如何处理教务登录、本地缓存、社区和反馈数据。",
    href: site.privacyUrl,
    cta: "阅读政策"
  },
  {
    title: "隐私选择",
    body: "访问、更正、删除社区资料或反馈内容的请求入口。",
    href: site.privacyChoicesUrl,
    cta: "查看选择"
  }
];

export const footerGroups = [
  {
    title: "Product",
    links: [
      { label: "课表", href: "/#product" },
      { label: "学业", href: "/#product" },
      { label: "社区", href: "/#community" },
      { label: "共享课表", href: "/share/timetable" }
    ]
  },
  {
    title: "Resources",
    links: [
      { label: "技术支持", href: "/support" },
      { label: "App 内反馈", href: "/support#in-app" },
      { label: "数据边界", href: "/#data" },
      { label: "联系邮箱", href: `mailto:${site.supportEmail}` }
    ]
  },
  {
    title: "Legal",
    links: [
      { label: "隐私政策", href: "/privacy" },
      { label: "隐私选择", href: "/privacy#privacy-rights" },
      { label: "第三方服务", href: "/privacy#third-party" },
      { label: "保存与删除", href: "/privacy#retention" }
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
  "出现问题的页面路径，例如 发现 -> 成绩。",
  "最近一次同步时间，以及错误提示截图或文字。",
  "是否连接校园网、是否重新登录过学校教务。"
];

export const supportTopics: Array<{
  icon: IconComponent;
  title: string;
  body: string;
}> = [
  {
    icon: Lifebuoy,
    title: "技术支持",
    body: "通过邮件或 App 内意见反馈提交问题。建议附上页面路径、错误提示、设备型号和 App 版本。"
  },
  {
    icon: DeviceMobile,
    title: "App 内入口",
    body: "进入 我的 -> 支持 -> 意见反馈，可以附带设备型号、系统版本、App 版本、登录状态和最近同步时间。"
  },
  {
    icon: WarningCircle,
    title: "教务异常",
    body: "学校网络不可达、登录态过期或页面结构变化都可能导致同步失败。建议先重新登录并重试同步。"
  },
  {
    icon: Trash,
    title: "数据请求",
    body: "需要访问、更正或删除社区资料、帖子、反馈等数据时，可以从 App 内反馈，也可以发送邮件说明。"
  }
];

export const privacySummaryCards: Array<{
  icon: IconComponent;
  title: string;
  body: string;
}> = [
  {
    icon: LockKey,
    title: "教务登录独立处理",
    body: "教务密码用于向学校强智教务系统发起登录请求，社区功能使用独立的 MyLeafy 社区会话。"
  },
  {
    icon: Database,
    title: "本地缓存用于离线查看",
    body: "课表、成绩、课程备注、提醒、收藏和同步状态会保存在当前设备。iPhone、iPad 与 Mac 的本地缓存相互独立，不通过 iCloud 同步。"
  },
  {
    icon: Cloud,
    title: "社区数据由 MyLeafy 社区服务承接",
    body: "昵称、头像、帖子、评论、点赞、通知、反馈、评教评分和你主动发布的共享课表快照会保存到 MyLeafy 社区服务。"
  },
  {
    icon: ShieldCheck,
    title: "隐私边界清晰",
    body: "官网用于公开介绍、技术支持和隐私政策说明。MyLeafy 会在隐私政策中更新新增的数据处理方式。"
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
      "学校教务数据：学号、验证码、学校会话 Cookie、课表、成绩、考试安排、教学计划、培养方案、空教室和指定教室占用等数据来自学校强智教务系统。",
      "登录凭据：教务密码用于向学校强智教务系统提交登录请求；本网站不收集教务密码。",
      "本地缓存：最近同步的课程、成绩、课程备注、课前提醒、常用自习室、常用链接、自定义倒计时、主题偏好、同步时间和失败提示会保存在当前设备。iPhone、iPad 与 Mac 各自保存本地副本，不通过 iCloud 同步，也不会从 iPhone 容器读取 Mac 数据。",
      "社区资料：匿名社区会话、绑定的教务学号、显示名、昵称、头像、专业、年级、邮箱验证状态和资料更新时间会用于社区身份。",
      "社区内容：帖子、图片、评论、点赞、通知、公告阅读记录、教师星级评分和评分汇总会保存在 MyLeafy 社区服务。",
      "共享课表：首次发布需要你在 App 内手动触发；发布后，课表同步成功时会更新已发布的共享快照。快照包含课程名、老师、地点、周次、节次、学期和发布时间。",
      "反馈信息：你提交的反馈内容、可选联系方式，以及设备类型、系统版本、App 版本、登录状态和最近课表同步时间会用于定位问题；Mac 版不会读取主机名或系统账号。",
      "照片与文件：MyLeafy 只在你主动选择社区头像、发帖图片或课表底图时读取所选照片；Mac 版通过系统打开或保存面板访问你明确选择的文件。",
      "定位与日历：定位仅用于天气和出行建议；日历权限仅在你主动导出课表或提醒时使用。拒绝权限不会影响社区、成绩等无关功能。"
    ]
  },
  {
    title: "使用目的",
    icon: BookOpen,
    items: [
      "向学校教务系统请求并展示课表、成绩、考试、教学培养和空教室信息。",
      "在设备上缓存最近一次成功同步的数据，支持离线查看和学校服务不可用时的兜底。",
      "提供社区资料、发帖、图片上传、评论、点赞、通知、公告、反馈和评教功能。",
      "在你主动发布后，允许你通过 7 天过期、单次使用的邀请码授权他人只读查看课程快照，并在后续课表同步成功时更新已共享内容。",
      "处理技术支持请求，排查同步失败、登录异常、解析失败、社区服务不可用等问题。",
      "维护社区安全，包括内容删除、禁言限制、发帖频率限制、图片数量限制和后台审计。"
    ]
  },
  {
    id: "third-party",
    title: "第三方服务",
    icon: Cloud,
    items: [
      "北京林业大学强智教务系统用于学校登录和教务数据查询。",
      "Supabase 用于 MyLeafy 社区服务，包括匿名认证、数据库、私有图片存储、Edge Functions、社区通知、反馈、评教、共享课表和运营后台。",
      "Cloudflare 用于 myleafy.space 的 DNS、静态站点托管和 support@myleafy.space 邮件转发。",
      "Apple 系统能力用于 App 分发、照片与文件选择、定位、日历、系统分享、通知和本地存储。"
    ]
  },
  {
    id: "retention",
    title: "保存与删除",
    icon: Trash,
    items: [
      "设备本地数据保存在你的当前设备。iPhone、iPad 与 Mac 的缓存相互独立；你可以在 App 的缓存与同步页面清理课表、成绩、备注、提醒、收藏和相关缓存。",
      "退出登录会清理学校会话和社区会话；为方便离线查看，本地课表和成绩缓存可能继续保留，直到你主动清理。",
      "共享课表关系可以由分享者撤销或停止共享，也可以由查看者移除；未使用的邀请码过期或停止共享后会失效。",
      "社区帖子和评论删除通常以软删除或状态更新方式处理，以保持通知、审计和社区安全记录的一致性。",
      "你可以通过 App 内意见反馈或发送邮件到 support@myleafy.space 请求访问、更正或删除与你相关的社区资料、反馈和内容。"
    ]
  },
  {
    id: "privacy-rights",
    title: "隐私选择与权利",
    icon: ShieldCheck,
    items: [
      "完善社区资料由你自行选择；发帖、评论和点赞前需要完成社区昵称。",
      "共享课表由你自行发布；发布后也可以随时停止共享或撤销某个同学的查看权限。",
      "照片、文件、定位和日历权限由你自行授权；课表、成绩、教学培养、自习室和社区等无关功能可以独立使用。",
      "你可以在邮件中说明要访问、更正或删除的数据范围。为了防止误删，我们可能需要你通过 App 内已登录状态或其他合理方式确认身份。",
      "如果 MyLeafy 未来接入网站分析、广告、支付、订阅、第三方登录或新的数据处理方，本政策会在上线前更新。"
    ]
  },
  {
    title: "安全与限制",
    icon: WarningCircle,
    items: [
      "MyLeafy 会尽量用最小范围处理数据，但学校教务页面结构变化、校园网络限制或第三方服务故障可能影响可用性。",
      "提交支持请求时，建议只提供定位问题所需的信息，避免发送教务密码、验证码或完整身份证件。",
      "社区图片通过私有存储和签名链接读取，但你仍应避免上传包含他人隐私的信息。"
    ]
  },
  {
    title: "联系我们",
    icon: EnvelopeSimple,
    items: [
      `技术支持和隐私请求邮箱：${site.supportEmail}。`,
      "你也可以在 App 内进入 我的 -> 支持 -> 意见反馈 提交问题。",
      `运营者：${site.operatorName}。${site.operatorNote}`,
      `本政策最近更新：${site.updatedAt}。`
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
    body: "Root directory 设置为 site，Build command 设置为 npm run build，Output directory 设置为 dist。"
  },
  {
    icon: EnvelopeSimple,
    title: "Email Routing",
    body: "将 support@myleafy.space 转发到实际收件邮箱后，再把支持网址提交到 App Store Connect。"
  },
  {
    icon: Images,
    title: "公开联系入口",
    body: "官网承接说明、支持邮箱和隐私政策入口，反馈内容可以通过邮件或 App 内反馈提交。"
  },
  {
    icon: BellSimple,
    title: "App 内反馈",
    body: "需要附带设备信息的问题，优先通过 App 内意见反馈提交，方便定位版本和同步状态。"
  },
  {
    icon: Star,
    title: "评教边界",
    body: "评教当前统计 1 到 5 星评分，用于呈现课程和教师的整体反馈。"
  }
];
