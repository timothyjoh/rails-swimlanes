import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: './e2e',
  use: {
    baseURL: 'http://localhost:3000',
    headless: true,
  },
  webServer: {
    command: 'PATH="/usr/local/lib/ruby/gems/3.4.0/bin:/usr/local/opt/ruby/bin:$PATH" bin/rails server -e test -p 3000',
    url: 'http://localhost:3000',
    reuseExistingServer: false,
    timeout: 30000,
  },
});
