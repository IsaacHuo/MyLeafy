# 系统架构

MyLeafy 同时面对三类性质不同的系统：不稳定的学校网页、强调本地体验的 iOS 客户端，以及需要严格授权的云端社区和运营业务。架构目标是隔离变化、明确权威来源，并让远程故障不会无条件阻断本地体验。

```mermaid
flowchart LR
    Student["学生"]
    Operator["运营人员"]

    subgraph Product["MyLeafy 系统边界"]
        direction TB
        IOS["MyLeafy iOS<br/>课表 · 校园 · 社区 · AI"]
        Local[("设备本地数据<br/>SwiftData · Keychain · 缓存")]
        Web["官网与运营后台<br/>公开页面 · 分享 · 内容治理"]
        IOS -->|读写本地状态| Local
    end

    School["学校教务系统<br/>身份 · 课表 · 成绩 · 考试"]
    Backend["Supabase 业务后端<br/>Auth · Database · Storage · Functions"]

    Student -->|日常学习与校园任务| IOS
    Operator -->|受控运营| Web
    IOS -->|授权访问教务数据| School
    IOS -->|用户会话 + RLS| Backend
    Web -->|管理代理 + 服务端授权| Backend

    classDef actor fill:#F8FAFC,stroke:#64748B,color:#0F172A,stroke-width:1.5px;
    classDef owned fill:#ECF7F0,stroke:#397A5A,color:#173C2B,stroke-width:2px;
    classDef external fill:#FFF8E8,stroke:#B7791F,color:#5F3B0B,stroke-width:1.5px;
    classDef data fill:#EDF4FF,stroke:#4776B5,color:#173B68,stroke-width:1.5px;
    class Student,Operator actor;
    class IOS,Web owned;
    class School,Backend external;
    class Local data;
```

## 运行单元

| 单元 | 部署位置 | 职责 |
|---|---|---|
| MyLeafy iOS App | 用户设备 | 学校登录、数据获取、本地持久化、UI 与普通业务请求 |
| 学校教务系统 | 学校基础设施 | 学校身份、课表、成绩、考试和培养数据 |
| Supabase | 托管云服务 | Auth、PostgreSQL、RLS、Storage、Realtime 与 Edge Functions |
| 官网与运营后台 | Cloudflare Pages | 公开页面、分享落地页、管理界面与管理 API 代理 |

## iOS 分层

```mermaid
flowchart TB
    Presentation["表现层 · Presentation<br/>SwiftUI Views · 页面状态<br/>Navigation Coordinator"]
    Application["应用层 · Application<br/>用例与协调器 · 服务协议<br/>展示投影与预计算"]
    Domain["领域层 · Domain<br/>业务模型 · 纯规则与计算<br/>校园能力描述"]
    Infrastructure["基础设施 · Infrastructure<br/>教务网络 · HTML 解析 · SwiftData<br/>Supabase · 系统服务"]
    External["外部系统<br/>学校教务 · Supabase<br/>WeatherKit · WidgetKit"]

    Presentation -->|用户意图| Application
    Application -->|执行业务规则| Domain
    Application -->|仅通过协议访问| Infrastructure
    Infrastructure -->|适配外部能力| External

    classDef ui fill:#F0F7FF,stroke:#4776B5,color:#173B68,stroke-width:2px;
    classDef core fill:#ECF7F0,stroke:#397A5A,color:#173C2B,stroke-width:2px;
    classDef adapter fill:#F8FAFC,stroke:#64748B,color:#1E293B,stroke-width:1.5px;
    classDef external fill:#FFF8E8,stroke:#B7791F,color:#5F3B0B,stroke-width:1.5px;
    class Presentation ui;
    class Application,Domain core;
    class Infrastructure adapter;
    class External external;
```

```text
leafy/
├── App/          应用启动、根导航、主题与生命周期
├── Core/         依赖、持久化、校园能力与跨功能基础设施
├── Features/     Auth、Timetable、Community、Discover、Profile
├── Services/     教务、Supabase、同步与诊断服务
├── Parsers/      教务 HTML 解析
└── Shared/       跨功能模型与共享组件
```

依赖方向以业务边界为准：

- `Presentation` 负责 SwiftUI View、页面状态与导航适配。
- `Application` 负责用例、协调器、服务协议和数据组合。
- `Domain` 保存不依赖 UI 的模型、规则、投影和纯计算。
- `Services` 与 `Parsers` 隔离外部系统、Cookie、HTML 和网络细节。
- `App` 只做全局组装，不承载页面解析或复杂业务计算。

## 学校数据链路

