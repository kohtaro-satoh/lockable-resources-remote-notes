/*
 * Screenshots of the lockable resources UI, for the PR.
 *
 * Runs inside a container on the harness network, so it reaches the controllers by their compose
 * aliases rather than the host ports. Everything here needs a logged-in session: the harness
 * disables anonymous read, and the pages worth showing (global configuration above all) need
 * ADMINISTER anyway.
 *
 * The tab bar on the lockable resources page is client-side - the tabs carry data-lr-tab and no
 * URL selects them - so a tab shot has to click. That is also why this is a scripted browser and
 * not `chrome --screenshot`.
 *
 * Which shots run is decided by the caller, because the "before" plugin has neither the Remote tab
 * nor the remote configuration sections, and asking for them there would only produce timeouts.
 */
const puppeteer = require('/usr/src/app/node_modules/puppeteer');

const OUT = '/out';
const USER = process.env.CAP_USER || 'admin';
const PASS = process.env.CAP_PASS || 'admin';
const LABEL = process.env.CAP_LABEL || 'after';
const SHOTS = (process.env.CAP_SHOTS || '').split(',').filter(Boolean);
const url = (key, path) => `http://jenkins-${key}:8080/jenkins${path}`;

const log = (...a) => console.log('[shots]', ...a);

async function login(page, key) {
  await page.goto(url(key, '/login'), { waitUntil: 'networkidle2' });
  await page.type("input[name='j_username']", USER);
  await page.type("input[name='j_password']", PASS);
  await Promise.all([
    page.waitForNavigation({ waitUntil: 'networkidle2' }),
    page.click("button[type='submit'], input[name='Submit'], #ok-button"),
  ]);
}

/** Screenshot an element by selector, falling back to the viewport when it is not there. */
async function shoot(page, name, selector, opts = {}) {
  const file = `${OUT}/${LABEL}-${name}.png`;
  let target = page;
  if (selector) {
    const el = await page.$(selector);
    if (!el) {
      log(`SKIP ${name}: no element for ${selector}`);
      return false;
    }
    target = el;
  }
  await target.screenshot({ path: file, ...opts });
  log(`OK   ${name} -> ${file.replace(OUT + '/', '')}`);
  return true;
}

/** Click a lockable-resources tab and wait for its panel to be the visible one. */
async function openTab(page, tab) {
  const sel = `[data-lr-tab='${tab}']`;
  if (!(await page.$(sel))) return false;
  await page.click(sel);
  await new Promise((r) => setTimeout(r, 600));
  return true;
}

const wants = (name) => SHOTS.length === 0 || SHOTS.includes(name);

(async () => {
  const browser = await puppeteer.launch({
    executablePath: '/usr/bin/chromium-browser',
    args: ['--no-sandbox', '--disable-dev-shm-usage'],
  });
  const page = await browser.newPage();
  await page.setViewport({ width: 1440, height: 900, deviceScaleFactor: 2 });

  // --- client side (controller a) ------------------------------------------
  await login(page, 'a');

  if (wants('tabbar') || wants('remote-own-locks')) {
    await page.goto(url('a', '/lockable-resources/'), { waitUntil: 'networkidle2' });
    if (wants('tabbar')) await shoot(page, 'tabbar', '.lr-tab-bar');
    if (wants('remote-own-locks') && (await openTab(page, 'remote'))) {
      await shoot(page, 'remote-own-locks', '#lr-tab-remote');
    }
  }

  if (wants('delegated-badge')) {
    await page.goto(url('a', '/lockable-resources/'), { waitUntil: 'networkidle2' });
    await shoot(page, 'delegated-badge', '.lr-delegated-badge');
  }

  if (wants('remote-catalog')) {
    await page.goto(url('a', '/lockable-resources/'), { waitUntil: 'networkidle2' });
    if (await openTab(page, 'remote')) {
      await shoot(page, 'remote-catalog', '#lr-tab-remote');
    }
  }

  if (wants('config')) {
    await page.goto(url('a', '/manage/configure'), { waitUntil: 'networkidle2' });
    // The lockable-resources block is one section of a long page; capture the whole page and let
    // the caller crop, rather than guessing at a selector that upstream may rename.
    await shoot(page, 'config', null, { fullPage: true });
  }

  // --- server side (controller b) ------------------------------------------
  if (wants('paused-banner')) {
    await login(page, 'b');
    await page.goto(url('b', '/lockable-resources/'), { waitUntil: 'networkidle2' });
    await shoot(page, 'paused-banner', '.lr-paused-banner');
  }

  await browser.close();
  log('done');
})().catch((e) => {
  console.error('[shots] FAIL', e.message);
  process.exit(1);
});
