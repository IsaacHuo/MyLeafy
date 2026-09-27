import { useEffect, useState } from "react";
import { Check, Copy } from "@phosphor-icons/react";

export function CopyButton({ value, label, success }: { value: string; label: string; success: string }) {
  const [state, setState] = useState<"idle" | "copying" | "copied" | "error">("idle");
  useEffect(() => {
    if (state !== "copied") return;
    const timeout = window.setTimeout(() => setState("idle"), 2200);
    return () => window.clearTimeout(timeout);
  }, [state]);
  async function copy() {
    setState("copying");
    try { await navigator.clipboard.writeText(value); setState("copied"); }
    catch { setState("error"); }
  }
  return <div className="copy-control"><button type="button" className="button button-secondary" onClick={copy} disabled={state === "copying"}>
    {state === "copied" ? <Check size={18} aria-hidden /> : <Copy size={18} aria-hidden />}
    {state === "copied" ? "已复制" : state === "error" ? "复制失败，请重试" : state === "copying" ? "正在复制" : label}
  </button><span className="copy-status" role="status" aria-live="polite">{state === "copied" ? success : state === "error" ? "无法访问剪贴板，请选中文字并手动复制。" : ""}</span></div>;
}

export function CopyEmailButton({ email }: { email: string }) {
  return <CopyButton value={email} label="复制邮箱地址" success="邮箱地址已复制到剪贴板。" />;
}

