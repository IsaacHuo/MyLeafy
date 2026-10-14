import { PageHeader } from "../components/ui";
export function ManualPage() {
  return (
    <>
      <PageHeader title="运营手册" description="常用流程、数据口径与权限边界" />
      <div className="studio-detail studio-card">
        <h3>处理顺序</h3>
        <p>
          从待办页面处理举报、反馈、投票审核与发布异常，再维护学校和资料名录。操作前阅读详情证据，保留异常请求
          ID。
        </p>
        <h3>指标口径</h3>
        <p>
          用户总数是非演示资料数，资料完善表示已设置有效昵称，不代表近期使用。
          内容与互动统计来自已保存的业务记录，时间范围采用北京时间自然日。
        </p>
        <h3>权限与发布</h3>
        <p>
          只读管理员查看业务数据；运营管理员处理内容；超级管理员管理账号、会话、诊断与敏感导出。Android
          正式发布必须本人下载验收并确认，iOS 使用 App Store Connect。
        </p>
        <h3>数据检查</h3>
        <p>
          数据质量页仅检查和定位异常，不直接修库。诊断页展示已记录的运行和队列状态，没有记录的数据明确显示未采集。
        </p>
      </div>
    </>
  );
}
