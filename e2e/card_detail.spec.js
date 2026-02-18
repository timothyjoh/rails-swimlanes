import { test, expect } from '@playwright/test';
import { signUp, uniqueEmail, createBoard } from './helpers/auth.js';

test.describe('Card Detail', () => {
  let email;

  test.beforeEach(async ({ page }) => {
    email = uniqueEmail('detail');
    await signUp(page, email);
    await createBoard(page, 'Detail Board');

    // Create a lane and a card
    await page.fill('[placeholder="Lane name..."]', 'To Do');
    await page.click('[type="submit"][value="Add Lane"]');
    await expect(page.locator('text=To Do')).toBeVisible();

    await page.fill('[placeholder="Add a card..."]', 'Test Card');
    await page.click('[type="submit"][value="Add"]');
    await expect(page.locator('text=Test Card')).toBeVisible();
  });

  test('open card detail modal by clicking card title', async ({ page }) => {
    await page.click('text=Test Card');
    await expect(page.locator('[role="dialog"]')).toBeVisible();
    await expect(page.locator('[role="dialog"]')).toContainText('Test Card');
  });

  test('save description and verify indicator on card face', async ({ page }) => {
    // Open card detail
    await page.click('text=Test Card');
    await expect(page.locator('[role="dialog"]')).toBeVisible();

    // Fill in description and save
    await page.fill('[name="card[description]"]', 'This is a test description');
    await page.click('button:has-text("Save")');

    // Close modal
    await page.click('button[aria-label="Close"]');

    // Verify description indicator appears on the card face
    const card = page.locator('[data-card-id]').filter({ hasText: 'Test Card' });
    await expect(card.locator('[data-description-indicator]')).toBeVisible();
  });

  test('set future due date and verify badge on card face', async ({ page }) => {
    await page.click('text=Test Card');
    await expect(page.locator('[role="dialog"]')).toBeVisible();

    // Set a future due date
    const futureDate = new Date();
    futureDate.setDate(futureDate.getDate() + 7);
    const dateStr = futureDate.toISOString().split('T')[0];
    await page.fill('[name="card[due_date]"]', dateStr);
    await page.locator('button:has-text("Save")').nth(1).click();

    // Close modal
    await page.click('button[aria-label="Close"]');

    // Verify due date badge on card face (not overdue)
    const card = page.locator('[data-card-id]').filter({ hasText: 'Test Card' });
    const badge = card.locator('[data-due-date-badge]');
    await expect(badge).toBeVisible();
    await expect(badge).not.toHaveClass(/overdue/);
  });

  test('set past due date and verify overdue badge on card face', async ({ page }) => {
    await page.click('text=Test Card');
    await expect(page.locator('[role="dialog"]')).toBeVisible();

    // Set a past due date
    const pastDate = new Date();
    pastDate.setDate(pastDate.getDate() - 3);
    const dateStr = pastDate.toISOString().split('T')[0];
    await page.fill('[name="card[due_date]"]', dateStr);
    await page.locator('button:has-text("Save")').nth(1).click();

    // Close modal
    await page.click('button[aria-label="Close"]');

    // Verify overdue badge on card face
    const card = page.locator('[data-card-id]').filter({ hasText: 'Test Card' });
    const badge = card.locator('[data-due-date-badge]');
    await expect(badge).toBeVisible();
    await expect(badge).toHaveClass(/overdue/);
  });

  test('toggle label on and off', async ({ page }) => {
    await page.click('text=Test Card');
    await expect(page.locator('[role="dialog"]')).toBeVisible();

    // Toggle a label on
    const labelButton = page.locator('[data-label-toggle]').first();
    await labelButton.click();
    await page.click('button:has-text("Save Labels")');

    // Close modal and verify chip on card face
    await page.click('button[aria-label="Close"]');
    const card = page.locator('[data-card-id]').filter({ hasText: 'Test Card' });
    await expect(card.locator('[data-label-chip]')).toBeVisible();

    // Reopen and toggle label off
    await page.click('text=Test Card');
    await expect(page.locator('[role="dialog"]')).toBeVisible();
    await page.locator('[data-label-toggle]').first().click();
    await page.click('button:has-text("Save Labels")');

    await page.click('button[aria-label="Close"]');
    await expect(card.locator('[data-label-chip]')).not.toBeVisible();
  });
});
