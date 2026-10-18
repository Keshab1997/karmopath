'use strict';

// Real Chromium smoke for the local-only admin. No production dependency is
// added: pass PLAYWRIGHT_MODULE and PLAYWRIGHT_BROWSERS_PATH from an isolated
// test-tool install. All browser requests except this loopback server are blocked.
const assert = require('node:assert/strict');
const { spawnSync } = require('node:child_process');
const fs = require('node:fs');
const http = require('node:http');
const path = require('node:path');

const ROOT = path.resolve(__dirname, '../..');
const ADMIN_DIR = path.join(ROOT, 'admin');
const FIXTURE = path.join(ROOT, 'test/fixtures/sample_feed.json');
const STORAGE_KEY = 'karmopath.admin.drafts.v1';
const playwrightModule = process.env.PLAYWRIGHT_MODULE || 'playwright';
const { chromium } = require(playwrightModule);

const CONTENT_TYPES = {
  '/admin/': 'text/html; charset=utf-8',
  '/admin/index.html': 'text/html; charset=utf-8',
  '/admin/app.js': 'text/javascript; charset=utf-8',
  '/admin/admin-core.js': 'text/javascript; charset=utf-8',
};
const SAFE_PATHS = new Map([
  ['/admin/', path.join(ADMIN_DIR, 'index.html')],
  ['/admin/index.html', path.join(ADMIN_DIR, 'index.html')],
  ['/admin/app.js', path.join(ADMIN_DIR, 'app.js')],
  ['/admin/admin-core.js', path.join(ADMIN_DIR, 'admin-core.js')],
]);

async function startLocalAdminServer() {
  const server = http.createServer((request, response) => {
    const url = new URL(request.url, 'http://127.0.0.1');
    const filename = SAFE_PATHS.get(url.pathname);
    if (!filename) {
      response.writeHead(404, { 'content-type': 'text/plain; charset=utf-8' });
      response.end('not found');
      return;
    }
    try {
      const content = fs.readFileSync(filename);
      response.writeHead(200, {
        'content-type': CONTENT_TYPES[url.pathname],
        'x-content-type-options': 'nosniff',
        'cache-control': 'no-store',
      });
      response.end(content);
    } catch (error) {
      response.writeHead(500, { 'content-type': 'text/plain; charset=utf-8' });
      response.end(String(error.message || error));
    }
  });
  await new Promise((resolve, reject) => {
    server.once('error', reject);
    server.listen(0, '127.0.0.1', resolve);
  });
  const address = server.address();
  return { server, origin: `http://127.0.0.1:${address.port}` };
}

function asDraftBundle(job) {
  const unsafe = {
    ...job,
    title_bn: 'নিরাপদ নমুনা',
    title_en: '<img id="xss-probe" src="x" onerror="window.__xssProbe=1">',
    apply_url: 'javascript:window.__xssProbe=2',
  };
  return {
    format: 'karmopath-admin-drafts-v1',
    exported_at: new Date().toISOString(),
    drafts: [{ key: 'unsafe-sample-draft', data: unsafe, reviewed: false, existing: false, idLocked: false }],
  };
}

function writeTempJson(directory, name, value) {
  const filename = path.join(directory, name);
  fs.writeFileSync(filename, JSON.stringify(value, null, 2), 'utf8');
  return filename;
}

async function importFile(page, filename) {
  await page.locator('#importFile').setInputFiles(filename);
  await page.waitForFunction(() => {
    const feedback = document.querySelector('#feedback');
    return feedback && !feedback.hidden && feedback.textContent.length > 0;
  });
}

async function downloadTo(page, selector, destination) {
  const [download] = await Promise.all([
    page.waitForEvent('download'),
    page.locator(selector).click(),
  ]);
  await download.saveAs(destination);
  return download.suggestedFilename();
}

function validateWithPython(candidatePath) {
  const result = spawnSync('python3', [path.join(ROOT, 'tools/feed/validate.py'), candidatePath], {
    encoding: 'utf8',
  });
  assert.equal(result.status, 0, result.stdout + result.stderr);
  assert.match(result.stdout, /VALID candidate feed/);
  return result.stdout.trim();
}

