import { test, expect } from '@playwright/test';
import { signUp, uniqueEmail, PASSWORD } from './helpers/auth.js';

test.describe('Authentication', () => {
  test('sign up creates account and shows boards page', async ({ page }) => {
    const email = uniqueEmail('signup');
    await signUp(page, email);
    await expect(page).toHaveURL('/boards');
    await expect(page.locator('h1')).toContainText('My Boards');
  });

  test('sign up with mismatched passwords shows error', async ({ page }) => {
    await page.goto('/registration/new');
    await page.fill('[name="user[email_address]"]', uniqueEmail('mismatch'));
    await page.fill('[name="user[password]"]', 'password123');
    await page.fill('[name="user[password_confirmation]"]', 'different123');
    await page.click('[type="submit"]');
    // Error re-renders the form (Turbo keeps URL at registration/new)
    await expect(page.locator('h1')).toContainText('Sign Up');
  });

  test('log in with valid credentials redirects to boards', async ({ page }) => {
    const email = uniqueEmail('login');
    await signUp(page, email);
    // Log out first
    await page.click('button:has-text("Log Out")');
    await expect(page).toHaveURL(/session\/new/);
    // Now log back in
    await page.fill('[name="email_address"]', email);
    await page.fill('[name="password"]', PASSWORD);
    await page.click('[type="submit"]');
    // Session controller redirects to root_path which is boards#index at /
    await expect(page.locator('h1')).toContainText('My Boards');
    // root_path is '/' which maps to boards#index — both URLs are valid
    await expect(page).toHaveURL(/\/(boards)?$/);
  });

  test('log out redirects to login', async ({ page }) => {
    const email = uniqueEmail('logout');
    await signUp(page, email);
    await page.click('button:has-text("Log Out")');
    await expect(page).toHaveURL(/session\/new/);
  });

  test('unauthenticated user is redirected from boards to login', async ({ page }) => {
    await page.goto('/boards');
    await expect(page).toHaveURL(/session\/new/);
  });
});
