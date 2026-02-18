import { test, expect } from '@playwright/test';
import { signUp, uniqueEmail } from './helpers/auth.js';

test.describe('Board Management', () => {
  test('create a board', async ({ page }) => {
    await signUp(page, uniqueEmail('create'));
    await page.click('text=New Board');
    await page.fill('[name="board[name]"]', 'My First Board');
    await page.click('[type="submit"]');
    await expect(page).toHaveURL('/boards');
    await expect(page.locator('text=My First Board')).toBeVisible();
  });

  test('create board with empty name shows validation error', async ({ page }) => {
    await signUp(page, uniqueEmail('blank'));
    await page.click('text=New Board');
    await page.click('[type="submit"]');
    // Turbo keeps URL at boards/new on validation failure; check for error message
    await expect(page.locator('h1')).toContainText('New Board');
    await expect(page.locator("text=can't be blank")).toBeVisible();
  });

  test('edit a board name', async ({ page }) => {
    await signUp(page, uniqueEmail('edit'));
    // Create a board first
    await page.click('text=New Board');
    await page.fill('[name="board[name]"]', 'Original Name');
    await page.click('[type="submit"]');
    // Edit it
    await page.click('text=Edit');
    await page.fill('[name="board[name]"]', 'Updated Name');
    await page.click('[type="submit"]');
    await expect(page.locator('text=Updated Name')).toBeVisible();
    await expect(page.locator('text=Original Name')).not.toBeVisible();
  });

  test('delete a board', async ({ page }) => {
    await signUp(page, uniqueEmail('delete'));
    await page.click('text=New Board');
    await page.fill('[name="board[name]"]', 'To Be Deleted');
    await page.click('[type="submit"]');
    await expect(page.locator('text=To Be Deleted')).toBeVisible();
    page.on('dialog', d => d.accept());
    await page.click('button:has-text("Delete")');
    await expect(page.locator('text=To Be Deleted')).not.toBeVisible();
  });
});
