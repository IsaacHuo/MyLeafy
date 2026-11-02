import { useState } from "react";
import { Form, Input, Button, Card, Typography } from "antd";
import { Leaf } from "lucide-react";
import { useAdmin } from "../providers/context";
import { ErrorState } from "./ui";
export function AdminLogin() {
  const { login } = useAdmin(),
    [error, setError] = useState<unknown>(null),
    [busy, setBusy] = useState(false);
  return (
    <main className="studio-login">
      <Card className="studio-login-card">
        <Leaf size={32} aria-hidden />
        <Typography.Title level={1}>MyLeafy</Typography.Title>
        <Typography.Paragraph type="secondary">
          登录运营工作台
        </Typography.Paragraph>
        <Form
          layout="vertical"
          onFinish={async (values: { username: string; password: string }) => {
            setError(null);
            setBusy(true);
            try {
              await login(values.username, values.password);
            } catch (error) {
              setError(error);
            } finally {
              setBusy(false);
            }
          }}
        >
          <Form.Item
            name="username"
            label="账号"
            rules={[{ required: true, message: "请输入账号" }]}
          >
            <Input autoComplete="username" size="large" />
          </Form.Item>
          <Form.Item
            name="password"
            label="密码"
            rules={[{ required: true, message: "请输入密码" }]}
          >
            <Input.Password autoComplete="current-password" size="large" />
          </Form.Item>
          {error != null && <ErrorState error={error} />}
          <Button
            block
            size="large"
            htmlType="submit"
            type="primary"
            loading={busy}
          >
            登录
          </Button>
        </Form>
        <Typography.Text type="secondary">
          MyLeafy · ECS 管理服务
        </Typography.Text>
      </Card>
    </main>
  );
}
