// Demo mode: generic seeded data, used when no daemon answers. Names are the
// example site's guests plus a scratch instance; nothing here is real.
import type { Backend, Instance, Op, State, Image, Profile, Network, Pool, Snapshot } from "./api";

function rng(seed: number) {
  let a = seed >>> 0;
  return () => {
    a = (a + 0x6d2b79f5) >>> 0;
    let t = a;
    t = Math.imul(t ^ (t >>> 15), t | 1);
    t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
export function walk(seed: number, base: number, amp: number, min: number, max: number, n = 1440, spike = 0): number[] {
  const r = rng(seed);
  const out: number[] = [];
  let v = base;
  for (let i = 0; i < n; i++) {
    v += (base - v) * 0.05 + (r() - 0.5) * amp;
    if (spike && r() < spike) v += amp * 4;
    v = Math.max(min, Math.min(max, v));
    out.push(v);
  }
  return out;
}
export function bursty(seed: number, lo: number, hi: number, n = 1440): number[] {
  const r = rng(seed);
  const out: number[] = [];
  let on = false;
  let left = 0;
  for (let i = 0; i < n; i++) {
    if (left-- <= 0) {
      on = !on;
      left = 20 + Math.floor(r() * 120);
    }
    out.push(on ? hi - r() * 10 : lo + r() * 5);
  }
  return out;
}

const names = ["web", "db", "worker", "compute", "builder", "vm1", "legacy", "scratch"];
const now = () => new Date().toISOString();
const inst = (name: string, i: number): Instance => ({
  name,
  type: name === "vm1" ? "virtual-machine" : "container",
  status: name === "legacy" ? "Stopped" : name === "builder" ? "Frozen" : "Running",
  profiles: ["default", ...(name === "compute" ? ["gpu"] : []), ...(i % 2 ? ["killswitch"] : [])],
  config: { "image.os": name === "legacy" || name === "vm1" ? "alpine" : "nixos", "limits.memory": name === "db" ? "2GiB" : "", "security.nesting": name === "builder" ? "true" : "false", "volatile.base_image": `demo${i}` },
  devices: { root: { type: "disk", path: "/", pool: "default" }, uplink: { type: "nic", nictype: "bridged", parent: "nixie-br", host_name: `veth-${name}` } },
  created_at: new Date(Date.now() - 86400000 * (i + 1)).toISOString(),
  state: { status: "Running", pid: 1000 + i, cpu: { usage: 1e9 * (i + 1) }, memory: { usage: 2 ** 28 * (i + 1), usage_peak: 2 ** 29, total: 2 ** 33 }, disk: { root: { usage: 2 ** 30 * (i + 1) } }, network: { uplink: { addresses: [{ family: "inet", address: `192.0.2.${10 + i}`, scope: "global" }], counters: { bytes_received: 1e9, bytes_sent: 5e8 } } } },
});
let instances = names.map(inst);
export const demoSeries = {
  cpu: Object.fromEntries(names.map((n, i) => [n, walk(i + 1, 12 + i * 6, 6, 0, 100, 1440, 0.01)])),
  hostCpu: walk(99, 20, 5, 0, 100),
  mem: walk(7, 55, 2, 0, 100),
  gpuUtil: [bursty(11, 2, 92), bursty(12, 3, 70)],
  gpuPower: [walk(21, 120, 30, 30, 300), walk(22, 90, 25, 30, 300)],
  gpuTemp: [walk(31, 62, 3, 30, 95), walk(32, 55, 3, 30, 95)],
};
let ops: Op[] = [
  { id: "op-1", status: "Running", class: "task", description: "Creating snapshot", created_at: now(), may_cancel: true, resources: { instances: ["/1.0/instances/db"] } },
  { id: "op-2", status: "Running", class: "task", description: "Pulling image debian/12", created_at: now(), may_cancel: true, metadata: { download_progress: "42%" } },
  { id: "op-3", status: "Success", class: "task", description: "Starting instance", created_at: now(), may_cancel: false, resources: { instances: ["/1.0/instances/web"] } },
];
const finished = (description: string, instance?: string): Op => ({ id: `op-${Math.random().toString(36).slice(2, 8)}`, status: "Success", class: "task", description, created_at: now(), may_cancel: false, resources: instance ? { instances: [`/1.0/instances/${instance}`] } : undefined });
const snaps: Record<string, Snapshot[]> = Object.fromEntries(names.map((n) => [n, [1, 2, 3].map((i) => ({ name: `daily-${i}`, created_at: new Date(Date.now() - 86400000 * i).toISOString(), stateful: false, size: 2 ** 27 * i }))]));

export const demo: Backend = {
  demo: true,
  server: async () => ({ auth: "trusted", environment: { server_name: "demo", kernel_version: "6.12", server_version: "6.0", storage: "zfs", driver: "lxc | qemu" }, config: { "core.https_address": ":8443" } }),
  instances: async () => instances,
  instance: async (n) => instances.find((i) => i.name === n)!,
  instanceState: async (n) => instances.find((i) => i.name === n)!.state as State,
  instanceAction: async (n, action) => {
    const i = instances.find((x) => x.name === n)!;
    i.status = action === "stop" ? "Stopped" : action === "freeze" ? "Frozen" : "Running";
    return finished(`${action} instance`, n);
  },
  createInstance: async (body) => {
    const b = body as { name: string; type?: string };
    instances = [...instances, { ...inst(b.name, instances.length), type: b.type ?? "container", status: "Stopped" }];
    return finished("Creating instance", b.name);
  },
  deleteInstance: async (n) => {
    instances = instances.filter((i) => i.name !== n);
    return finished("Deleting instance", n);
  },
  updateInstance: async (n, body) => {
    const i = instances.find((x) => x.name === n)!;
    Object.assign(i, body);
  },
  snapshots: async (n) => snaps[n] ?? [],
  createSnapshot: async (n, s) => {
    (snaps[n] ??= []).push({ name: s, created_at: now(), stateful: false });
    return finished("Creating snapshot", n);
  },
  deleteSnapshot: async (n, s) => {
    snaps[n] = (snaps[n] ?? []).filter((x) => x.name !== s);
    return finished("Deleting snapshot", n);
  },
  restoreSnapshot: async (n) => finished("Restoring snapshot", n),
  logs: async () => ["lxc.log", "console.log"],
  log: async (n, f) => `# ${f} for ${n}\n${new Date().toISOString()} lxc ${n} 20250910 INFO start - demo log line\n`,
  files: async (_n, p) => (p.endsWith("/") || p === "/" ? ["etc", "var", "nix", "root"] : { content: `# ${p}\ndemo file content\n` }),
  putFile: async () => undefined,
  execUrls: async () => {
    throw new Error("demo");
  },
  images: async (): Promise<Image[]> => [
    { fingerprint: "de4efaf408b8bda90121491390e57b7bebb27373bd6917fc9bddb47d6de616d5", aliases: [{ name: "alpine/3.22/cloud" }], properties: { os: "Alpine", release: "3.22", description: "Alpine 3.22 amd64 (cloud)" }, size: 3e6, uploaded_at: now(), type: "container", architecture: "x86_64" },
    { fingerprint: "9897f13a1099c18fd4646d6aa6c9ca2dac85fbd6c4923fe79cb143978b0913d4", aliases: [{ name: "nixie/web/abc" }], properties: { os: "nixos", description: "NixOS guest web" }, size: 4e8, uploaded_at: now(), type: "container", architecture: "x86_64" },
  ],
  pullImage: async (_r, a) => finished(`Pulling image ${a}`),
  deleteImage: async () => finished("Deleting image"),
  profiles: async (): Promise<Profile[]> => [
    { name: "default", description: "Default profile", config: {}, devices: { root: { type: "disk", path: "/", pool: "default" } }, used_by: names.map((n) => `/1.0/instances/${n}`) },
    { name: "gpu", description: "All host GPUs", config: {}, devices: { gpu: { type: "gpu" } }, used_by: ["/1.0/instances/compute"] },
    { name: "killswitch", description: "Exit-node only egress", config: {}, devices: {}, used_by: [] },
  ],
  saveProfile: async () => undefined,
  deleteProfile: async () => undefined,
  networks: async (): Promise<Network[]> => [
    { name: "nixie-br", type: "bridge", managed: false, config: {}, used_by: names.map((n) => `/1.0/instances/${n}`), status: "Created" },
    { name: "uplink0", type: "physical", managed: false, config: {}, used_by: [] },
    { name: "tailscale0", type: "unknown", managed: false, config: {}, used_by: [] },
  ],
  networkState: async (n) => ({ addresses: [{ family: "inet", address: n === "nixie-br" ? "10.90.0.1" : "192.0.2.2", netmask: "24" }], counters: { bytes_received: 4e9, bytes_sent: 2e9 }, hwaddr: "00:00:00:00:00:00", state: "up", type: "broadcast", mtu: 1500 }),
  pools: async (): Promise<Pool[]> => [
    { name: "default", driver: "zfs", config: { source: "rpool/incus" }, used_by: names.map((n) => `/1.0/instances/${n}`), status: "Created" },
    { name: "media", driver: "dir", config: { source: "/data/media" }, used_by: [] },
  ],
  poolResources: async (n) => ({ space: { used: n === "default" ? 1.3e12 : 6e11, total: 2e12 } }),
  volumes: async () => names.slice(0, 5).map((n) => ({ name: n, type: "container", content_type: "filesystem", used_by: [`/1.0/instances/${n}`], config: {} })),
  operations: async () => ops,
  cancelOperation: async (id) => {
    ops = ops.map((o) => (o.id === id ? { ...o, status: "Cancelled" } : o));
  },
  waitOperation: async (id) => ops.find((o) => o.id === id) ?? finished("op"),
  updateServer: async () => undefined,
  metrics: async () => "",
  events: (onEvent) => {
    const t = setInterval(() => onEvent({ type: "lifecycle", metadata: { action: "instance-updated", source: `/1.0/instances/${names[Math.floor(Math.random() * 5)]}` }, timestamp: now() }), 15000);
    return () => clearInterval(t);
  },
};