async function assertLayout(page, width, height, label) {
  await page.setViewportSize({ width, height });
  await page.waitForTimeout(80);
  const metrics = await page.evaluate(() => ({
    viewport: window.innerWidth,
    document: document.documentElement.scrollWidth,
    body: document.body.scrollWidth,
    buttons: ['#importButton', '#draftExportButton', '#candidateExportButton', '#newDraftButton'].map((selector) => {
      const element = document.querySelector(selector);
      const rect = element.getBoundingClientRect();
      return { selector, left: rect.left, right: rect.right, width: rect.width, height: rect.height, visible: rect.width > 0 && rect.height > 0 };
    }),
    overflowing: [...document.querySelectorAll('body *')].map((element) => {
      const rect = element.getBoundingClientRect();
      return { tag: element.tagName, id: element.id, className: String(element.className || '').slice(0, 80), left: rect.left, right: rect.right, width: rect.width, scrollWidth: element.scrollWidth };
    }).filter((item) => item.right > window.innerWidth + 1 || item.left < -1).slice(0, 12),
  }));
  assert.ok(metrics.document <= metrics.viewport, `${label}: horizontal document overflow: ${JSON.stringify(metrics)}`);
  for (const button of metrics.buttons) {
    assert.ok(button.visible, `${label}: ${button.selector} is not visible`);
    assert.ok(button.left >= -1 && button.right <= metrics.viewport + 1, `${label}: ${button.selector} clipped: ${JSON.stringify(button)}`);
  }
  return metrics;
}

