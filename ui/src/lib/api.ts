// The Incus REST API over the same origin incusd serves the panel from.
// Every call goes through `req`, so demo mode is one swap at the bottom.
export type Op = { id: string; status: string; class: string; description: string; created_at: string; may_cancel: boolean; resources?: Record<string, string[]>; metadata?: unknown };
export type State = { status: string; pid: number; cpu: { usage: number }; memory: { usage: number; usage_peak: number; total: number }; disk: Record<string, { usage: number }>; network: Record<string, { addresses: { family: string; address: string; scope: string }[]; counters: { bytes_received: number; bytes_sent: number } }> };
export type Instance = { name: string; type: string; status: string; profiles: string[]; config: Record<string, string>; devices: Record<string, Record<string, string>>; expanded_devices?: Record<string, Record<string, string>>; created_at: string; state?: State; architecture?: string; description?: string; location?: string; ephemeral?: boolean };
export type Snapshot = { name: string; created_at: string; expires_at?: string; stateful: boolean; size?: number };
export type Image = { fingerprint: string; aliases: { name: string }[]; properties: Record<string, string>; size: number; uploaded_at: string; type: string; architecture: string };
export type Profile = { name: string; description: string; config: Record<string, string>; devices: Record<string, Record<string, string>>; used_by: string[] };
export type Network = { name: string; type: string; managed: boolean; config: Record<string, string>; used_by: string[]; status?: string; description?: string };
export type NetworkState = { addresses: { family: string; address: string; netmask: string }[]; counters: { bytes_received: number; bytes_sent: number }; hwaddr: string; state: string; type: string; mtu: number };
export type Pool = { name: string; driver: string; config: Record<string, string>; used_by: string[]; status?: string };
export type PoolResources = { space: { used: number; total: number } };
export type Volume = { name: string; type: string; content_type: string; used_by: string[]; config: Record<string, string> };
export type Server = { auth: string; environment?: { server_name: string; kernel_version: string; server_version: string; storage: string; driver: string }; config?: Record<string, string>; auth_methods?: string[]; api_extensions?: string[] };

// Where a guest is reached: the platform's nic ("uplink", or "eth0" in a
// foreign image) before any bridge the guest made inside (podman0, docker0).
export const address = (s?: State): string => {
  const pick = (k: string) => s?.network?.[k]?.addresses.find((a) => a.family === "inet" && a.scope === "global")?.address;
  return pick("uplink") ?? pick("eth0") ?? Object.keys(s?.network ?? {}).map(pick).find(Boolean) ?? "";
};

export class ApiError extends Error {
  constructor(public status: number, message: string) {
    super(message);
  }
}

export interface Backend {
  server(): Promise<Server>;
  instances(): Promise<Instance[]>;
  instance(name: string): Promise<Instance>;
  instanceState(name: string): Promise<State>;
  instanceAction(name: string, action: "start" | "stop" | "restart" | "freeze" | "unfreeze", force?: boolean): Promise<Op>;
  createInstance(body: unknown): Promise<Op>;
  deleteInstance(name: string): Promise<Op>;
  updateInstance(name: string, body: Partial<Instance>): Promise<Op | void>;
  snapshots(name: string): Promise<Snapshot[]>;
  createSnapshot(name: string, snap: string): Promise<Op>;
  deleteSnapshot(name: string, snap: string): Promise<Op>;
  restoreSnapshot(name: string, snap: string): Promise<Op>;
  logs(name: string): Promise<string[]>;
  log(name: string, file: string): Promise<string>;
  files(name: string, path: string): Promise<string[] | { content: string }>;
  putFile(name: string, path: string, content: string): Promise<void>;
  execUrls(name: string, command: string[]): Promise<{ control: string; data: string; op: Op }>;
  images(): Promise<Image[]>;
  pullImage(remote: string, alias: string): Promise<Op>;
  deleteImage(fingerprint: string): Promise<Op>;
  profiles(): Promise<Profile[]>;
  saveProfile(p: Profile, isNew: boolean): Promise<void>;
  deleteProfile(name: string): Promise<void>;
  networks(): Promise<Network[]>;
  networkState(name: string): Promise<NetworkState>;
  pools(): Promise<Pool[]>;
  poolResources(name: string): Promise<PoolResources>;
  volumes(pool: string): Promise<Volume[]>;
  operations(): Promise<Op[]>;
  cancelOperation(id: string): Promise<void>;
  waitOperation(id: string): Promise<Op>;
  updateServer(config: Record<string, string>): Promise<void>;
  metrics(): Promise<string>;
  events(onEvent: (e: { type: string; metadata: unknown; timestamp: string }) => void): () => void;
  readonly demo: boolean;
}

async function req<T>(method: string, path: string, body?: unknown, raw = false): Promise<T> {
  const r = await fetch(`/1.0${path}`, {
    method,
    headers: body !== undefined && !raw ? { "Content-Type": "application/json" } : undefined,
    body: body === undefined ? undefined : raw ? (body as string) : JSON.stringify(body),
  });
  const text = await r.text();
  if (raw && r.ok) return text as unknown as T;
  let j: { type: string; status_code: number; error?: string; metadata: T };
  try {
    j = JSON.parse(text);
  } catch {
    if (!r.ok) throw new ApiError(r.status, text || r.statusText);
    return text as unknown as T;
  }
  if (j.type === "error") throw new ApiError(j.status_code ?? r.status, j.error ?? "error");
  return j.metadata;
}

