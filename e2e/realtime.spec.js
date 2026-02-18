import { test, expect } from "@playwright/test";
import { signInAs, signUp, uniqueEmail, createBoard, PASSWORD } from "./helpers/auth.js";

test.describe("Real-time collaboration", () => {
  test("owner creates card; collaborator sees it without reload", async ({ browser }) => {
    const ownerCtx = await browser.newContext();
    const collabCtx = await browser.newContext();
    try {
      const ownerPage = await ownerCtx.newPage();
      const collabPage = await collabCtx.newPage();

      const ownerEmail = uniqueEmail("rt_owner");
      const collabEmail = uniqueEmail("rt_collab");

      await signUp(ownerPage, ownerEmail);
      await signUp(collabPage, collabEmail);

      // Owner creates board, adds collaborator
      await createBoard(ownerPage, "RT Board");
      await ownerPage.fill('[placeholder="user@example.com"]', collabEmail);
      await ownerPage.click('#membership_form [type="submit"]');
      await ownerPage.waitForSelector(`text=${collabEmail}`);

      // Owner adds a swimlane
      await ownerPage.fill('[placeholder="Lane name..."]', "Todo");
      await ownerPage.click('[type="submit"][value="Add Lane"]');
      await expect(ownerPage.locator("text=Todo")).toBeVisible();

      // Get board URL for collaborator
      const boardUrl = ownerPage.url();

      // Collaborator navigates to the board
      await signInAs(collabPage, collabEmail, PASSWORD);
      await collabPage.goto(boardUrl);
      await collabPage.waitForURL(/\/boards\/\d+/);
      await expect(collabPage.locator("text=Todo")).toBeVisible();

      // Owner creates a card
      await ownerPage.fill('[placeholder="Add a card..."]', "Live Card");
      await ownerPage.click('[type="submit"][value="Add"]');

      // Collaborator should see the card appear via ActionCable broadcast
      await expect(collabPage.locator("text=Live Card")).toBeVisible({ timeout: 10000 });
    } finally {
      await ownerCtx.close();
      await collabCtx.close();
    }
  });

  test("owner deletes card; collaborator sees it disappear", async ({ browser }) => {
    const ownerCtx = await browser.newContext();
    const collabCtx = await browser.newContext();
    try {
      const ownerPage = await ownerCtx.newPage();
      const collabPage = await collabCtx.newPage();

      const ownerEmail = uniqueEmail("rt_del_owner");
      const collabEmail = uniqueEmail("rt_del_collab");

      await signUp(ownerPage, ownerEmail);
      await signUp(collabPage, collabEmail);

      await createBoard(ownerPage, "RT Delete Board");
      await ownerPage.fill('[placeholder="user@example.com"]', collabEmail);
      await ownerPage.click('#membership_form [type="submit"]');
      await ownerPage.waitForSelector(`text=${collabEmail}`);

      await ownerPage.fill('[placeholder="Lane name..."]', "Work");
      await ownerPage.click('[type="submit"][value="Add Lane"]');
      await expect(ownerPage.locator("text=Work")).toBeVisible();

      await ownerPage.fill('[placeholder="Add a card..."]', "Delete Me");
      await ownerPage.click('[type="submit"][value="Add"]');
      await expect(ownerPage.locator("text=Delete Me")).toBeVisible();

      const boardUrl = ownerPage.url();

      await signInAs(collabPage, collabEmail, PASSWORD);
      await collabPage.goto(boardUrl);
      await collabPage.waitForURL(/\/boards\/\d+/);
      await expect(collabPage.locator("text=Delete Me")).toBeVisible({ timeout: 10000 });

      // Owner deletes the card — hover to reveal the ✕ button, accept turbo_confirm
      ownerPage.on("dialog", (d) => d.accept());
      const card = ownerPage.locator('[data-card-id]').filter({ hasText: "Delete Me" });
      await card.hover();
      await card.locator('button').click();

      // Collaborator sees card disappear via ActionCable broadcast
      await expect(collabPage.locator("text=Delete Me")).not.toBeVisible({ timeout: 10000 });
    } finally {
      await ownerCtx.close();
      await collabCtx.close();
    }
  });

  test("owner creates swimlane; collaborator sees it appear", async ({ browser }) => {
    const ownerCtx = await browser.newContext();
    const collabCtx = await browser.newContext();
    try {
      const ownerPage = await ownerCtx.newPage();
      const collabPage = await collabCtx.newPage();

      const ownerEmail = uniqueEmail("rt_sl_owner");
      const collabEmail = uniqueEmail("rt_sl_collab");

      await signUp(ownerPage, ownerEmail);
      await signUp(collabPage, collabEmail);

      await createBoard(ownerPage, "RT Swimlane Board");
      await ownerPage.fill('[placeholder="user@example.com"]', collabEmail);
      await ownerPage.click('#membership_form [type="submit"]');
      await ownerPage.waitForSelector(`text=${collabEmail}`);

      const boardUrl = ownerPage.url();

      await signInAs(collabPage, collabEmail, PASSWORD);
      await collabPage.goto(boardUrl);
      await collabPage.waitForURL(/\/boards\/\d+/);

      // Owner creates a swimlane
      await ownerPage.fill('[placeholder="Lane name..."]', "New Live Lane");
      await ownerPage.click('[type="submit"][value="Add Lane"]');

      // Collaborator sees it appear via ActionCable broadcast
      await expect(collabPage.locator("text=New Live Lane")).toBeVisible({ timeout: 10000 });
    } finally {
      await ownerCtx.close();
      await collabCtx.close();
    }
  });

  test("owner moves card between swimlanes; collaborator sees move", async ({ browser }) => {
    const ownerCtx = await browser.newContext();
    const collabCtx = await browser.newContext();
    try {
      const ownerPage = await ownerCtx.newPage();
      const collabPage = await collabCtx.newPage();

      const ownerEmail = uniqueEmail("rt_mv_owner");
      const collabEmail = uniqueEmail("rt_mv_collab");

      await signUp(ownerPage, ownerEmail);
      await signUp(collabPage, collabEmail);

      await createBoard(ownerPage, "RT Move Board");
      await ownerPage.fill('[placeholder="user@example.com"]', collabEmail);
      await ownerPage.click('#membership_form [type="submit"]');
      await ownerPage.waitForSelector(`text=${collabEmail}`);

      // Owner creates two swimlanes
      await ownerPage.fill('[placeholder="Lane name..."]', "Lane A");
      await ownerPage.click('[type="submit"][value="Add Lane"]');
      await expect(ownerPage.locator("text=Lane A")).toBeVisible();

      await ownerPage.fill('[placeholder="Lane name..."]', "Lane B");
      await ownerPage.click('[type="submit"][value="Add Lane"]');
      await expect(ownerPage.locator("text=Lane B")).toBeVisible();

      // Owner creates a card in Lane A (first add-card form)
      await ownerPage.locator('[placeholder="Add a card..."]').first().fill("Move Me");
      await ownerPage.locator('[type="submit"][value="Add"]').first().click();
      await expect(ownerPage.locator("text=Move Me")).toBeVisible();

      const boardUrl = ownerPage.url();
      const boardId = boardUrl.match(/\/boards\/(\d+)/)[1];

      // Extract swimlane and card IDs from DOM
      const laneAId = await ownerPage.locator('[id^="swimlane_"]').nth(0).getAttribute("id").then(id => id.replace("swimlane_", ""));
      const laneBId = await ownerPage.locator('[id^="swimlane_"]').nth(1).getAttribute("id").then(id => id.replace("swimlane_", ""));
      const cardId = await ownerPage.locator('[id^="card_"]').first().getAttribute("id").then(id => id.replace("card_", ""));

      // Collaborator navigates to the board
      await signInAs(collabPage, collabEmail, PASSWORD);
      await collabPage.goto(boardUrl);
      await collabPage.waitForURL(/\/boards\/\d+/);
      await expect(collabPage.locator("text=Move Me")).toBeVisible({ timeout: 10000 });

      // Owner moves the card via direct PATCH (avoids flaky drag-and-drop; CSRF disabled in test env)
      await ownerPage.request.patch(
        `/boards/${boardId}/swimlanes/${laneBId}/cards/reorder`,
        {
          headers: { "Content-Type": "application/x-www-form-urlencoded" },
          data: `card_id=${cardId}&position=0`,
        }
      );

      // Collaborator sees Move Me leave Lane A and appear in Lane B
      await expect(collabPage.locator(`#cards_swimlane_${laneAId}`).locator("text=Move Me")).not.toBeVisible({ timeout: 10000 });
      await expect(collabPage.locator(`#cards_swimlane_${laneBId}`).locator("text=Move Me")).toBeVisible({ timeout: 10000 });
    } finally {
      await ownerCtx.close();
      await collabCtx.close();
    }
  });

  test("owner deletes swimlane; collaborator sees it disappear", async ({ browser }) => {
    const ownerCtx = await browser.newContext();
    const collabCtx = await browser.newContext();
    try {
      const ownerPage = await ownerCtx.newPage();
      const collabPage = await collabCtx.newPage();

      const ownerEmail = uniqueEmail("rt_sld_owner");
      const collabEmail = uniqueEmail("rt_sld_collab");

      await signUp(ownerPage, ownerEmail);
      await signUp(collabPage, collabEmail);

      await createBoard(ownerPage, "RT Delete Lane Board");
      await ownerPage.fill('[placeholder="user@example.com"]', collabEmail);
      await ownerPage.click('#membership_form [type="submit"]');
      await ownerPage.waitForSelector(`text=${collabEmail}`);

      await ownerPage.fill('[placeholder="Lane name..."]', "Doomed Lane");
      await ownerPage.click('[type="submit"][value="Add Lane"]');
      await expect(ownerPage.locator("text=Doomed Lane")).toBeVisible();

      const boardUrl = ownerPage.url();

      await signInAs(collabPage, collabEmail, PASSWORD);
      await collabPage.goto(boardUrl);
      await collabPage.waitForURL(/\/boards\/\d+/);
      await expect(collabPage.locator("text=Doomed Lane")).toBeVisible({ timeout: 10000 });

      // Owner deletes the swimlane — accept turbo_confirm dialog
      ownerPage.on("dialog", (d) => d.accept());
      await ownerPage.locator('[data-swimlane-id] button:has-text("Delete")').click();

      // Collaborator sees it disappear via ActionCable broadcast
      await expect(collabPage.locator("text=Doomed Lane")).not.toBeVisible({ timeout: 10000 });
    } finally {
      await ownerCtx.close();
      await collabCtx.close();
    }
  });
});
