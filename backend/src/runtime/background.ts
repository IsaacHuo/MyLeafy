const pending = new Set<Promise<unknown>>();
export function defer(work: Promise<unknown>) {
  pending.add(work);
  void work.finally(() => pending.delete(work)).catch(() => console.error(JSON.stringify({event:'background_failed'})));
}
export async function drainBackground() { while (pending.size) await Promise.allSettled([...pending]); }
