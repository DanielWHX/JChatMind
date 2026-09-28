import { useEffect, useRef, useState } from "react";
import type { FormEvent } from "react";
import { API_ORIGIN } from "../api/origin";
import "./guest-demo.css";
import XMarkdown from "@ant-design/x-markdown";
import { journeys } from "./demo-journeys";

type DemoMessage = { id: string; role: "user" | "assistant" | "tool"; content: string; tools: string[] };
type SessionView = { status: "idle" | "running" | "failed"; messages: DemoMessage[]; remainingTurns: number; error: string | null };
const GUIDE_STORAGE = "jchatmind-guide-v1";
type Guide = { journey: number; step: number; enabled: boolean; awaiting: string; complete: boolean };
const INITIAL_GUIDE: Guide = { journey: 0, step: 0, enabled: true, awaiting: "", complete: false };
function savedGuide(): Guide { try { const v = JSON.parse(sessionStorage.getItem(GUIDE_STORAGE) ?? "null"); return v && journeys[v.journey]?.steps[v.step] && typeof v.enabled === "boolean" && typeof v.awaiting === "string" && typeof v.complete === "boolean" ? v : INITIAL_GUIDE; } catch { return INITIAL_GUIDE; } }
const STORAGE = "jchatmind-guest-session-v1";
const EMPTY: SessionView = { status: "idle", messages: [], remainingTurns: 8, error: null };
const prompts = [
  { label: "Find my plan", question: "We are an 8-person team and need CSV exports and Slack alerts. Which plan fits, and what is our monthly cost?" },
  { label: "Check my trial", question: "If we start a free trial today, when does it expire? Use the date tool and handbook." },
  { label: "Ask about SSO", question: "Does OrbitDesk support SAML SSO? Check the handbook before answering." },
];
const toolLabels: Record<string, string> = { calculateMonthlyCost: "Calculate monthly cost", KnowledgeTool: "Search handbook", getDate: "Check today's date", terminate: "Finish reply" };

function savedToken() { try { return sessionStorage.getItem(STORAGE) ?? ""; } catch { return ""; } }
function remember(token: string) { try { if (token) sessionStorage.setItem(STORAGE, token); else sessionStorage.removeItem(STORAGE); } catch { /* Iframes may have storage disabled. In-memory chat still works. */ } }
class DemoError extends Error { status: number; constructor(message: string, status: number) { super(message); this.status = status; } }

async function request<T>(path: string, token: string, body?: object): Promise<T> {
  const response = await fetch(`${API_ORIGIN}/api/demo/${path}`, {
    method: body ? "POST" : "GET",
    headers: { ...(token ? { Authorization: `Bearer ${token}` } : {}), ...(body ? { "Content-Type": "application/json" } : {}) },
    body: body ? JSON.stringify(body) : undefined,
    signal: AbortSignal.timeout(15_000),
    cache: "no-store",
  });
  const value = await response.json().catch(() => null);
  if (!response.ok) throw new DemoError(value?.error ?? "The demo is unavailable. Please try again later.", response.status);
  if (!value || typeof value !== "object") throw new Error("Invalid demo response");
  return value as T;
}