```mermaid
flowchart TB
    Login["01 · 建立会话<br/>验证码与临时 key · 本地编码 · Cookie 同步"]
    School["02 · 学校教务系统<br/>登录与中间页 · 课表 · 成绩 · 考试 · 培养"]
    Request["03 · 获取并识别页面<br/>URLSession 主链路 · WKWebView 特定兜底"]
    Parse["04 · 解析与建模<br/>SwiftSoup · 领域模型 · 字段校验"]
    Deliver["05 · 本地交付<br/>SwiftData · 页面投影 · SwiftUI / Widget"]
    Recovery["故障分类与恢复<br/>网络：保留缓存<br/>会话：重新认证<br/>页面变化：输出可诊断错误"]

    Login -->|用户授权登录| School
    School -->|返回授权页面| Request
    Request -->|仅传入已识别页面| Parse
    Parse -->|校验成功后更新缓存| Deliver
    Request -.->|网络 / 会话 / 页面异常| Recovery
    Parse -.->|DOM 或字段不符合契约| Recovery
    Recovery -.->|不覆盖最近成功数据| Deliver

    classDef action fill:#F0F7FF,stroke:#4776B5,color:#173B68,stroke-width:2px;
    classDef boundary fill:#FFF8E8,stroke:#B7791F,color:#5F3B0B,stroke-width:1.5px;
    classDef success fill:#ECF7F0,stroke:#397A5A,color:#173C2B,stroke-width:2px;
    classDef recovery fill:#FFF1F2,stroke:#BE5360,color:#6F1D2A,stroke-width:1.5px;
    class Login,Request,Parse action;
    class School boundary;
    class Deliver success;
    class Recovery recovery;
```

典型过程为：用户授权登录 → 建立教务会话 → 访问目标页面 → 识别登录页或中间页 → 解析 HTML → 转换为领域模型 → 写入本地缓存 → 生成页面投影。

必须区分网络失败、会话失效、页面结构变化和数据为空。它们需要不同的恢复策略，不能统一显示为“加载失败”。

## Supabase 边界

```mermaid
flowchart TB
    Client["01 · 非可信客户端<br/>MyLeafy iOS · Publishable key · 用户 JWT<br/>本机教务数据"]
    Gateway["02 · 授权与业务边界<br/>Supabase Auth · Row Level Security · Edge Functions<br/>owner · profile · campus_id"]
    Data["03 · 受保护业务数据<br/>社区与通知 · 共享课表 · 目录与评价<br/>私有图片 Storage"]
    Server["服务端专属能力<br/>service_role · 签名与代理 secret<br/>管理权限与审计"]

    Client -->|匿名或用户会话| Gateway
    Gateway -->|校验通过后访问| Data
    Server -->|仅服务端注入| Gateway
    Server -->|最小权限管理操作| Data
    Client -.->|禁止下发高权限密钥| Server
    Client -.->|默认不上传学校密码与完整教务数据| Data

    classDef untrusted fill:#F8FAFC,stroke:#64748B,color:#1E293B,stroke-width:1.5px;
    classDef guard fill:#F0F7FF,stroke:#4776B5,color:#173B68,stroke-width:2px;
    classDef protected fill:#ECF7F0,stroke:#397A5A,color:#173C2B,stroke-width:2px;
    classDef secret fill:#FFF8E8,stroke:#B7791F,color:#5F3B0B,stroke-width:1.5px;
    class Client untrusted;
    class Gateway guard;
    class Data protected;
    class Server secret;
    linkStyle 4,5 stroke:#BE5360,stroke-width:2px,stroke-dasharray:5 5;
```

- iOS 使用 publishable key 和用户会话。
- 数据授权依赖 RLS、资源所有权和校园范围。
- Storage 使用私有 bucket、受控路径和 signed URL。
- Edge Functions 承载跨表、外部服务或高风险业务操作。
- `service_role` 和管理代理 secret 不得进入 iOS 或浏览器 bundle。

## 运营后台边界

```mermaid
sequenceDiagram
    actor Admin as 管理员
    participant Browser as React-admin 浏览器
    participant Proxy as Cloudflare Pages Functions
    participant Edge as Supabase Edge Functions
    participant Data as PostgreSQL / Storage / Audit

    Admin->>Browser: 发起管理操作
    Browser->>Proxy: 同域请求 + HttpOnly Cookie + CSRF
    Proxy->>Proxy: 校验 Origin、Method、类型与大小
    Proxy->>Edge: 管理 token + 代理证明 + Request ID
    Edge->>Edge: 校验会话、角色、校园范围与字段白名单
    Edge->>Data: 执行授权后的最小操作
    Data-->>Edge: 返回结果、冲突或拒绝
    Edge-->>Proxy: 状态码 + Request ID + 审计结果
    Proxy-->>Browser: 安全响应 / Set-Cookie
    Browser-xData: 禁止以管理员身份直连数据层
```

管理请求遵循“浏览器 UI → Cloudflare Pages Functions → Supabase Edge Functions → 数据库/Storage”。浏览器不持有管理 token 或服务端密钥；权限、校园范围、参数和审计均在服务端重新校验。

## 架构约束

1. 学校 HTML 与 Cookie 不进入通用页面层。
2. UI 隐藏不作为权限控制。
3. 页面不直接拼装任意数据库查询或管理 action。
4. 本地、学校和 Supabase 数据必须明确各自的权威来源。
5. 新校园差异应收敛到 capability、描述和适配器，而非散落条件判断。
6. 复杂课表使用预计算投影、缓存和窄状态更新控制渲染成本。

完整说明见仓库[架构文档](https://github.com/IsaacHuo/leafy/blob/main/docs/architecture.md)。


