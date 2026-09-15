// The config editor on the review step: Nix highlighting, completion and hover
// help for every nixie.* option from the metadata the steps use, and the lines
// an evaluation names marked as errors.
import { useEffect, useRef } from "react";
import { EditorView, basicSetup } from "codemirror";
import { hoverTooltip, tooltips } from "@codemirror/view";
import { autocompletion, type CompletionContext } from "@codemirror/autocomplete";
import { setDiagnostics, lintGutter } from "@codemirror/lint";
import { HighlightStyle, syntaxHighlighting } from "@codemirror/language";
import { tags } from "@lezer/highlight";
import { nix } from "@replit/codemirror-lang-nix";
import type { Opt } from "./api";

export type Mark = { line: number; col: number; message: string };

const look = EditorView.theme({
  "&": { backgroundColor: "var(--s2)", color: "var(--ink)", fontSize: "13px", height: "100%", borderRadius: "6px" },
  ".cm-content": { fontFamily: "'JetBrains Mono', monospace", caretColor: "var(--brand2)" },
  ".cm-gutters": { backgroundColor: "var(--s2)", color: "var(--muted)", border: "none" },
  ".cm-activeLine, .cm-activeLineGutter": { backgroundColor: "color-mix(in srgb, var(--s3) 60%, transparent)" },
  "&.cm-focused .cm-selectionBackground, .cm-selectionBackground": { backgroundColor: "color-mix(in oklch, var(--brand) 35%, transparent)" },
  ".cm-tooltip": { backgroundColor: "var(--s1)", color: "var(--ink)", border: "1px solid var(--line)", borderRadius: "6px", maxWidth: "520px" },
  ".cm-tooltip-autocomplete ul li[aria-selected]": { backgroundColor: "var(--brand)", color: "#fff" },
  ".cm-completionInfo": { padding: "8px 10px", whiteSpace: "pre-line" },
});

const colours = HighlightStyle.define([
  { tag: [tags.keyword, tags.operatorKeyword], color: "var(--brand2)" },
  { tag: [tags.string, tags.special(tags.string)], color: "var(--ok)" },
  { tag: tags.comment, color: "var(--muted)", fontStyle: "italic" },
  { tag: [tags.number, tags.bool, tags.null, tags.atom], color: "var(--hot)" },
  { tag: [tags.propertyName, tags.attributeName], color: "var(--ink)" },
  { tag: [tags.variableName, tags.function(tags.variableName)], color: "var(--ice)" },
  { tag: [tags.url, tags.link], color: "var(--net)" },
]);

function help(o: Opt): HTMLElement {
  const d = document.createElement("div");
  d.style.padding = "8px 10px";
  const title = document.createElement("div");
  title.style.fontWeight = "600";
  title.textContent = o.label ? `${o.label} · ${o.path}` : o.path;
  const type = document.createElement("div");
  type.style.color = "var(--muted)";
  type.textContent = `${o.type}${o.default !== null && o.default !== undefined ? ` · default ${JSON.stringify(o.default)}` : ""}`;
  const text = document.createElement("div");
  text.style.whiteSpace = "pre-line";
  text.style.marginTop = "6px";
  text.textContent = o.description.trim();
  d.append(title, type, text);
  return d;
}

export function Editor({ value, onChange, opts, marks }: { value: string; onChange: (v: string) => void; opts: Opt[]; marks: Mark[] }) {
  const host = useRef<HTMLDivElement>(null);
  const view = useRef<EditorView | null>(null);
  const change = useRef(onChange);
  change.current = onChange;

  useEffect(() => {
    const byPath = new Map(opts.map((o) => [o.path, o]));
    const complete = (ctx: CompletionContext) => {
      const w = ctx.matchBefore(/[\w.-]+/);
      if (!w || (w.from === w.to && !ctx.explicit)) return null;
      return {
        from: w.from,
        validFor: /^[\w.-]*$/,
        options: opts.map((o) => ({ label: o.path, detail: o.label ?? o.type, type: "property", info: () => help(o) })),
      };
    };
    const hover = hoverTooltip((v, pos) => {
      const line = v.state.doc.lineAt(pos);
      const re = /nixie(\.[\w-]+)+/g;
      for (let m; (m = re.exec(line.text)); ) {
        const from = line.from + m.index;
        const to = from + m[0].length;
        if (pos < from || pos > to) continue;
        // The longest known option the word starts with (nixie.backups.enable = …).
        let path = m[0];
        while (path.includes(".") && !byPath.has(path)) path = path.slice(0, path.lastIndexOf("."));
        const o = byPath.get(path);
        return o ? { pos: from, end: to, above: true, create: () => ({ dom: help(o) }) } : null;
      }
      return null;
    });
    view.current = new EditorView({
      doc: value,
      parent: host.current!,
      extensions: [
        basicSetup,
        // The editor sits in a clipped frame; help drawn inside it was cut off.
        tooltips({ parent: document.body }),
        nix(),
        look,
        syntaxHighlighting(colours),
        autocompletion({ override: [complete] }),
        hover,
        lintGutter(),
        EditorView.updateListener.of((u) => u.docChanged && change.current(u.state.doc.toString())),
      ],
    });
    return () => view.current?.destroy();
    // One editor per file: the parent keys this component by path.
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, []);

  useEffect(() => {
    const v = view.current;
    if (!v) return;
    const doc = v.state.doc;
    v.dispatch(
      setDiagnostics(
        v.state,
        marks
          .filter((m) => m.line >= 1 && m.line <= doc.lines)
          .map((m) => {
            const line = doc.line(m.line);
            const from = Math.min(line.from + Math.max(0, m.col - 1), line.to);
            return { from, to: Math.max(from, line.to), severity: "error" as const, message: m.message };
          }),
      ),
    );
  }, [marks]);

  return <div ref={host} style={{ height: "100%", minHeight: 360, overflow: "auto" }} />;
}
