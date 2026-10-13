import { useState } from "react";
import { useForm } from "react-hook-form";
import { Leaf, ArrowRight } from "lucide-react";
import { useAdmin } from "../providers/context";
import { Button, ErrorState } from "./ui";
export function AdminLogin() {
  const { login } = useAdmin(),
    [error, setError] = useState<unknown>(null);
  const {
    register,
    handleSubmit,
    formState: { isSubmitting },
  } = useForm<{ username: string; password: string }>();
  return (
    <main className="studio-login">
      <div className="studio-login-card">
        <Leaf className="studio-brand-icon" size={28} />
        <h1>MyLeafy</h1>
        <p>登录运营工作台</p>
        <form
          onSubmit={handleSubmit(async (values) => {
            setError(null);
            try {
              await login(values.username, values.password);
            } catch (err) {
              setError(err);
            }
          })}
        >
          <label>
            账号
            <input autoComplete="username" required {...register("username")} />
          </label>
          <label>
            密码
            <input
              type="password"
              autoComplete="current-password"
              required
              {...register("password")}
            />
          </label>
          {error != null && <ErrorState error={error} />}
          <Button type="submit" variant="primary" disabled={isSubmitting}>
            {isSubmitting ? "正在登录…" : "登录"}
            <ArrowRight size={14} />
          </Button>
        </form>
        <small>受保护的 Cloudflare 管理服务</small>
      </div>
    </main>
  );
}
