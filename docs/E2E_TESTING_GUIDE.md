# E2E Testing Implementation Guide

## Overview

This document provides a comprehensive guide for implementing end-to-end (E2E) tests for the Scientific Raster Data Platform frontend using Playwright.

## Setup

### 1. Install Playwright

```bash
cd frontend
npm install -D @playwright/test @axe-core/playwright
npx playwright install
```

### 2. Configuration

Create `frontend/playwright.config.ts`:

```typescript
import { defineConfig, devices } from '@playwright/test';

export default defineConfig({
  testDir: './tests/e2e',
  fullyParallel: true,
  forbidOnly: !!process.env.CI,
  retries: process.env.CI ? 2 : 0,
  workers: process.env.CI ? 1 : undefined,
  reporter: 'html',
  use: {
    baseURL: 'http://localhost:5173',
    trace: 'on-first-retry',
    screenshot: 'only-on-failure',
  },

  projects: [
    {
      name: 'chromium',
      use: { ...devices['Desktop Chrome'] },
    },
    {
      name: 'firefox',
      use: { ...devices['Desktop Firefox'] },
    },
    {
      name: 'webkit',
      use: { ...devices['Desktop Safari'] },
    },
    {
      name: 'Mobile Chrome',
      use: { ...devices['Pixel 5'] },
    },
    {
      name: 'Mobile Safari',
      use: { ...devices['iPhone 12'] },
    },
  ],

  webServer: {
    command: 'npm run dev',
    url: 'http://localhost:5173',
    reuseExistingServer: !process.env.CI,
  },
});
```

### 3. Update package.json

```json
{
  "scripts": {
    "test:e2e": "playwright test",
    "test:e2e:ui": "playwright test --ui",
    "test:e2e:debug": "playwright test --debug"
  }
}
```

## Test Implementation

### Happy Path Test: `frontend/tests/e2e/HappyPath.spec.ts`

