import { test, expect } from '@playwright/test';
import { signUp, uniqueEmail, createBoard } from './helpers/auth.js';

// Helper: trigger a card reorder by directly calling the PATCH endpoint.
// This simulates what SortableJS does on drag-end, testing the server-side
// persistence logic without relying on DOM drag events in headless mode.
// Note: CSRF protection is disabled in the test environment, so no token needed.
async function reorderCard(page, cardId, swimlaneId, position) {
  const result = await page.evaluate(
    async ({ cardId, swimlaneId, position }) => {
      const container = document.querySelector(`[data-sortable-swimlane-id-value="${swimlaneId}"]`);
      if (!container) return { error: `no container for swimlane ${swimlaneId}` };

      const baseUrl = container.dataset.sortableUrlValue;
      const reorderUrl = baseUrl.replace('/cards', '/cards/reorder');

      // CSRF protection is disabled in test env; send empty token
      const csrfToken = document.querySelector('meta[name="csrf-token"]')?.content || '';

      const response = await fetch(reorderUrl, {
        method: 'PATCH',
        headers: {
          'Content-Type': 'application/json',
          'X-CSRF-Token': csrfToken,
        },
        body: JSON.stringify({ card_id: cardId, position }),
      });
      return { status: response.status, ok: response.ok };
    },
    { cardId, swimlaneId, position }
  );
  return result;
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

  test('drag card within a lane persists after reload', async ({ page }) => {
    // Setup: create lane
    await page.fill('[placeholder="Lane name..."]', 'Sprint');
    await page.click('[type="submit"][value="Add Lane"]');
    await expect(page.locator('text=Sprint')).toBeVisible();

    // Add Card A (position 0)
    await page.fill('[placeholder="Add a card..."]', 'Card A');
    await page.click('[type="submit"][value="Add"]');
    await expect(page.locator('[data-card-id]').filter({ hasText: 'Card A' })).toBeVisible();

    // Add Card B (position 1)
    await page.fill('[placeholder="Add a card..."]', 'Card B');
    await page.click('[type="submit"][value="Add"]');
    await expect(page.locator('[data-card-id]').filter({ hasText: 'Card B' })).toBeVisible();

    // Verify initial order: Card A first (position 0), Card B second (position 1)
    const cards = page.locator('[data-card-id]');
    await expect(cards.nth(0)).toContainText('Card A');
    await expect(cards.nth(1)).toContainText('Card B');

    // Get Card A's id and swimlane id
    const cardA = page.locator('[data-card-id]').filter({ hasText: 'Card A' });
    const cardAId = await cardA.getAttribute('data-card-id');
    const swimlaneId = await cardA.getAttribute('data-swimlane-id');

    // Move Card A to position 1 (after Card B) via the reorder endpoint
    const result = await reorderCard(page, cardAId, swimlaneId, 1);
    expect(result.ok).toBe(true);

    await page.reload();

    const cardsAfterReload = page.locator('[data-card-id]');
    await expect(cardsAfterReload.nth(0)).toContainText('Card B');
    await expect(cardsAfterReload.nth(1)).toContainText('Card A');
  });

  test('drag card between lanes persists after reload', async ({ page }) => {
    // Create first lane: To Do
    await page.fill('[placeholder="Lane name..."]', 'To Do');
    await page.click('[type="submit"][value="Add Lane"]');
    await expect(page.locator('text=To Do')).toBeVisible();

    // Create second lane: Done
    await page.fill('[placeholder="Lane name..."]', 'Done');
    await page.click('[type="submit"][value="Add Lane"]');
    await expect(page.locator('text=Done')).toBeVisible();

    // Add card to first (To Do) lane
    const addCardInputs = page.locator('[placeholder="Add a card..."]');
    await addCardInputs.first().fill('My Task');
    const addSubmits = page.locator('[type="submit"][value="Add"]');
    await addSubmits.first().click();
    await expect(page.locator('[data-card-id]').filter({ hasText: 'My Task' })).toBeVisible();

    // Get card ID and Done lane's swimlane container ID
    const cardEl = page.locator('[data-card-id]').filter({ hasText: 'My Task' });
    const cardId = await cardEl.getAttribute('data-card-id');
    const doneColumn = page.locator('[data-controller="sortable"]').last();
    const doneSwimlaneId = await doneColumn.getAttribute('data-sortable-swimlane-id-value');

    // Move card to Done lane at position 0 via the reorder endpoint
    const result = await reorderCard(page, cardId, doneSwimlaneId, 0);
    expect(result.ok).toBe(true);

    await page.reload();

    // After reload, card should appear in the Done (last) sortable column
    const doneColumnAfterReload = page.locator('[data-controller="sortable"]').last();
    await expect(doneColumnAfterReload.locator('text=My Task')).toBeVisible();
  });
});
