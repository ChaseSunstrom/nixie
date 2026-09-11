// The setup backend's JSON API, same origin.
export type Opt = { path: string; type: string; values: string[]; default: unknown; required: boolean; description: string; section: string | null; order: number; secret: string | null };
export type Hardware = { disks: { path: string; size: number; model: string | null; serial: string | null; transport: string | null; id: string | null }[]; nics: { mac: string; name: string; up: boolean }[]; gpu: string; tpm: boolean; efi: boolean };
export type State = { mode: "iso" | "continuation"; state: Record<string, unknown>; done: number[]; host: string; secrets: string[]; layout: { features: Record<string, boolean | number[]> } | null };

async function j<T>(method: string, path: string, body?: unknown): Promise<T> {
  const r = await fetch(path, { method, headers: body !== undefined ? { "Content-Type": "application/json" } : undefined, body: body === undefined ? undefined : JSON.stringify(body) });
  const t = await r.text();
  let data: T & { error?: string };
  try {
    data = JSON.parse(t);
  } catch {
    throw new Error(t || r.statusText);
  }
  if (!r.ok) throw new Error(data.error ?? r.statusText);
  return data;
}
export const api = {
  pairInfo: () => j<{ needsCode: boolean; mode: string; host: string }>("GET", "/api/pair"),
  pair: (code: string) => j<{ ok: boolean }>("POST", "/api/pair", { code }),
  state: () => j<State>("GET", "/api/state"),
  hardware: () => j<Hardware>("GET", "/api/hardware"),
  options: () => j<Opt[]>("GET", "/api/options"),
  plan: () => j<{ hardware: string; site: string }>("GET", "/api/plan"),
  site: (b: Record<string, unknown>) => j<{ ok: boolean; hosts: string[] }>("POST", "/api/site", b),
  config: (b: Record<string, unknown>) => j<{ ok: boolean }>("POST", "/api/config", b),
  secrets: (b: Record<string, string>) => j<{ ok: boolean; have: string[] }>("POST", "/api/secrets", b),
  totpNew: () => j<{ secret: string; uri: string; qr: string }>("GET", "/api/totp/new"),
  totpVerify: (code: string) => j<{ ok: boolean }>("POST", "/api/totp/verify", { code }),
  attestation: () => j<{ text: string }>("GET", "/api/attestation"),
  reboot: () => j<{ ok: boolean }>("POST", "/api/reboot", {}),
  finish: () => j<{ ok: boolean; output: string }>("POST", "/api/finish", {}),
  phase: (n: number, body: Record<string, unknown>, onLine: (l: string) => void) =>
    new Promise<{ rc: number; done: number[] }>((resolve, reject) => {
      fetch(`/api/phase/${n}`, { method: "POST", headers: { "Content-Type": "application/json" }, body: JSON.stringify(body) })
        .then(async (r) => {
          if (!r.ok) throw new Error(await r.text());
          const reader = r.body!.getReader();
          const dec = new TextDecoder();
          let buf = "";
          for (;;) {
            const { value, done } = await reader.read();
            if (done) break;
            buf += dec.decode(value, { stream: true });
            let i;
            while ((i = buf.indexOf("\n\n")) >= 0) {
              const ev = buf.slice(0, i);
              buf = buf.slice(i + 2);
              const isDone = ev.startsWith("event: done");
              const data = ev.split("\n").find((l) => l.startsWith("data: "))?.slice(6) ?? "null";
              if (isDone) resolve(JSON.parse(data));
              else onLine(JSON.parse(data));
            }
          }
        })
        .catch(reject);
    }),
};
