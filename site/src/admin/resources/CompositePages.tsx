import { useState } from "react";
import { Card, CardContent, Tab, Tabs, Typography } from "@mui/material";
import { ResourceList } from "./ResourcePages";
import { resourceConfigs } from "./config";

export function CampusesPage() {
  return <TabbedResources tabs={[{ resource: "campus-requests", label: "学校归属申请" }, { resource: "campuses", label: "学校空间" }]} />;
}

export function PostgraduatePage() {
  return <TabbedResources tabs={[{ resource: "postgraduate", label: "公开来源" }, { resource: "postgraduate-suggestions", label: "用户线索" }]} />;
}

function TabbedResources({ tabs }: { tabs: Array<{ resource: string; label: string }> }) {
  const [selected, setSelected] = useState(0);
  const current = tabs[selected];
  return (
    <>
      <Tabs value={selected} onChange={(_, value) => setSelected(value)} sx={{ mb: 2 }}>
        {tabs.map((tab) => <Tab key={tab.resource} label={tab.label} />)}
      </Tabs>
      <ResourceList resource={current.resource} config={resourceConfigs[current.resource]} />
    </>
  );
}

export function ManualPage() {
  return (
    <Card><CardContent>
      <Typography variant="h4" gutterBottom>运营手册</Typography>
      <Typography paragraph>推荐处理顺序：举报与高风险内容 → 待审核学校与线索 → 用户反馈 → 公告与资料维护。</Typography>
      <Typography variant="h6">权限边界</Typography>
      <Typography paragraph>只读账号只能查看；运营账号可以执行内容与资料操作；超级管理员额外管理账号、会话、审计与敏感导出。所有写操作由 Supabase Edge Function 再次校验并记录审计。</Typography>
      <Typography variant="h6">高风险操作</Typography>
      <Typography paragraph>下架、删除、禁言、撤销会话和批量操作必须填写原因并等待服务端成功。遇到错误请保留界面显示的 request ID，不要重复提交或绕过后台直接修改表。</Typography>
      <Typography variant="h6">校园范围</Typography>
      <Typography>顶栏校园选择会作用于社区、反馈与名录资源；考研公开来源、国家日历和系统管理是全局资源。</Typography>
    </CardContent></Card>
  );
}