export const incus: Backend = {
  demo: false,
  server: () => req<Server>("GET", ""),
  instances: () => req<Instance[]>("GET", "/instances?recursion=2"),
  instance: (n) => req<Instance>("GET", `/instances/${n}?recursion=1`),
  instanceState: (n) => req<State>("GET", `/instances/${n}/state`),
  instanceAction: (n, action, force) => req<Op>("PUT", `/instances/${n}/state`, { action, force: !!force, timeout: 30 }),
  createInstance: (body) => req<Op>("POST", "/instances", body),
  deleteInstance: (n) => req<Op>("DELETE", `/instances/${n}`),
  updateInstance: (n, body) => req<Op | void>("PATCH", `/instances/${n}`, body),
  snapshots: (n) => req<Snapshot[]>("GET", `/instances/${n}/snapshots?recursion=1`),
  createSnapshot: (n, s) => req<Op>("POST", `/instances/${n}/snapshots`, { name: s }),
  deleteSnapshot: (n, s) => req<Op>("DELETE", `/instances/${n}/snapshots/${s}`),
  restoreSnapshot: (n, s) => req<Op>("PUT", `/instances/${n}`, { restore: s }),
  logs: (n) => req<string[]>("GET", `/instances/${n}/logs`),
  log: (n, f) => req<string>("GET", `/instances/${n}/logs/${f}`, undefined, true),
  files: async (n, p) => {
    const r = await fetch(`/1.0/instances/${n}/files?path=${encodeURIComponent(p)}`);
    if (!r.ok) throw new ApiError(r.status, await r.text());
    if (r.headers.get("X-Incus-type") === "directory") return ((await r.json()) as { metadata: string[] }).metadata;
    return { content: await r.text() };
  },
  putFile: async (n, p, c) => {
    const r = await fetch(`/1.0/instances/${n}/files?path=${encodeURIComponent(p)}`, { method: "POST", body: c, headers: { "X-Incus-type": "file", "X-Incus-write": "overwrite" } });
    if (!r.ok) throw new ApiError(r.status, await r.text());
  },
  execUrls: async (n, command) => {
    const op = await req<Op>("POST", `/instances/${n}/exec`, { command, "wait-for-websocket": true, interactive: true, environment: { TERM: "xterm-256color" }, width: 120, height: 36 });
    const fds = (op.metadata as { fds: Record<string, string> }).fds;
    const ws = (secret: string) => `${location.protocol === "https:" ? "wss" : "ws"}://${location.host}/1.0/operations/${op.id}/websocket?secret=${secret}`;
    return { control: ws(fds.control), data: ws(fds["0"]), op };
  },
  images: () => req<Image[]>("GET", "/images?recursion=1"),
  pullImage: (remote, alias) => req<Op>("POST", "/images", { source: { type: "image", mode: "pull", server: remote, protocol: "simplestreams", alias }, aliases: [{ name: alias }] }),
  deleteImage: (f) => req<Op>("DELETE", `/images/${f}`),
  profiles: () => req<Profile[]>("GET", "/profiles?recursion=1"),
  saveProfile: (p, isNew) => (isNew ? req<void>("POST", "/profiles", p) : req<void>("PUT", `/profiles/${p.name}`, p)),
  deleteProfile: (n) => req<void>("DELETE", `/profiles/${n}`),
  networks: () => req<Network[]>("GET", "/networks?recursion=1"),
  networkState: (n) => req<NetworkState>("GET", `/networks/${n}/state`),
  pools: () => req<Pool[]>("GET", "/storage-pools?recursion=1"),
  poolResources: (n) => req<PoolResources>("GET", `/storage-pools/${n}/resources`),
  volumes: (p) => req<Volume[]>("GET", `/storage-pools/${p}/volumes?recursion=1`),
  operations: async () => {
    const m = await req<Record<string, Op[]>>("GET", "/operations?recursion=1");
    return Object.values(m ?? {}).flat();
  },
  cancelOperation: (id) => req<void>("DELETE", `/operations/${id}`),
  waitOperation: (id) => req<Op>("GET", `/operations/${id}/wait?timeout=120`),
  updateServer: (config) => req<void>("PATCH", "", { config }),
  metrics: () => req<string>("GET", "/metrics", undefined, true),
  events: (onEvent) => {
    const ws = new WebSocket(`${location.protocol === "https:" ? "wss" : "ws"}://${location.host}/1.0/events?type=operation,lifecycle,logging`);
    ws.onmessage = (m) => {
      try {
        onEvent(JSON.parse(m.data));
      } catch {
        /* keep listening */
      }
    };
    return () => ws.close();
  },
};

// Prometheus text exposition -> { name: [{labels, value}] }, enough for the
// rolling history and the per-instance readouts.
export function parseMetrics(text: string): Record<string, { labels: Record<string, string>; value: number }[]> {
  const out: Record<string, { labels: Record<string, string>; value: number }[]> = {};
  for (const line of text.split("\n")) {
    if (!line || line[0] === "#") continue;
    const m = /^([a-zA-Z_:][a-zA-Z0-9_:]*)(\{([^}]*)\})?\s+(\S+)/.exec(line);
    if (!m) continue;
    const labels: Record<string, string> = {};
    if (m[3]) for (const kv of m[3].match(/(\w+)="((?:[^"\\]|\\.)*)"/g) ?? []) {
      const [, k, v] = /(\w+)="(.*)"/.exec(kv)!;
      labels[k] = v;
    }
    (out[m[1]] ??= []).push({ labels, value: Number(m[4]) });
  }
  return out;
}
