import { forwardRef, type ButtonHTMLAttributes, type ReactNode } from "react";
import { Dialog as Primitive, Tooltip as Tip } from "radix-ui";
import { X, Info } from "lucide-react";
import { cva } from "class-variance-authority";
import { clsx } from "clsx";
import { twMerge } from "tailwind-merge";
export const cn = (...values: Parameters<typeof clsx>) => twMerge(clsx(values));
const variants = cva("studio-button", {
  variants: {
    variant: {
      primary: "primary",
      danger: "danger",
      ghost: "ghost",
      default: "",
    },
  },
  defaultVariants: { variant: "default" },
});
export const Button = forwardRef<
  HTMLButtonElement,
  ButtonHTMLAttributes<HTMLButtonElement> & {
    variant?: "primary" | "danger" | "ghost" | "default";
  }
>(({ className, variant, type = "button", ...props }, ref) => (
  <button
    ref={ref}
    type={type}
    className={cn(variants({ variant }), className)}
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
  return (
    <Primitive.Root
      open={open}
      onOpenChange={(value) => !value && !busy && onClose()}
    >
      <Primitive.Portal>
        <Primitive.Overlay className="studio-overlay" />
        <Primitive.Content
          className={cn("studio-dialog", side && "studio-sheet")}
          onInteractOutside={(e) => e.preventDefault()}
          aria-describedby={undefined}
        >
          <header>
            <Primitive.Title>{title}</Primitive.Title>
            <Button
              aria-label="关闭"
              variant="ghost"
              disabled={busy}
              onClick={onClose}
            >
              <X size={16} />
            </Button>
          </header>
          {children}
        </Primitive.Content>
      </Primitive.Portal>
    </Primitive.Root>
  );
}
export function Help({ children }: { children: ReactNode }) {
  return (
    <Tip.Provider>
      <Tip.Root>
        <Tip.Trigger className="studio-help" aria-label="指标说明">
          <Info size={14} />
        </Tip.Trigger>
        <Tip.Portal>
          <Tip.Content className="studio-tooltip" sideOffset={6}>
            {children}
            <Tip.Arrow />
          </Tip.Content>
        </Tip.Portal>
      </Tip.Root>
    </Tip.Provider>
  );
}
export function Badge({
  children,
  tone = "neutral",
}: {
  children: ReactNode;
  tone?: string;
}) {
  return <span className={`studio-badge ${tone}`}>{children}</span>;
}
export function ErrorState({
  error,
  retry,
}: {
  error: unknown;
  retry?: () => void;
}) {
  return (
    <div className="studio-error" role="alert">
      <strong>请求未完成</strong>
      <p>{error instanceof Error ? error.message : String(error)}</p>
      {retry && <Button onClick={retry}>重试</Button>}
    </div>
  );
}
export function Loading() {
  return (
    <div role="status" className="studio-loading">
      正在加载…
    </div>
  );
}
export function Empty({
  children = "当前条件下暂无数据",
}: {
  children?: ReactNode;
}) {
  return <div className="studio-empty">{children}</div>;
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
        <h1>{title}</h1>
        {description && <p>{description}</p>}
      </div>
      {children}
    </div>
  );
}