```typescript
import { test, expect } from '@playwright/test';
import { injectAxe, checkA11y } from 'axe-playwright';

test.describe('Happy Path: Search → Map → Timeseries', () => {
  test.beforeEach(async ({ page }) => {
    await page.goto('/');
    
    // Wait for app to load
    await page.waitForLoadState('networkidle');
  });

  test('complete user journey from search to timeseries visualization', async ({ page }) => {
    // ===== STEP 1: Search for datasets =====
    test.step('Search for datasets', async () => {
      // Open search panel on mobile
      const isMobile = page.viewportSize()!.width < 1024;
      if (isMobile) {
        await page.click('button[aria-label="Toggle search panel"]');
      }

      // Fill search form
      await page.fill('input[name="keywords"]', 'temperature');
      
      // Set date range
      await page.fill('input[name="startDate"]', '2024-01-01');
      await page.fill('input[name="endDate"]', '2024-12-31');

      // Select variable
      await page.check('input[value="temperature"]');

      // Submit search
      await page.click('button[type="submit"]');

      // Wait for results
      await page.waitForSelector('.dataset-card', { timeout: 10000 });

      // Verify results appear
      const resultCards = await page.locator('.dataset-card').count();
      expect(resultCards).toBeGreaterThan(0);
    });

    // ===== STEP 2: Select dataset and view on map =====
    test.step('Select dataset and visualize on map', async () => {
      // Click first dataset card
      await page.click('.dataset-card:first-child button');

      // Wait for map to load layer
      await page.waitForSelector('.maplibregl-canvas', { timeout: 5000 });

      // Verify layer controls appear
      await expect(page.locator('text=Layers & Legend')).toBeVisible();

      // Check layer is listed
      const layerItems = await page.locator('.layer-item').count();
      expect(layerItems).toBeGreaterThan(0);

      // Verify opacity control exists
      await expect(page.locator('input[type="range"][aria-label*="Opacity"]')).toBeVisible();
    });

    // ===== STEP 3: Click map to query timeseries =====
    test.step('Click map and view timeseries', async () => {
      // Click on map center
      const mapCanvas = page.locator('.maplibregl-canvas').first();
      await mapCanvas.click({ position: { x: 400, y: 300 } });

      // Wait for timeseries to load
      await page.waitForSelector('.plotly', { timeout: 10000 });

      // Verify chart is visible
      await expect(page.locator('.plotly .main-svg')).toBeVisible();

      // Verify export buttons
      await expect(page.locator('button:has-text("CSV")')).toBeVisible();
      await expect(page.locator('button:has-text("JSON")')).toBeVisible();

      // Verify location metadata
      await expect(page.locator('text=/Location:.*\\d+\\.\\d+/')).toBeVisible();
    });

    // ===== STEP 4: Export data =====
    test.step('Export timeseries data as CSV', async () => {
      // Setup download listener
      const downloadPromise = page.waitForEvent('download');

      // Click CSV export
      await page.click('button:has-text("CSV")');

      // Wait for download
      const download = await downloadPromise;

      // Verify filename
      expect(download.suggestedFilename()).toMatch(/timeseries.*\\.csv$/);

      // Verify file is not empty
      const path = await download.path();
      expect(path).toBeTruthy();
    });

    // ===== STEP 5: Test layer controls =====
    test.step('Adjust layer opacity', async () => {
      // Get opacity slider
      const opacitySlider = page.locator('input[type="range"][aria-label*="Opacity"]').first();

      // Change opacity
      await opacitySlider.fill('50');

      // Verify change reflected (visual regression test could be added)
      const value = await opacitySlider.inputValue();
      expect(parseInt(value)).toBeLessThanOrEqual(50);
    });

    // ===== STEP 6: Toggle layer visibility =====
    test.step('Toggle layer visibility', async () => {
      // Get visibility checkbox
      const visibilityToggle = page.locator('input[type="checkbox"][aria-label*="Toggle"]').first();

      // Toggle off
      await visibilityToggle.uncheck();
      await expect(visibilityToggle).not.toBeChecked();

      // Toggle back on
      await visibilityToggle.check();
      await expect(visibilityToggle).toBeChecked();
    });
  });

  test('handles error states gracefully', async ({ page }) => {
    // Test network error handling
    await page.route('**/api/v1/stac/search', route => {
      route.abort('failed');
    });

    // Try to search
    await page.fill('input[name="keywords"]', 'test');
    await page.click('button[type="submit"]');

    // Verify error message appears
    await expect(page.locator('[role="alert"]')).toContainText(/network error/i);

    // Verify retry button exists
    await expect(page.locator('button:has-text("Retry")')).toBeVisible();
  });

  test('responsive design on mobile', async ({ page }) => {
    await page.setViewportSize({ width: 375, height: 667 });

    // Verify mobile navigation
    await expect(page.locator('[aria-label="Mobile navigation"]')).toBeVisible();

    // Test hamburger menu
    await page.click('button[aria-label="Toggle search panel"]');
    await expect(page.locator('.search-panel')).toBeVisible();

    // Test drawer controls on map
    await page.click('button[aria-label="Open layer controls"]');
    await expect(page.locator('.layer-controls-drawer')).toBeVisible();
  });
});

test.describe('Accessibility', () => {
  test('meets WCAG 2.1 AA standards', async ({ page }) => {
    await page.goto('/');
    await injectAxe(page);

    // Check entire page
    await checkA11y(page, null, {
      detailedReport: true,
      detailedReportOptions: {
        html: true,
      },
    });
  });

  test('keyboard navigation works', async ({ page }) => {
    await page.goto('/');

    // Tab through interactive elements
    await page.keyboard.press('Tab');
    
    // Verify skip link appears
    await expect(page.locator('.skip-link:focus')).toBeVisible();

    // Skip to main content
    await page.keyboard.press('Enter');

    // Verify focus moved
    const mainContent = page.locator('#main-content');
    await expect(mainContent).toBeFocused();
  });
});

test.describe('Performance', () => {
  test('loads within acceptable time', async ({ page }) => {
    const startTime = Date.now();
    
    await page.goto('/');
    await page.waitForLoadState('networkidle');
    
    const loadTime = Date.now() - startTime;
    
    // Should load within 3 seconds
    expect(loadTime).toBeLessThan(3000);
  });

  test('handles large timeseries datasets', async ({ page }) => {
    await page.goto('/');

    // Mock large dataset response
    await page.route('**/api/v1/timeseries', route => {
      const largeData = {
        series: [{
          times: Array.from({ length: 10000 }, (_, i) => 
            new Date(2024, 0, 1 + i).toISOString()
          ),
          values: Array.from({ length: 10000 }, () => Math.random() * 100),
          variable: 'temperature',
          units: 'K',
        }],
      };
      route.fulfill({ json: largeData });
    });

    // Trigger timeseries query
    await page.click('.maplibregl-canvas', { position: { x: 400, y: 300 } });

    // Verify warning appears for large dataset
    await expect(page.locator('text=/Large dataset/i')).toBeVisible();

    // Verify chart still renders (decimated)
    await expect(page.locator('.plotly .main-svg')).toBeVisible();
  });
});
```

