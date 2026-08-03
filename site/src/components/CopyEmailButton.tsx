import { useEffect, useState } from "react";
import { CheckCircle, Copy, WarningCircle } from "@phosphor-icons/react";
import { TapButton } from "./MotionBits";

type CopyState = "idle" | "copying" | "copied" | "error";

export function CopyEmailButton({ email }: { email: string }) {
  const [state, setState] = useState<CopyState>("idle");

  useEffect(() => {
    if (state !== "copied") {
      return undefined;
    }

    const timeout = window.setTimeout(() => setState("idle"), 2200);
    return () => window.clearTimeout(timeout);
  }, [state]);

  async function copyEmail() {
    setState("copying");
    try {
      await navigator.clipboard.writeText(email);
      setState("copied");
    } catch {
      setState("error");
    }
  }

  const Icon = state === "copied" ? CheckCircle : state === "error" ? WarningCircle : Copy;
  const label = state === "copying" ? "正在复制" : state === "copied" ? "已复制" : state === "error" ? "复制失败，请重试" : "复制邮箱地址";
  const toneClass =
    state === "copied"
      ? "border border-success bg-success text-white hover:bg-success"
      : state === "error"
        ? "border border-danger bg-danger text-white hover:bg-danger"
        : state === "copying"
          ? "border border-warning/40 bg-warning/10 text-ivory"
          : "border border-white/20 bg-forest-elevated/80 text-ivory shadow-deep hover:border-white/30 hover:bg-forest-elevated";

  return (
    <div className="grid gap-2">
      <TapButton
        onClick={copyEmail}
        disabled={state === "copying"}
        className={toneClass + " min-h-12 px-5"}
      >
        <Icon size={20} weight="bold" aria-hidden />
        {label}
      </TapButton>
      <span className="min-h-5 text-sm text-ivory/60" role="status" aria-live="polite">
        {state === "copied" ? "邮箱地址已复制到剪贴板。" : state === "error" ? "无法访问剪贴板，请选中邮箱地址并手动复制。" : ""}
      </span>
    </div>
  );
}
