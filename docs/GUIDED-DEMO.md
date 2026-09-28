# JChatMind guided experience

Updated: 2026-09-28

## Product behavior

Portfolio / Projects / JChatMind keeps its header entry position. “Explore the demo” expands the original guest application inside the project page. The interactive recorded replay remains separate below it.

Three independent, English-language journeys:

1. Choose a plan: eight-person recommendation, then twelve-person follow-up.
2. Start a trial: real current date plus the handbook's trial policy, then onboarding with a 6,000-row CSV.
3. Handle an enquiry: undocumented SAML SSO, then an unsent customer reply with pricing.

Each tutorial step explains the goal and fills an editable composer. The visitor sends the question. No recorded answer is returned by the tutorial. An actual completed assistant response unlocks the next step; failures and in-flight requests do not. Visitors can skip guidance, keep asking questions, restart, or select another journey (fresh session).

Answers render as restricted Markdown. KnowledgeTool/getDate/calculateMonthlyCost results appear as collapsed evidence. The public API only includes tool results matched to an allowed call in that visitor's session; system prompts, tool arguments, internal IDs, and unrelated results are not exposed through the evidence contract.

The current evidence is the actual retrieved text, not a structured document citation. Retrieval still uses the existing title embeddings/top-three retrieval. Broader retrieval quality improvements and arbitrary document uploads are outside this slice.

## Local preview

Keep the existing local services running. This separate preview uses backend 8081 and UI 5177; it does not stop the original 8080/5174 services.

Prerequisites: JDK 21, Node, local PostgreSQL/Ollama, `.local/config/application-local.yaml`, and `.local/business-demo.json` from the existing OrbitDesk setup.

```sh
cd jchatmind
JAVA_HOME=/Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home ./mvnw -DskipTests package
cd ..
python3 scripts/start-guided-demo.py
```

Visit `http://127.0.0.1:5177/demo`. Logs and process records are under `.local/logs/guided-*` and `.local/pids/guided-*`. Readiness must be checked after startup. The guest runtime uses the same configured model and prepared knowledge base as the original app.

For local Portfolio development, add `JCHATMIND_DEMO_URL="http://127.0.0.1:5177/demo"` to its ignored `.dev.vars` file (Cloudflare bindings), then restart the dev server. Passing only a shell environment variable did not reach this Worker runtime. Production retains the HTTPS-only requirement. No public live endpoint is configured by this change.

## Verification status

- Guest frontend production build: passed.
- Portfolio production build: passed.
- Guest edited-file lint: passed.
- Portfolio lint: no errors, three existing image warnings.
- Backend tests: 10 passed (8 guest HTTP tests and 2 exact pricing tool tests). HTTP dependencies are mocked; live verification below covers the actual runtime.
- Browser tests: all 8 passed (5 guest and 3 Portfolio), including desktop/mobile, editable input, response-gated progression, evidence, reload, independent journeys, failure and skip behavior.
- Live validation: six API turns across all three journeys passed against the configured model, database, real retrieval and tools. An additional two-turn browser conversation verified $144 → $216 and tutorial completion. Desktop/mobile visual inspection passed. Portfolio iframe and ready handshake passed on the actual local integration.
- Public deployment: not performed.

HTTP test invocation in this environment avoids unsupported Mockito self-attachment:

```sh
cd jchatmind
JAVA_HOME=/Library/Java/JavaVirtualMachines/temurin-21.jdk/Contents/Home ./mvnw \
  -DargLine=-javaagent:/Users/wanghongxiang/.m2/repository/org/mockito/mockito-core/5.17.0/mockito-core-5.17.0.jar \
  -Dtest=GuestDemoHttpTest,DemoPricingToolTest test
```

Browser: `cd ui && npm run test:demo`. Portfolio: build, then `PLAYWRIGHT_CHANNEL=chrome npx playwright test tests/browser/jchatmind.spec.ts`.

## Live acceptance checks before publication

- Eight users: Team recommendation, $144 before taxes, real retrieved evidence.
- Same session, twelve users: $216, prior needs retained.
- Trial: actual getDate output plus 14 calendar days, not the recording's fixed dates.
- CSV onboarding: 5,000-row per-file limit; Slack setup described rather than executed.
- SAML: handbook does not specify; refer to product team rather than invent support or non-support.
- Reply: draft only; no external send/account action.
- Switch journey/reset: no old messages or context leak.
- Failure: no false “complete” or automatic paid retry.
- Public HTTPS, mobile layout, iframe readiness, quotas and host capacity verified before enabling the live URL.

## Real-test findings and correction

The initial live recommendation incorrectly said 8 × 18 = 288. Added a guest-only `calculateMonthlyCost` tool using BigDecimal and instructed the guest runtime to retrieve the rate first, then use the actual arithmetic result. Tool results are visible as evidence. No fixed answer replaces the model response, and no database agent prompt is overwritten.

After correction, the pricing outputs were $144 for eight and $216 for twelve, including the customer draft. The date tool returned 2026-09-28 and the trial reply calculated 2026-10-12. CSV guidance split 6,000 rows into two files. SSO remained unconfirmed and the final reply stayed an unsent draft.

One post-fix request hit an upstream EOF/connection failure. The application exposed the failed state without auto-retrying a paid request; a new-session manual rerun then completed all six turns. This proves this test run, not uninterrupted provider availability or perfect model accuracy. One successful response used “Staff” once when referring to Starter; generated wording can still vary. Production hosting and long-term quota persistence remain pending.

Local review: Portfolio `http://127.0.0.1:3104/projects/jchatmind`; direct guest `http://127.0.0.1:5177/demo`. The original 8080/5174 services and VPN settings were preserved.