## Additional Test Scenarios

### Multi-Dataset Comparison Test

```typescript
test('compare multiple datasets', async ({ page }) => {
  // Add first dataset
  await page.click('.dataset-card:nth-child(1) button');
  
  // Add second dataset  
  await page.click('.dataset-card:nth-child(2) button');

  // Verify both layers in control panel
  const layers = await page.locator('.layer-item').count();
  expect(layers).toBe(2);

  // Click map for timeseries
  await page.click('.maplibregl-canvas', { position: { x: 400, y: 300 } });

  // Verify multi-series chart
  const traces = await page.locator('.plotly .trace').count();
  expect(traces).toBeGreaterThan(1);
});
```

### Catalog Browse Test

```typescript
test('browse catalog hierarchy', async ({ page }) => {
  await page.goto('/browse');

  // Click collection
  await page.click('button:has-text("Collection")');

  // Verify items load
  await expect(page.locator('.dataset-card')).toBeVisible();

  // Select item
  await page.click('.dataset-card:first-child');

  // View on map
  await page.click('button[aria-label="View on map"]');

  // Verify redirected to explorer with layer loaded
  await expect(page).toHaveURL(/\\/explorer/);
  await expect(page.locator('.layer-item')).toBeVisible();
});
```

## Running Tests

### Local Development

```bash
# Run all E2E tests
npm run test:e2e

# Run with UI mode (debugging)
npm run test:e2e:ui

# Run specific test file
npx playwright test tests/e2e/HappyPath.spec.ts

# Run in headed mode
npx playwright test --headed

# Debug mode
npm run test:e2e:debug
```

### CI/CD Integration

```yaml
# .github/workflows/e2e-tests.yml
name: E2E Tests

on:
  push:
    branches: [main, develop]
  pull_request:
    branches: [main, develop]

jobs:
  test:
    timeout-minutes: 60
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      
      - name: Setup Node
        uses: actions/setup-node@v3
        with:
          node-version: 20
          cache: 'npm'
          cache-dependency-path: frontend/package-lock.json
      
      - name: Install dependencies
        working-directory: ./frontend
        run: npm ci
      
      - name: Install Playwright Browsers
        working-directory: ./frontend
        run: npx playwright install --with-deps
      
      - name: Run Playwright tests
        working-directory: ./frontend
        run: npm run test:e2e
      
      - name: Upload test report
        uses: actions/upload-artifact@v3
        if: always()
        with:
          name: playwright-report
          path: frontend/playwright-report/
          retention-days: 30
```

## Best Practices

1. **Use data-testid for stable selectors**:
   ```tsx
   <button data-testid="search-submit">Search</button>
   ```

2. **Mock external services**:
   ```typescript
   await page.route('**/api/**', route => {
     route.fulfill({ json: mockData });
   });
   ```

3. **Test in multiple viewports**:
   ```typescript
   test.use({ viewport: { width: 375, height: 667 } });
   ```

4. **Use test.step for readable logs**:
   ```typescript
   await test.step('User searches for data', async () => {
     // test code
   });
   ```

5. **Handle asynchronous operations**:
   ```typescript
   await page.waitForLoadState('networkidle');
   await page.waitForResponse(response => 
     response.url().includes('/api/v1/stac/search')
   );
   ```

## Maintenance

- Update selectors when UI changes
- Keep test data fixtures in `frontend/tests/e2e/fixtures/`
- Review and update tests when adding new features
- Run E2E tests before each release
- Monitor test flakiness and address unstable tests

## Resources

- [Playwright Documentation](https://playwright.dev)
- [Playwright Best Practices](https://playwright.dev/docs/best-practices)
- [axe-playwright](https://github.com/abhinaba-ghosh/axe-playwright)
