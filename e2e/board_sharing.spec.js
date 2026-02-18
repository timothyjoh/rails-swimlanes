import { test, expect } from "@playwright/test";
import { signUp, signIn, uniqueEmail, createBoard } from "./helpers/auth.js";

test.describe("Board Sharing", () => {
  test("owner adds collaborator; collaborator sees board and can create card", async ({ browser }) => {
    const ownerContext = await browser.newContext();
    const collabContext = await browser.newContext();
    const ownerPage = await ownerContext.newPage();
    const collabPage = await collabContext.newPage();

    const ownerEmail = uniqueEmail("owner");
    const collabEmail = uniqueEmail("collab");

    // Register both users
    await signUp(ownerPage, ownerEmail);
    await signUp(collabPage, collabEmail);

    // Owner creates a board and navigates to it
    await createBoard(ownerPage, "Shared Project");

    // Owner adds collaborator by email
    await ownerPage.fill('[placeholder="user@example.com"]', collabEmail);
    await ownerPage.click('#membership_form [type="submit"]');
    await expect(ownerPage.locator("#memberships")).toContainText(collabEmail);

    // Collaborator navigates to boards index and sees the shared board
    await collabPage.goto("/");
    await expect(collabPage.locator(`a:has-text("Shared Project")`)).toBeVisible();

    // Collaborator opens the board
    await collabPage.click('a:has-text("Shared Project")');
    await collabPage.waitForURL(/\/boards\/\d+/);

    // Collaborator adds a swimlane
    await collabPage.fill('[placeholder="Lane name..."]', "Todo");
    await collabPage.click('[type="submit"][value="Add Lane"]');
    await expect(collabPage.locator("text=Todo")).toBeVisible();

    // Collaborator adds a card
    await collabPage.fill('[placeholder="Add a card..."]', "Test Card");
    await collabPage.click('[type="submit"][value="Add"]');
    await expect(collabPage.locator("text=Test Card")).toBeVisible();

    // Collaborator does NOT see Edit Board link (owner-only)
    await expect(collabPage.locator('a:has-text("Edit Board")')).not.toBeVisible();

    await ownerContext.close();
    await collabContext.close();
  });

  test("owner removes collaborator; collaborator no longer sees board", async ({ browser }) => {
    const ownerContext = await browser.newContext();
    const collabContext = await browser.newContext();
    const ownerPage = await ownerContext.newPage();
    const collabPage = await collabContext.newPage();

    const ownerEmail = uniqueEmail("owner");
    const collabEmail = uniqueEmail("collab");

    await signUp(ownerPage, ownerEmail);
    await signUp(collabPage, collabEmail);

    // Owner creates board
    await createBoard(ownerPage, "Temp Board");

    // Owner adds collaborator
    await ownerPage.fill('[placeholder="user@example.com"]', collabEmail);
    await ownerPage.click('#membership_form [type="submit"]');
    await expect(ownerPage.locator("#memberships")).toContainText(collabEmail);

    // Collaborator verifies they can see the board
    await collabPage.goto("/");
    await expect(collabPage.locator('a:has-text("Temp Board")')).toBeVisible();

    // Owner removes collaborator (accept turbo_confirm dialog)
    ownerPage.on("dialog", (d) => d.accept());
    await ownerPage.locator('#memberships button:has-text("Remove")').click();
    await expect(ownerPage.locator("#memberships")).not.toContainText(collabEmail);

    // Collaborator reloads and no longer sees the board
    await collabPage.goto("/");
    await expect(collabPage.locator('a:has-text("Temp Board")')).not.toBeVisible();

    await ownerContext.close();
    await collabContext.close();
  });

  test("non-member cannot see another user's board", async ({ browser }) => {
    const ownerContext = await browser.newContext();
    const strangerContext = await browser.newContext();
    const ownerPage = await ownerContext.newPage();
    const strangerPage = await strangerContext.newPage();

    const ownerEmail = uniqueEmail("owner");
    const strangerEmail = uniqueEmail("stranger");

    await signUp(ownerPage, ownerEmail);
    await signUp(strangerPage, strangerEmail);

    // Owner creates a board
    await createBoard(ownerPage, "Secret Board");

    // Get the board URL from the owner's page
    const boardUrl = ownerPage.url();

    // Stranger navigates directly to the board URL
    const response = await strangerPage.goto(boardUrl);
    // Should get 404 — board content not visible
    expect(response.status()).toBe(404);
    await expect(strangerPage.locator("text=Secret Board")).not.toBeVisible();

    await ownerContext.close();
    await strangerContext.close();
  });
});