async function main() {
  assert.ok(fs.existsSync(FIXTURE), `sample contract fixture missing: ${FIXTURE}`);
  const fixture = JSON.parse(fs.readFileSync(FIXTURE, 'utf8'));
  const originalJob = fixture.jobs[0];
  const originalPublishedAt = originalJob.published_at;
  const temp = fs.mkdtempSync(path.join('/home/user', 'karmopath-admin-browser-'));
  const { server, origin } = await startLocalAdminServer();
  const externalRequests = [];
  let browser;
  let context;
  try {
    browser = await chromium.launch({ headless: true });
    console.log(`REAL_BROWSER ${browser.version()}`);
    context = await browser.newContext({ acceptDownloads: true, viewport: { width: 1280, height: 900 } });
    await context.route('**/*', async (route) => {
      const requestUrl = new URL(route.request().url());
      if (requestUrl.origin === origin) return route.continue();
      externalRequests.push(requestUrl.href);
      return route.abort('blockedbyclient');
    });
    const page = await context.newPage();
    let dialogMode = 'accept';
    page.on('dialog', (dialog) => dialogMode === 'dismiss' ? dialog.dismiss() : dialog.accept());
    await page.goto(`${origin}/admin/`, { waitUntil: 'domcontentloaded' });
    await assertLayout(page, 1280, 900, 'desktop');

    // Import the repository's explicitly sample-only contract fixture.
    await importFile(page, FIXTURE);
    await page.getByText(/imported after validation/).waitFor();
    assert.equal(await page.locator('#draftList .draft-item').count(), 1);
    assert.equal(await page.locator('#id').inputValue(), originalJob.id);
    assert.equal(await page.locator('#id').isDisabled(), true);

    // Edit both languages. Existing reviewed record must block replacement export.
    await page.locator('#title_bn').fill('ব্রাউজার পরীক্ষা — নমুনা');
    await page.locator('#title_en').fill('Browser smoke test — SAMPLE ONLY');
    await page.locator('#summary_bn').fill('শুধু পরীক্ষার নমুনা; বাস্তব পদ নয়।');
    await page.locator('#summary_en').fill('Browser-only sample; not a real vacancy.');
    assert.match(await page.locator('#reviewState').innerText(), /RE-REVIEW NEEDED/);
    await page.locator('#candidateExportButton').click();
    const blockedText = await page.locator('#feedback').innerText();
    assert.match(blockedText, /blocked/i);
    assert.match(blockedText, new RegExp(originalJob.id));
    assert.equal(await page.locator('#feedback').evaluate((node) => node.className.includes('error')), true);

    // A genuine explicit confirmation restores review. Candidate is downloaded,
    // Python-validated, and retains the imported stable ID and published_at.
    await page.locator('#reviewButton').click();
    await page.getByText(/Review attestation saved/).waitFor();
    const firstCandidatePath = path.join(temp, 'candidate-reviewed.json');
    await downloadTo(page, '#candidateExportButton', firstCandidatePath);
    const firstCandidate = JSON.parse(fs.readFileSync(firstCandidatePath, 'utf8'));
    assert.equal(firstCandidate.jobs.length, 1);
    assert.equal(firstCandidate.jobs[0].id, originalJob.id);
    assert.equal(firstCandidate.jobs[0].published_at, originalPublishedAt);
    assert.equal(firstCandidate.jobs[0].title_bn, 'ব্রাউজার পরীক্ষা — নমুনা');
    assert.equal(firstCandidate.jobs[0].title_en, 'Browser smoke test — SAMPLE ONLY');
    assert.equal(firstCandidate.jobs[0].status, originalJob.status); // preview expiry never rewrites feed status
    console.log(`PYTHON_VALIDATION ${validateWithPython(firstCandidatePath)}`);

    // Existing item cannot be deleted; explicit reviewed withdrawal retains ID.
    await page.locator('#deleteDraftButton').click();
    assert.match(await page.locator('#feedback').innerText(), /cannot be deleted/i);
    assert.equal(await page.locator('#draftList .draft-item').count(), 1);
    await page.locator('#status').selectOption('withdrawn');
    assert.match(await page.locator('#reviewState').innerText(), /RE-REVIEW NEEDED/);
    await page.locator('#reviewButton').click();
    await page.getByText(/Review attestation saved/).waitFor();
    const withdrawnPath = path.join(temp, 'candidate-withdrawn.json');
    await downloadTo(page, '#candidateExportButton', withdrawnPath);
    const withdrawnFeed = JSON.parse(fs.readFileSync(withdrawnPath, 'utf8'));
    assert.equal(withdrawnFeed.jobs[0].id, originalJob.id);
    assert.equal(withdrawnFeed.jobs[0].status, 'withdrawn');
    assert.equal(withdrawnFeed.jobs[0].published_at, originalPublishedAt);
    validateWithPython(withdrawnPath);

    // Draft backup really downloads independently from a candidate feed.
    const draftBackupPath = path.join(temp, 'draft-backup.json');
    const draftFilename = await downloadTo(page, '#draftExportButton', draftBackupPath);
    assert.equal(draftFilename, 'karmopath-admin-drafts.json');
    assert.equal(JSON.parse(fs.readFileSync(draftBackupPath, 'utf8')).format, 'karmopath-admin-drafts-v1');

    // Invalid candidate import is rejected without replacing current state.
    const malformed = JSON.parse(JSON.stringify(fixture));
    delete malformed.jobs[0].title_bn;
    const malformedPath = writeTempJson(temp, 'malformed-candidate.json', malformed);
    await importFile(page, malformedPath);
    assert.match(await page.locator('#feedback').innerText(), /Import rejected/i);
    assert.equal(await page.locator('#draftList .draft-item').count(), 1);
    assert.equal(await page.locator('#id').inputValue(), originalJob.id);

    // Imported draft strings remain inert text; unsafe javascript links are omitted.
    const unsafeDraftPath = writeTempJson(temp, 'unsafe-draft.json', asDraftBundle(originalJob));
    await importFile(page, unsafeDraftPath);
    await page.locator('[data-lang="en"]').click();
    assert.equal(await page.locator('#preview #xss-probe').count(), 0);
    assert.match(await page.locator('#preview h3').innerText(), /<img id="xss-probe"/);
    assert.equal(await page.locator('#preview a[href^="javascript:"]').count(), 0);
    assert.equal(await page.evaluate(() => window.__xssProbe || null), null);

    // 320px and desktop layouts keep core controls visible without horizontal scroll.
    const mobileMetrics = await assertLayout(page, 320, 780, 'mobile-320');
    console.log(`MOBILE_LAYOUT ${JSON.stringify(mobileMetrics)}`);
    await page.locator('#newDraftButton').click();
    assert.equal(await page.locator('#id').isDisabled(), false);
    assert.equal(await page.locator('#id').isVisible(), true);
    const desktopMetrics = await assertLayout(page, 1280, 900, 'desktop-repeat');
    console.log(`DESKTOP_LAYOUT ${JSON.stringify(desktopMetrics)}`);

    // Corrupt storage recovery offers an exact raw backup and refuses writes
    // until the operator explicitly confirms clearing it.
    const corruptRaw = '{corrupt local drafts — SAMPLE ONLY';
    await page.evaluate(([key, raw]) => localStorage.setItem(key, raw), [STORAGE_KEY, corruptRaw]);
    await page.reload({ waitUntil: 'domcontentloaded' });
    await page.locator('#recoveryPanel').waitFor({ state: 'visible' });
    assert.equal(await page.locator('#newDraftButton').isDisabled(), true);
    assert.equal(await page.locator('#importButton').isDisabled(), true);
    const rawBackupPath = path.join(temp, 'corrupt-storage-raw.txt');
    const rawFilename = await downloadTo(page, '#rawBackupButton', rawBackupPath);
    assert.equal(rawFilename, 'karmopath-corrupt-local-storage-raw.txt');
    assert.equal(fs.readFileSync(rawBackupPath, 'utf8'), corruptRaw);
    assert.equal(await page.locator('#confirmRecoveryButton').isDisabled(), false);
    dialogMode = 'dismiss';
    await page.locator('#confirmRecoveryButton').click();
    assert.equal(await page.evaluate((key) => localStorage.getItem(key), STORAGE_KEY), corruptRaw);
    dialogMode = 'accept';
    await page.locator('#confirmRecoveryButton').click();
    await page.locator('#recoveryPanel').waitFor({ state: 'hidden' });
    assert.deepEqual(await page.evaluate((key) => JSON.parse(localStorage.getItem(key)), STORAGE_KEY), { version: 1, drafts: [] });

    // A denied Storage API is read-only; actions show failure and manual export remains usable.
    const deniedContext = await browser.newContext({ acceptDownloads: true, viewport: { width: 1280, height: 900 } });
    await deniedContext.addInitScript(() => {
      Object.defineProperty(window, 'localStorage', {
        configurable: true,
        get() { throw new DOMException('blocked by test policy', 'SecurityError'); },
      });
    });
    await deniedContext.route('**/*', async (route) => {
      const requestUrl = new URL(route.request().url());
      if (requestUrl.origin === origin) return route.continue();
      externalRequests.push(requestUrl.href);
      return route.abort('blockedbyclient');
    });
    const deniedPage = await deniedContext.newPage();
    await deniedPage.goto(`${origin}/admin/`, { waitUntil: 'domcontentloaded' });
    assert.equal(await deniedPage.locator('#recoveryPanel').isVisible(), true);
    assert.equal(await deniedPage.locator('#newDraftButton').isDisabled(), true);
    assert.equal(await deniedPage.locator('#importButton').isDisabled(), true);
    const deniedExportPath = path.join(temp, 'denied-storage-drafts.json');
    await downloadTo(deniedPage, '#draftExportButton', deniedExportPath);
    assert.equal(JSON.parse(fs.readFileSync(deniedExportPath, 'utf8')).drafts.length, 0);
    assert.match(await deniedPage.locator('#feedback').innerText(), /Draft backup exported/);
    await deniedContext.close();

    assert.deepEqual(externalRequests, [], `external requests were blocked: ${externalRequests.join(', ')}`);
    console.log('REAL_BROWSER_SMOKE PASS: import/edit/review/export/Python validation, recovery, XSS/URL and 320px/desktop checks.');
  } finally {
    if (context) await context.close().catch(() => {});
    if (browser) await browser.close().catch(() => {});
    await new Promise((resolve) => server.close(resolve));
    fs.rmSync(temp, { recursive: true, force: true });
  }
}

main().catch((error) => {
  console.error('REAL_BROWSER_SMOKE FAIL');
  console.error(error && error.stack || error);
  process.exitCode = 1;
});
