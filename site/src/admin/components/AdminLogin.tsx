import { useState } from "react";
import { useLogin, useNotify } from "react-admin";
import { Box, Button, Card, CircularProgress, TextField, Typography } from "@mui/material";

export function AdminLogin() {
  const login = useLogin();
  const notify = useNotify();
  const [username, setUsername] = useState("");
  const [password, setPassword] = useState("");
  const [loading, setLoading] = useState(false);

  async function submit(event: React.FormEvent) {
    event.preventDefault();
    setLoading(true);
    try {
      await login({ username, password });
    } catch (error) {
      notify(error instanceof Error ? error.message : "登录失败。", { type: "error" });
    } finally {
      setLoading(false);
    }
  }

  return (
    <Box minHeight="100dvh" display="grid" sx={{ placeItems: "center", bgcolor: "#f5faf7", p: 3 }}>
      <Card component="form" onSubmit={submit} sx={{ width: "min(100%, 420px)", p: 4, borderRadius: 2 }}>
        <Typography color="primary" fontWeight={700} variant="overline">MyLeafy Admin</Typography>
        <Typography variant="h4" fontWeight={700} mt={1} mb={3}>社区管理后台</Typography>
        <TextField label="账号" autoComplete="username" value={username} onChange={(event) => setUsername(event.target.value)} fullWidth required margin="normal" />
        <TextField label="密码" type="password" autoComplete="current-password" value={password} onChange={(event) => setPassword(event.target.value)} fullWidth required margin="normal" />
        <Button type="submit" variant="contained" size="large" fullWidth disabled={loading} sx={{ mt: 3 }}>
          {loading ? <CircularProgress color="inherit" size={22} /> : "登录"}
        </Button>
      </Card>
    </Box>
  );
}
