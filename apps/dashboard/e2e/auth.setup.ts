import { test as setup } from '@playwright/test';
import { ADMIN_STATE } from '../playwright.config';
import { loginAsAdmin } from './helpers';

setup('login Admin sekali untuk semua tes', async ({ page }) => {
  await loginAsAdmin(page);
  await page.context().storageState({ path: ADMIN_STATE });
});
