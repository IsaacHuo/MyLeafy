export type AdminRole = "super_admin" | "operator" | "viewer";

export type AdminAccount = {
  id: string;
  username: string;
  display_name: string;
  role: AdminRole;
  active: boolean;
  last_login_at?: string | null;
  created_at?: string;
  updated_at?: string;
};

export type LoginResponse = {
  token: string;
  expires_at: string;
  admin: AdminAccount;
};

export type AdminSession = LoginResponse;

export async function login(username: string, password: string): Promise<LoginResponse> {
  return invoke<LoginResponse>("admin-login", { username, password });
}

export async function fetchCurrentAdmin(token: string): Promise<AdminAccount> {
  const response = await invoke<{ admin: AdminAccount }>("admin-me", {}, token);
  return response.admin;
}

export async function logout(token: string): Promise<void> {
  await invoke("admin-logout", {}, token);
}

export async function adminAction<T>(
  token: string,
  action: string,
  params: Record<string, unknown> = {}
): Promise<T> {
  const response = await invoke<{ data: T }>("admin-community", { action, params }, token);
  return response.data;
}

async function invoke<T>(functionName: string, body: unknown, token?: string): Promise<T> {
  const supabaseUrl = import.meta.env.VITE_SUPABASE_URL as string | undefined;
  const supabaseKey = import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY as string | undefined;

  if (!supabaseUrl) {
    throw new Error("Missing Supabase URL.");
  }

  if (!supabaseKey) {
    throw new Error("Missing Supabase publishable key.");
  }

  const response = await fetch(`${supabaseUrl.replace(/\/+$/, "")}/functions/v1/${functionName}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      apikey: supabaseKey,
      ...(token ? { Authorization: `Bearer ${token}` } : {})
    },
    body: JSON.stringify(body ?? {})
  });

  const payload = await response.json().catch(() => ({}));
  if (!response.ok || payload?.error) {
    throw new Error(payload?.error ?? `Request failed with ${response.status}`);
  }

  return payload as T;
}
