export const PASSWORD = 'password123';

export function uniqueEmail(prefix = 'test') {
  return `${prefix}_${Date.now()}_${Math.random().toString(36).slice(2)}@example.com`;
}

export async function signUp(page, email) {
  await page.goto('/registration/new');
  await page.fill('[name="user[email_address]"]', email);
  await page.fill('[name="user[password]"]', PASSWORD);
  await page.fill('[name="user[password_confirmation]"]', PASSWORD);
  await page.click('[type="submit"]');
  await page.waitForURL('/boards');
}

export async function signIn(page, email, password = PASSWORD) {
  await page.goto('/session/new');
  await page.fill('[name="email_address"]', email);
  await page.fill('[name="password"]', password);
  await page.click('[type="submit"]');
  await page.waitForURL(/\/(boards)?$/);
}

export const signInAs = signIn;

export async function createBoard(page, name) {
  await page.click('text=New Board');
  await page.fill('[name="board[name]"]', name);
  await page.click('[type="submit"]');
  await page.waitForURL('/boards');
  await page.click(`a:has-text("${name}")`);
  await page.waitForURL(/\/boards\/\d+/);
}
