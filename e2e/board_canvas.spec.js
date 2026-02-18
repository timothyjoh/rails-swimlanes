import { test, expect } from '@playwright/test';
import { signUp, uniqueEmail, createBoard } from './helpers/auth.js';

// Drags source element to overlap with target element.
// Uses smooth mouse movement so SortableJS registers the drag correctly.
async function dragTo(page, source, target, { offsetX = 0, offsetY = 0 } = {}) {
  const srcBox = await source.boundingBox();
  const tgtBox = await target.boundingBox();

  await page.mouse.move(srcBox.x + srcBox.width / 2, srcBox.y + srcBox.height / 2);
  await page.mouse.down();
  await page.waitForTimeout(50);
  await page.mouse.move(
    tgtBox.x + tgtBox.width / 2 + offsetX,
    tgtBox.y + tgtBox.height / 2 + offsetY,
    { steps: 15 }
  );
  await page.waitForTimeout(100);
  await page.mouse.up();
}

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

  test('drag card to reorder within a lane', async ({ page }) => {
    await page.fill('[placeholder="Lane name..."]', 'Todo');
    await page.click('[type="submit"][value="Add Lane"]');
    await page.waitForSelector('[data-sortable-swimlane-id-value]');

    await page.fill('[placeholder="Add a card..."]', 'First Card');
    await page.click('[type="submit"][value="Add"]');
    await page.waitForTimeout(300);

    await page.fill('[placeholder="Add a card..."]', 'Second Card');
    await page.click('[type="submit"][value="Add"]');
    await page.waitForTimeout(300);

    const cards = page.locator('[data-card-id]');
    await expect(cards).toHaveCount(2);

    // Wait for the reorder PATCH to complete before asserting
    const reorderDone = page.waitForResponse(
      r => r.url().includes('/reorder') && r.request().method() === 'PATCH'
    );
    await dragTo(page, cards.nth(1), cards.nth(0), { offsetY: -5 });
    await reorderDone;

    // DOM should reflect new order immediately (SortableJS moved it client-side)
    const domTexts = await page.locator('[data-card-id]').allTextContents();
    expect(domTexts.findIndex(t => t.includes('Second Card'))).toBeLessThan(
      domTexts.findIndex(t => t.includes('First Card'))
    );

    // Reload to confirm server persisted the new positions
    await page.reload();
    const savedTexts = await page.locator('[data-card-id]').allTextContents();
    expect(savedTexts.findIndex(t => t.includes('Second Card'))).toBeLessThan(
      savedTexts.findIndex(t => t.includes('First Card'))
    );
  });

  test('drag card to a different swimlane', async ({ page }) => {
    // Create two lanes
    await page.fill('[placeholder="Lane name..."]', 'Lane A');
    await page.click('[type="submit"][value="Add Lane"]');
    await page.waitForTimeout(300);

    await page.fill('[placeholder="Lane name..."]', 'Lane B');
    await page.click('[type="submit"][value="Add Lane"]');
    await page.waitForTimeout(300);

    // Add a card to Lane A (first card form)
    await page.locator('[placeholder="Add a card..."]').first().fill('Move Me');
    await page.locator('[type="submit"][value="Add"]').first().click();
    await page.waitForTimeout(300);

    await expect(page.locator('text=Move Me')).toBeVisible();

    // Drag the card into Lane B's card container
    const card = page.locator('[data-card-id]').first();
    const laneBCards = page.locator('[data-sortable-swimlane-id-value]').nth(1);

    const reorderDone = page.waitForResponse(
      r => r.url().includes('/reorder') && r.request().method() === 'PATCH'
    );
    await dragTo(page, card, laneBCards);
    await reorderDone;

    // Card should now be inside Lane B's container
    await expect(laneBCards.locator('[data-card-id]')).toHaveCount(1);
    await expect(laneBCards.locator('[data-card-id]').first()).toContainText('Move Me');

    // Lane A should be empty
    const laneACards = page.locator('[data-sortable-swimlane-id-value]').first();
    await expect(laneACards.locator('[data-card-id]')).toHaveCount(0);

    // Reload to confirm server persisted the move
    await page.reload();
    const savedLaneBCards = page.locator('[data-sortable-swimlane-id-value]').nth(1);
    await expect(savedLaneBCards.locator('[data-card-id]')).toHaveCount(1);
    await expect(savedLaneBCards.locator('[data-card-id]').first()).toContainText('Move Me');
  });

  test('drag swimlane to reorder', async ({ page }) => {
    // Create two lanes
    await page.fill('[placeholder="Lane name..."]', 'First Lane');
    await page.click('[type="submit"][value="Add Lane"]');
    await page.waitForTimeout(300);

    await page.fill('[placeholder="Lane name..."]', 'Second Lane');
    await page.click('[type="submit"][value="Add Lane"]');
    await page.waitForTimeout(300);

    const lanes = page.locator('[data-swimlane-id]');
    await expect(lanes).toHaveCount(2);

    // Drag second lane to the left of the first lane
    const reorderDone = page.waitForResponse(
      r => r.url().includes('/swimlanes/reorder') && r.request().method() === 'PATCH'
    );
    await dragTo(page, lanes.nth(1), lanes.nth(0), { offsetX: -20 });
    await reorderDone;

    // DOM should reflect new order
    const domNames = await page.locator('[data-swimlane-id] .font-semibold').allTextContents();
    expect(domNames.findIndex(t => t.includes('Second Lane'))).toBeLessThan(
      domNames.findIndex(t => t.includes('First Lane'))
    );

    // Reload to confirm server persisted the reorder
    await page.reload();
    const savedNames = await page.locator('[data-swimlane-id] .font-semibold').allTextContents();
    expect(savedNames.findIndex(t => t.includes('Second Lane'))).toBeLessThan(
      savedNames.findIndex(t => t.includes('First Lane'))
    );
  });
});
