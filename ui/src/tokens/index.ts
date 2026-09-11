// The 21 design tokens per finish, extracted once from the design file
// (docs/design-tokens.md). Applied as CSS custom properties on :root.
import tokens from "./tokens.json";

export type Finish = "graphite" | "umber" | "paper";
export const finishes = Object.keys(tokens) as Finish[];
export type Tokens = (typeof tokens)["graphite"];

export function tokensFor(finish: Finish, overrides: Partial<Tokens> = {}): Tokens {
  return { ...tokens[finish], ...overrides };
}

export function applyFinish(finish: Finish, overrides: Partial<Tokens> = {}): Tokens {
  const t = tokensFor(finish, overrides);
  const root = document.documentElement;
  for (const [k, v] of Object.entries(t)) {
    if (k === "label" || k === "dark") continue;
    root.style.setProperty(`--${k}`, String(v));
  }
  root.dataset.finish = finish;
  root.style.colorScheme = t.dark ? "dark" : "light";
  return t;
}

export function heatColor(v: number, dark: boolean): string {
  const t = Math.max(0, Math.min(1, v / 100));
  return dark
    ? `oklch(${14 + 76 * t}% ${0.17 * Math.min(1, 1.6 * t)} ${25 + 60 * t})`
    : `oklch(${86 - 56 * t}% ${0.02 + 0.16 * t} ${80 - 50 * t})`;
}
