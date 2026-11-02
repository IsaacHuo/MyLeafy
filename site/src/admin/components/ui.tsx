import { forwardRef, type ButtonHTMLAttributes, type ReactNode } from "react";
import {
  Button as AntButton,
  Modal,
  Drawer,
  Tag,
  Tooltip,
  Alert,
  Spin,
  Empty as AntEmpty,
  Typography,
} from "antd";
import { Info } from "lucide-react";
import { clsx } from "clsx";
import { twMerge } from "tailwind-merge";
export const cn = (...values: Parameters<typeof clsx>) => twMerge(clsx(values));
export const Button = forwardRef<
  HTMLButtonElement,
  Omit<ButtonHTMLAttributes<HTMLButtonElement>, "color"> & {
    variant?: "primary" | "danger" | "ghost" | "default";
  }
>(({ variant, type = "button", ...props }, ref) => (
  <AntButton
    ref={ref}
    htmlType={type}
    type={
      variant === "primary"
        ? "primary"
        : variant === "ghost"
          ? "text"
          : "default"
    }
    danger={variant === "danger"}
    {...props}
  />
));
Button.displayName = "Button";
export function Dialog({
  open,
  onClose,
  title,
  children,
  side = false,
  busy = false,
}: {
  open: boolean;
  onClose: () => void;
  title: string;
  children: ReactNode;
  side?: boolean;
  busy?: boolean;
}) {
  const common = {
    open,
    title: <h2 style={{ fontSize: 18, margin: 0 }}>{title}</h2>,
    onClose: () => {
      if (!busy) onClose();
    },
    keyboard: !busy,
    maskClosable: false,
    destroyOnHidden: true,
    closable: { disabled: busy, "aria-label": "关闭" },
  };
  return side ? (
    <Drawer {...common} width={640}>
      {children}
    </Drawer>
  ) : (
    <Modal {...common} onCancel={common.onClose} footer={null} width={680}>
      {children}
    </Modal>
  );
}
export function Help({ children }: { children: ReactNode }) {
  return (
    <Tooltip title={children}>
      <button className="studio-help" type="button" aria-label="指标说明">
        <Info size={14} />
      </button>
    </Tooltip>
  );
}
export function Badge({
  children,
  tone = "neutral",
}: {
  children: ReactNode;
  tone?: string;
}) {
  return (
    <Tag
      color={
        tone === "success"
          ? "success"
          : tone === "danger"
            ? "error"
            : tone === "warning"
              ? "warning"
              : undefined
      }
    >
      {children}
    </Tag>
  );
}
export function ErrorState({
  error,
  retry,
}: {
  error: unknown;
  retry?: () => void;
}) {
  return (
    <Alert
      role="alert"
      type="error"
      showIcon
      message="请求未完成"
      description={error instanceof Error ? error.message : String(error)}
      action={retry ? <AntButton onClick={retry}>重试</AntButton> : undefined}
    />
  );
}
export function Loading() {
  return (
    <div role="status" className="studio-loading">
      <Spin />
      <span>正在加载…</span>
    </div>
  );
}
export function Empty({
  children = "当前条件下暂无数据",
}: {
  children?: ReactNode;
}) {
  return (
    <AntEmpty image={AntEmpty.PRESENTED_IMAGE_SIMPLE} description={children} />
  );
}
export function PageHeader({
  title,
  description,
  children,
}: {
  title: string;
  description?: string;
  children?: ReactNode;
}) {
  return (
    <div className="studio-page-header">
      <div>
        <Typography.Title level={1}>{title}</Typography.Title>
        {description && (
          <Typography.Paragraph type="secondary">
            {description}
          </Typography.Paragraph>
        )}
      </div>
      {children}
    </div>
  );
}