export default function GuestDemo() {
  useEffect(() => { if (window.parent !== window) window.parent.postMessage({ type: "jchatmind:ready" }, "*"); }, []);
  const [guide, setGuide] = useState(savedGuide);
  useEffect(() => { try { sessionStorage.setItem(GUIDE_STORAGE, JSON.stringify(guide)); } catch { /* Optional storage. */ } }, [guide]);
  const journey = journeys[guide.journey];
  const step = journey.steps[guide.step];
  const [token, setToken] = useState(savedToken);
  const [view, setView] = useState<SessionView>(EMPTY);
  const [draft, setDraft] = useState("");
  const [pending, setPending] = useState(false);
  const [checking, setChecking] = useState(Boolean(token));
  const [watch, setWatch] = useState(Boolean(token));
  const [error, setError] = useState("");
  const [uncertain, setUncertain] = useState(false);
  const [refresh, setRefresh] = useState(0);
  const sending = useRef(false);
  const scrollArea = useRef<HTMLDivElement>(null);
  const follow = useRef(true);

  // GET-only polling: reconnecting never submits the visitor's message a second time.
  useEffect(() => {
    if (!token || !watch) return;
    let cancelled = false;
    let timer: ReturnType<typeof setTimeout> | undefined;
    async function check() {
      if (sending.current) { timer = setTimeout(check, 500); return; }
      try {
        const result = await request<SessionView>("session", token);
        if (cancelled) return;
        setView(result);
        setGuide(previous => {
          if (!previous.awaiting || result.status !== "idle" || result.error) return previous;
          const questionIndex = result.messages.reduce((found, m, index) => m.role === "user" && m.content.trim() === previous.awaiting ? index : found, -1);
          const answered = questionIndex >= 0 && result.messages.slice(questionIndex + 1).some(m => m.role === "assistant" && m.content.trim());
          return answered ? { ...previous, awaiting: "", complete: true } : previous;
        });
        setChecking(false);
        setUncertain(false);
        if (result.error) setError(result.error);
        const lastQuestion = result.messages.filter(message => message.role === "user").at(-1)?.content;
        if (lastQuestion) setDraft(previous => previous.trim() === lastQuestion.trim() ? "" : previous);
        if (result.status === "running") timer = setTimeout(check, 1500);
        else setWatch(false);
      } catch (failure) {
        if (cancelled) return;
        setChecking(false);
        setWatch(false);
        if (failure instanceof DemoError && [401, 410].includes(failure.status)) {
          remember(""); setToken(""); setUncertain(false);
          setView(previous => ({ ...previous, status: "idle" }));
          setError("Your demo session has expired. Start a new chat to continue.");
        } else {
          setUncertain(true);
          setError("Connection interrupted. Check the reply before sending again.");
        }
      }
    }
    void check();
    return () => { cancelled = true; clearTimeout(timer); };
  }, [token, refresh, watch]);

  useEffect(() => {
    if (follow.current && scrollArea.current) scrollArea.current.scrollTop = scrollArea.current.scrollHeight;
  }, [view.messages, pending]);

  async function send(event: FormEvent) {
    event.preventDefault();
    const message = draft.trim();
    if (!message || sending.current || checking || uncertain || view.status !== "idle" || view.remainingTurns === 0) return;
    if (guide.enabled && !guide.complete) setGuide(previous => ({ ...previous, awaiting: message }));
    sending.current = true; setPending(true); setError(""); follow.current = true;
    let activeToken = token;
    let submitted = false;
    try {
      if (!activeToken) {
        const session = await request<{ sessionToken: string; maxTurns: number }>("sessions", "", {});
        activeToken = session.sessionToken; remember(activeToken); setToken(activeToken);
      }
      submitted = true;
      await request("messages", activeToken, { message });
      setDraft(""); setView(previous => ({ ...previous, status: "running" }));
      setChecking(true); setWatch(true); setRefresh(value => value + 1);
    } catch (failure) {
      if (failure instanceof DemoError) {
        setError(failure.message);
        if ([401, 410].includes(failure.status)) { remember(""); setToken(""); }
        if (failure.status === 409) { setChecking(true); setWatch(true); setRefresh(value => value + 1); }
      } else {
        setError(submitted ? "Connection interrupted. Check whether your message arrived before sending again." : "Could not connect. Please try again.");
        setUncertain(submitted);
      }
    } finally { sending.current = false; setPending(false); }
  }

  function reset(journeyIndex = guide.journey) {
    setGuide({ ...INITIAL_GUIDE, journey: journeyIndex });
    remember(""); setToken(""); setView(EMPTY); setDraft(""); setError(""); setChecking(false); setWatch(false); setUncertain(false);
  }
  const busy = pending || checking || view.status === "running";
  const expired = !token && view.messages.length > 0;

  return <main className="guest-demo" aria-label="OrbitDesk live demo">
    <header className="guest-header"><div><span className="guest-logo" aria-hidden="true">J</span><div><h1>OrbitDesk support</h1><p>Powered by JChatMind</p></div></div><button type="button" onClick={() => reset()} disabled={pending || checking || (view.status === "running" && !uncertain)}>New chat</button></header>
    <nav className="guest-journeys" aria-label="Choose an experience">{journeys.map((item, index) => <button key={item.id} type="button" aria-pressed={index === guide.journey} disabled={busy || uncertain} onClick={() => reset(index)}><span>0{index + 1}</span><strong>{item.title}</strong><small>{item.description}</small></button>)}</nav>
    {guide.enabled ? <section className="guest-guide" aria-label="Guided experience">
      <div className="guest-guide-heading"><span>YOUR MISSION · {guide.step + 1} / {journey.steps.length}</span><button type="button" onClick={() => setGuide(previous => ({ ...previous, enabled: false }))}>Skip tutorial</button></div>
      <h2>{step.title}</h2><p>{step.goal}</p>
      <div className="guest-guide-actions"><button type="button" disabled={busy || uncertain || expired || view.status === "failed" || view.remainingTurns === 0} onClick={() => { setDraft(step.question); document.getElementById("guest-question")?.focus(); }}>Use suggested question ↓</button><span>Edit it below, then send.</span></div>
      {guide.complete && <div className="guest-guide-evidence"><p><strong>What to look for</strong> {step.evidence}</p>{guide.step + 1 < journey.steps.length ? <button type="button" disabled={busy || uncertain} onClick={() => setGuide(previous => ({ ...previous, step: previous.step + 1, complete: false, awaiting: "" }))}>Next step →</button> : <p className="guest-guide-done">Tutorial complete. Keep exploring, or choose another experience.</p>}</div>}
    </section> : <div className="guest-free-mode">Free exploration · Ask your own questions.<button type="button" onClick={() => setGuide(previous => ({ ...previous, enabled: true }))}>Show tutorial</button></div>}
    <div className="guest-messages" role="log" aria-label="Conversation" ref={scrollArea} onScroll={() => { const node = scrollArea.current; if (node) follow.current = node.scrollHeight - node.scrollTop - node.clientHeight < 70; }}>
      {!view.messages.length && <div className="guest-welcome"><span aria-hidden="true">✦</span><h2>Ask. Follow up. Check the source.</h2><p>Try a question about plans, pricing or free trials.</p></div>}
      {view.messages.map(message => (message.content || message.tools.length > 0) && <article className={`guest-message guest-${message.role}`} key={message.id} aria-label={message.role === "user" ? "You" : "JChatMind"}>
        {message.tools.length > 0 && <div className="guest-tools" aria-label="Agent tool calls">{message.tools.map(tool => <span key={tool}>{toolLabels[tool] ?? tool}</span>)}</div>}
        {message.role === "tool" ? <details className="guest-evidence"><summary>{toolLabels[message.tools[0]] ?? "Tool result"} · View evidence</summary><p>{message.content}</p></details> : message.content && (message.role === "assistant" ? <XMarkdown content={message.content} dompurifyConfig={{ ALLOWED_TAGS: ["p", "strong", "em", "ul", "ol", "li", "code", "pre", "blockquote", "br", "hr", "h2", "h3", "h4", "table", "thead", "tbody", "tr", "th", "td"], ALLOWED_ATTR: [] }} /> : <p>{message.content}</p>)}
      </article>)}
      {busy && <p className="guest-status" role="status">{pending ? "Sending…" : "Working on your reply…"}</p>}
    </div>
    <footer className="guest-composer">
      <nav className="guest-prompts" aria-label="Suggested questions">{prompts.map(prompt => <button type="button" key={prompt.label} disabled={busy || uncertain || expired} onClick={() => setDraft(prompt.question)}>{prompt.label}</button>)}</nav>
      {error && <div className="guest-error" role="alert">{error}{uncertain && <button type="button" onClick={() => { setError(""); setChecking(true); setWatch(true); setRefresh(value => value + 1); }}>Check reply</button>}</div>}
      {view.remainingTurns === 0 && <p className="guest-status">This chat has reached its eight-question limit.</p>}
      <form onSubmit={send}><label className="guest-sr-only" htmlFor="guest-question">Ask OrbitDesk</label><textarea id="guest-question" rows={2} maxLength={1500} placeholder="Ask about OrbitDesk…" value={draft} disabled={busy || uncertain || expired || view.status === "failed" || view.remainingTurns === 0} onChange={event => setDraft(event.target.value)} onKeyDown={event => { if (event.key === "Enter" && !event.shiftKey && !event.nativeEvent.isComposing) { event.preventDefault(); event.currentTarget.form?.requestSubmit(); } }} /><button type="submit" disabled={!draft.trim() || busy || uncertain || expired || view.status === "failed" || view.remainingTurns === 0} aria-label="Send message">↑</button></form>
      <p className="guest-note">Fictional SaaS · Real AI · {view.remainingTurns} questions left</p>
    </footer>
  </main>;
}
