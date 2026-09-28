import { test, expect } from "@playwright/test";

for (const width of [1440, 390]) {
  test(`guest can send, see real API tool names, restore, and reset at ${width}px`, async ({ page }) => {
    await page.setViewportSize({ width, height: 850 });
    let sent = 0;
    let poll = 0;
    let question = "";
    await page.route("**/api/demo/**", async route => {
      const request = route.request();
      if (request.url().endsWith("/sessions")) return route.fulfill({ json: { sessionToken: "visitor-a", maxTurns: 8, expiresAt: "2099-01-01" } });
      expect(request.headers().authorization).toBe("Bearer visitor-a");
      if (request.url().endsWith("/messages")) {
        expect(Object.keys(request.postDataJSON())).toEqual(["message"]);
        question = request.postDataJSON().message; sent++;
        return route.fulfill({ status: 202, json: { status: "running" } });
      }
      poll++;
      return route.fulfill({ json: { status: sent && poll < 2 ? "running" : "idle", remainingTurns: 8 - sent, error: null, messages: sent ? [
        { id: "u1", role: "user", content: question, tools: [] },
        { id: "a1", role: "assistant", content: "Team includes CSV exports and Slack alerts. Eight people cost $144 per month.", tools: ["KnowledgeTool"] },
      ] : [] } });
    });
    await page.goto("/demo");
    await page.getByRole("button", { name: "Find my plan" }).click();
    await page.getByRole("button", { name: "Send message" }).click();
    await expect(page.getByText("Team includes CSV exports and Slack alerts. Eight people cost $144 per month.")).toBeVisible();
    await expect(page.getByText("Search handbook", { exact: true })).toBeVisible();
    await expect(page.getByRole("textbox", { name: "Ask OrbitDesk" })).toBeEnabled();
    await page.reload();
    await expect(page.getByText("Team includes CSV exports and Slack alerts. Eight people cost $144 per month.")).toBeVisible();
    expect(sent).toBe(1);
    expect(await page.evaluate(() => document.documentElement.scrollWidth <= innerWidth)).toBe(true);
    await page.getByRole("button", { name: "New chat" }).click();
    await expect(page.getByText("Ask. Follow up. Check the source.")).toBeVisible();
  });
}

test("uncertain delivery checks the result without repeating the paid request", async ({ page }) => {
  let sent = 0;
  await page.route("**/api/demo/**", async route => {
    const request = route.request();
    if (request.url().endsWith("/sessions")) return route.fulfill({ json: { sessionToken: "visitor-b", maxTurns: 8 } });
    if (request.url().endsWith("/messages")) { sent++; return route.abort("connectionreset"); }
    return route.fulfill({ json: { status: "idle", remainingTurns: 7, error: null, messages: [{ id: "u", role: "user", content: "Check my trial", tools: [] }, { id: "a", role: "assistant", content: "Your trial lasts 14 calendar days.", tools: ["getDate", "KnowledgeTool"] }] } });
  });
  await page.goto("/demo");
  await page.getByRole("textbox", { name: "Ask OrbitDesk" }).fill("Check my trial");
  await page.getByRole("button", { name: "Send message" }).click();
  await expect(page.getByRole("alert")).toContainText("Connection interrupted");
  await page.getByRole("button", { name: "Check reply" }).click();
  await expect(page.getByText("Your trial lasts 14 calendar days.")).toBeVisible();
  await expect(page.getByRole("textbox", { name: "Ask OrbitDesk" })).toHaveValue("");
  expect(sent).toBe(1);
});

test("unavailable demo retains the question and reports failure", async ({ page }) => {
  await page.route("**/api/demo/sessions", route => route.fulfill({ status: 503, json: { error: "The live demo is being prepared. Please try again later." } }));
  await page.goto("/demo");
  await page.getByRole("textbox", { name: "Ask OrbitDesk" }).fill("Hello");
  await page.getByRole("button", { name: "Send message" }).click();
  await expect(page.getByRole("alert")).toContainText("being prepared");
  await expect(page.getByRole("textbox", { name: "Ask OrbitDesk" })).toHaveValue("Hello");
  await expect(page.getByRole("button", { name: "Send message" })).toBeEnabled();
});

test("tutorial requires a live response, exposes evidence, and isolates journeys", async ({ page }) => {
  let session = 0;
  let question = "";
  let answered = false;
  let failed = false;
  await page.route("**/api/demo/**", async route => {
    if (route.request().url().endsWith("/sessions")) { session++; question = ""; answered = false; return route.fulfill({ json: { sessionToken: `journey-${session}`, maxTurns: 8 } }); }
    if (route.request().url().endsWith("/messages")) { question = route.request().postDataJSON().message; return route.fulfill({ status: 202, json: { status: "running" } }); }
    return route.fulfill({ json: { status: failed ? "failed" : answered ? "idle" : "running", remainingTurns: 7, error: failed ? "Could not complete reply" : null, messages: [
      { id: "u", role: "user", content: question, tools: [] },
      ...(answered ? [{ id: "t", role: "tool", content: "Team costs USD 18 per user per month.", tools: ["KnowledgeTool"] }, { id: "a", role: "assistant", content: "Eight users cost $144 per month.", tools: [] }] : []),
    ] } });
  });
  await page.goto("/demo");
  await page.getByRole("button", { name: "Use suggested question" }).click();
  await expect(page.getByRole("textbox", { name: "Ask OrbitDesk" })).toHaveValue(/8-person/);
  await page.getByRole("textbox", { name: "Ask OrbitDesk" }).fill("We have 8 people. Check the handbook for CSV and Slack pricing.");
  await page.getByRole("button", { name: "Send message" }).click();
  await expect(page.getByRole("button", { name: "Next step" })).toHaveCount(0);
  answered = true;
  await expect(page.getByRole("button", { name: "Next step" })).toBeVisible();
  await expect(page.getByText("Team costs USD 18 per user per month.")).not.toBeVisible();
  await page.getByText("Search handbook · View evidence").click();
  await expect(page.getByText("Team costs USD 18 per user per month.")).toBeVisible();
  await page.getByRole("button", { name: "Next step" }).click();
  await page.getByRole("button", { name: "Use suggested question" }).click();
  await expect(page.getByRole("textbox", { name: "Ask OrbitDesk" })).toHaveValue(/12 people/);
  await page.reload();
  await expect(page.getByRole("heading", { name: "Follow up naturally" })).toBeVisible();
  await page.getByRole("button", { name: /Start a trial/ }).click();
  await expect(page.getByText("Eight users cost $144 per month.")).toHaveCount(0);
  await page.getByRole("button", { name: "Use suggested question" }).click();
  failed = true;
  await page.getByRole("button", { name: "Send message" }).click();
  await expect(page.getByRole("alert")).toContainText("Could not complete reply");
  expect(session).toBe(2);
  await expect(page.getByRole("button", { name: "Next step" })).toHaveCount(0);
  await page.getByRole("button", { name: "Skip tutorial" }).click();
  await expect(page.getByText("Free exploration", { exact: false })).toBeVisible();
});
