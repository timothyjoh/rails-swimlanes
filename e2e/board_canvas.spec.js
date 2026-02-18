import { test, expect } from '@playwright/test';
import { signUp, uniqueEmail, createBoard } from './helpers/auth.js';

test.describe('Board Canvas', () => {
  let email;

  test.beforeEach(async ({ page }) => {
    email = uniqueEmail('canvas');
    await signUp(page, email);
    await createBoard(page, 'My Canvas Board');
  });

  test('create and delete a swimlane', async ({ page }) => {
    await page.fill('[placeholder="Lane name..."]', 'To Do');
    await page.click('[type="submit"][value="Add Lane"]');
    await expect(page.locator('text=To Do')).toBeVisible();

    // Handle the turbo-confirm dialog (uses window.confirm)
    page.on('dialog', d => d.accept());
    await page.locator('button:has-text("Delete")').first().click();
    await expect(page.locator('text=To Do')).not.toBeVisible();
  });

  test('create a card in a lane', async ({ page }) => {
    await page.fill('[placeholder="Lane name..."]', 'In Progress');
    await page.click('[type="submit"][value="Add Lane"]');
    await expect(page.locator('text=In Progress')).toBeVisible();

    await page.fill('[placeholder="Add a card..."]', 'Write tests');
    await page.click('[type="submit"][value="Add"]');
    await expect(page.locator('text=Write tests')).toBeVisible();
  });

  test('drag card to reorder', async ({ page }) => {
    // beforeEach already signed in and created a board — we're on the board page

    // Add a swimlane
    await page.fill('[placeholder="Lane name..."]', 'Todo');
    await page.click('[type="submit"][value="Add Lane"]');
    await page.waitForSelector('[data-controller="sortable"]');

    // Add two cards
    await page.fill('[placeholder="Add a card..."]', 'First Card');
    await page.click('[type="submit"][value="Add"]');
    await page.waitForTimeout(300);

    await page.fill('[placeholder="Add a card..."]', 'Second Card');
    await page.click('[type="submit"][value="Add"]');
    await page.waitForTimeout(300);

    // Capture initial card order
    const cards = page.locator('[data-card-id]');
    await expect(cards).toHaveCount(2);

    // Drag second card above first card using mouse API
    const firstCard = cards.nth(0);
    const secondCard = cards.nth(1);
    const firstBox = await firstCard.boundingBox();
    const secondBox = await secondCard.boundingBox();

    await page.mouse.move(secondBox.x + secondBox.width / 2, secondBox.y + secondBox.height / 2);
    await page.mouse.down();
    await page.waitForTimeout(100);
    await page.mouse.move(firstBox.x + firstBox.width / 2, firstBox.y + 5, { steps: 10 });
    await page.waitForTimeout(300);
    await page.mouse.up();
    await page.waitForTimeout(500);

    // Verify second card is now before first card in the DOM
    const cardTexts = await page.locator('[data-card-id]').allTextContents();
    const secondIdx = cardTexts.findIndex(t => t.includes('Second Card'));
    const firstIdx = cardTexts.findIndex(t => t.includes('First Card'));
    expect(secondIdx).toBeLessThan(firstIdx);
  });
});
