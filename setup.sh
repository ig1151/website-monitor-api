#!/bin/bash
set -e

echo "🚀 Setting up Website Monitor API..."

mkdir -p src/routes

cat > package.json << 'ENDPACKAGE'
{
  "name": "website-monitor-api",
  "version": "1.0.0",
  "description": "Monitor any URL for changes — detects content diffs, summarizes what changed and delivers alerts via webhook.",
  "main": "dist/index.js",
  "scripts": {
    "build": "tsc",
    "dev": "ts-node-dev --respawn --transpile-only src/index.ts",
    "start": "node dist/index.js"
  },
  "dependencies": {
    "axios": "^1.6.0",
    "cheerio": "^1.0.0",
    "compression": "^1.7.4",
    "cors": "^2.8.5",
    "express": "^4.18.2",
    "express-rate-limit": "^7.1.5",
    "helmet": "^7.1.0",
    "joi": "^17.11.0",
    "node-cron": "^3.0.3",
    "uuid": "^9.0.0"
  },
  "devDependencies": {
    "@types/compression": "^1.7.5",
    "@types/cors": "^2.8.17",
    "@types/express": "^4.17.21",
    "@types/node": "^20.10.0",
    "@types/node-cron": "^3.0.11",
    "@types/uuid": "^9.0.7",
    "ts-node-dev": "^2.0.0",
    "typescript": "^5.3.2"
  }
}
ENDPACKAGE

cat > tsconfig.json << 'ENDTSCONFIG'
{
  "compilerOptions": {
    "target": "ES2020",
    "module": "commonjs",
    "lib": ["ES2020"],
    "outDir": "./dist",
    "rootDir": "./src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "resolveJsonModule": true
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules", "dist"]
}
ENDTSCONFIG

cat > render.yaml << 'ENDRENDER'
services:
  - type: web
    name: website-monitor-api
    env: node
    buildCommand: npm install && npm run build
    startCommand: node dist/index.js
    healthCheckPath: /v1/health
    envVars:
      - key: NODE_ENV
        value: production
      - key: PORT
        value: 10000
      - key: ANTHROPIC_API_KEY
        sync: false
ENDRENDER

cat > .gitignore << 'ENDGITIGNORE'
node_modules/
dist/
.env
*.log
ENDGITIGNORE

cat > src/logger.ts << 'ENDLOGGER'
export const logger = {
  info: (obj: unknown, msg?: string) =>
    console.log(JSON.stringify({ level: 'info', ...(typeof obj === 'object' ? obj : { data: obj }), msg })),
  warn: (obj: unknown, msg?: string) =>
    console.warn(JSON.stringify({ level: 'warn', ...(typeof obj === 'object' ? obj : { data: obj }), msg })),
  error: (obj: unknown, msg?: string) =>
    console.error(JSON.stringify({ level: 'error', ...(typeof obj === 'object' ? obj : { data: obj }), msg })),
};
ENDLOGGER

cat > src/types.ts << 'ENDTYPES'
export type MonitorStatus = 'active' | 'paused';
export type ChangeType = 'content' | 'title' | 'price' | 'status';

export interface Monitor {
  id: string;
  url: string;
  label?: string;
  status: MonitorStatus;
  webhook_url?: string;
  check_interval_minutes: number;
  selector?: string;
  created_at: string;
  last_checked?: string;
  next_check?: string;
  last_hash?: string;
  last_content?: string;
  check_count: number;
  change_count: number;
}

export interface ChangeRecord {
  id: string;
  timestamp: string;
  changed: boolean;
  change_type?: ChangeType;
  summary?: string;
  diff_snippet?: string;
  previous_hash?: string;
  current_hash?: string;
  webhook_sent: boolean;
}
ENDTYPES

cat > src/store.ts << 'ENDSTORE'
import { Monitor, ChangeRecord } from './types';

const monitors = new Map<string, Monitor>();
const history = new Map<string, ChangeRecord[]>();
const MAX_HISTORY = 50;

export const store = {
  create(monitor: Monitor): void {
    monitors.set(monitor.id, monitor);
    history.set(monitor.id, []);
  },

  get(id: string): Monitor | undefined {
    return monitors.get(id);
  },

  getAll(): Monitor[] {
    return Array.from(monitors.values());
  },

  update(id: string, patch: Partial<Monitor>): void {
    const monitor = monitors.get(id);
    if (monitor) monitors.set(id, { ...monitor, ...patch });
  },

  delete(id: string): boolean {
    history.delete(id);
    return monitors.delete(id);
  },

  addHistory(id: string, record: ChangeRecord): void {
    const records = history.get(id) ?? [];
    records.unshift(record);
    if (records.length > MAX_HISTORY) records.pop();
    history.set(id, records);
  },

  getHistory(id: string, limit = 10): ChangeRecord[] {
    return (history.get(id) ?? []).slice(0, limit);
  },

  count(): number {
    return monitors.size;
  },
};
ENDSTORE

cat > src/differ.ts << 'ENDDIFF'
import axios from 'axios';
import * as cheerio from 'cheerio';
import crypto from 'crypto';

const USER_AGENT = 'Mozilla/5.0 (compatible; WebsiteMonitorBot/1.0)';

export async function fetchContent(url: string, selector?: string): Promise<{ text: string; hash: string; title: string; status: number }> {
  const res = await axios.get(url, {
    timeout: 15000,
    headers: { 'User-Agent': USER_AGENT, 'Accept': 'text/html' },
    maxRedirects: 5,
  });

  const $ = cheerio.load(res.data as string);
  $('script, style, nav, footer, noscript').remove();

  let text: string;
  if (selector) {
    text = $(selector).text().replace(/\s+/g, ' ').trim();
  } else {
    text = $('body').text().replace(/\s+/g, ' ').trim().slice(0, 10000);
  }

  const title = $('title').text().trim();
  const hash = crypto.createHash('md5').update(text).digest('hex');

  return { text, hash, title, status: res.status };
}

export function extractDiff(prev: string, curr: string, maxLen = 300): string {
  const prevWords = new Set(prev.split(/\s+/));
  const currWords = curr.split(/\s+/);
  const added = currWords.filter(w => w.length > 3 && !prevWords.has(w)).slice(0, 20);

  const prevSet = new Set(curr.split(/\s+/));
  const prevArr = prev.split(/\s+/);
  const removed = prevArr.filter(w => w.length > 3 && !prevSet.has(w)).slice(0, 20);

  const parts: string[] = [];
  if (added.length > 0) parts.push(`Added: ${added.join(', ')}`);
  if (removed.length > 0) parts.push(`Removed: ${removed.join(', ')}`);

  return parts.join(' | ').slice(0, maxLen) || 'Content changed';
}

export function detectChangeType(prev: string, curr: string): 'price' | 'content' | 'title' {
  const pricePattern = /\$[\d,]+\.?\d*|\d+\.?\d*\s*USD/i;
  const prevPrices = prev.match(pricePattern);
  const currPrices = curr.match(pricePattern);
  if (prevPrices && currPrices && prevPrices[0] !== currPrices[0]) return 'price';
  return 'content';
}
ENDDIFF

cat > src/summarizer.ts << 'ENDSUMMARIZER'
import axios from 'axios';

export async function summarizeChange(url: string, diff: string): Promise<string> {
  const apiKey = process.env.ANTHROPIC_API_KEY;
  if (!apiKey) return diff;

  try {
    const res = await axios.post(
      'https://api.anthropic.com/v1/messages',
      {
        model: 'claude-sonnet-4-20250514',
        max_tokens: 100,
        messages: [{
          role: 'user',
          content: `A website changed at ${url}. Here is what changed: "${diff}". Summarize this change in one short sentence (max 15 words). Be specific and factual.`,
        }],
      },
      {
        headers: {
          'x-api-key': apiKey,
          'anthropic-version': '2023-06-01',
          'content-type': 'application/json',
        },
        timeout: 10000,
      }
    );
    return res.data.content[0]?.text?.trim() ?? diff;
  } catch {
    return diff;
  }
}
ENDSUMMARIZER

cat > src/scheduler.ts << 'ENDSCHEDULER'
import cron from 'node-cron';
import axios from 'axios';
import { v4 as uuidv4 } from 'uuid';
import { store } from './store';
import { logger } from './logger';
import { fetchContent, extractDiff, detectChangeType } from './differ';
import { summarizeChange } from './summarizer';
import { ChangeRecord } from './types';

const INTERVAL_MINUTES = 5;

function getNextCheck(): string {
  return new Date(Date.now() + INTERVAL_MINUTES * 60 * 1000).toISOString();
}

async function checkMonitor(monitorId: string): Promise<void> {
  const monitor = store.get(monitorId);
  if (!monitor || monitor.status !== 'active') return;

  try {
    const { text, hash, status } = await fetchContent(monitor.url, monitor.selector);
    const now = new Date().toISOString();
    const changed = !!monitor.last_hash && monitor.last_hash !== hash;
    let summary: string | undefined;
    let diff_snippet: string | undefined;
    let webhookSent = false;

    if (changed && monitor.last_content) {
      diff_snippet = extractDiff(monitor.last_content, text);
      const changeType = detectChangeType(monitor.last_content, text);
      summary = await summarizeChange(monitor.url, diff_snippet);

      if (monitor.webhook_url) {
        try {
          await axios.post(monitor.webhook_url, {
            event: 'website.changed',
            monitor_id: monitor.id,
            url: monitor.url,
            label: monitor.label,
            change_type: changeType,
            summary,
            diff_snippet,
            timestamp: now,
          }, { timeout: 8000 });
          webhookSent = true;
        } catch (err) {
          logger.warn({ monitorId, err }, 'Webhook delivery failed');
        }
      }

      logger.info({ monitorId, url: monitor.url, summary }, 'Change detected');
    }

    const record: ChangeRecord = {
      id: uuidv4(),
      timestamp: now,
      changed,
      change_type: changed ? detectChangeType(monitor.last_content ?? '', text) : undefined,
      summary,
      diff_snippet,
      previous_hash: monitor.last_hash,
      current_hash: hash,
      webhook_sent: webhookSent,
    };

    store.addHistory(monitorId, record);
    store.update(monitorId, {
      last_checked: now,
      next_check: getNextCheck(),
      last_hash: hash,
      last_content: text,
      check_count: (monitor.check_count ?? 0) + 1,
      change_count: (monitor.change_count ?? 0) + (changed ? 1 : 0),
      status: status >= 400 ? 'paused' : monitor.status,
    });
  } catch (err) {
    logger.error({ monitorId, err }, 'Monitor check failed');
  }
}

export function startScheduler(): void {
  cron.schedule('*/5 * * * *', async () => {
    const active = store.getAll().filter(m => m.status === 'active');
    if (active.length === 0) return;
    logger.info({ count: active.length }, 'Scheduler tick — checking monitors');
    await Promise.allSettled(active.map(m => checkMonitor(m.id)));
  });

  logger.info({}, 'Website monitor scheduler started — runs every 5 minutes');
}

export { getNextCheck };
ENDSCHEDULER

cat > src/routes/monitors.ts << 'ENDMONITORS'
import { Router, Request, Response } from 'express';
import Joi from 'joi';
import { v4 as uuidv4 } from 'uuid';
import { store } from '../store';
import { logger } from '../logger';
import { Monitor } from '../types';
import { getNextCheck } from '../scheduler';
import { fetchContent } from '../differ';

const router = Router();

const createSchema = Joi.object({
  url: Joi.string().uri().required(),
  label: Joi.string().max(100).optional(),
  webhook_url: Joi.string().uri().optional(),
  selector: Joi.string().max(200).optional(),
  check_interval_minutes: Joi.number().integer().min(5).max(1440).default(5),
});

const updateSchema = Joi.object({
  label: Joi.string().max(100).optional(),
  webhook_url: Joi.string().uri().optional(),
  selector: Joi.string().max(200).optional(),
  status: Joi.string().valid('active', 'paused').optional(),
});

// POST /v1/monitors — create monitor
router.post('/', async (req: Request, res: Response) => {
  const { error, value } = createSchema.validate(req.body);
  if (error) {
    res.status(400).json({ error: 'Validation failed', details: error.details[0].message });
    return;
  }

  // Take initial snapshot
  let initialHash: string | undefined;
  let initialContent: string | undefined;
  try {
    const { text, hash } = await fetchContent(value.url, value.selector);
    initialHash = hash;
    initialContent = text;
  } catch {
    // Continue without snapshot — will detect on first check
  }

  const monitor: Monitor = {
    id: uuidv4(),
    url: value.url,
    label: value.label,
    webhook_url: value.webhook_url,
    selector: value.selector,
    check_interval_minutes: value.check_interval_minutes,
    status: 'active',
    created_at: new Date().toISOString(),
    next_check: getNextCheck(),
    last_hash: initialHash,
    last_content: initialContent,
    check_count: 0,
    change_count: 0,
  };

  store.create(monitor);
  logger.info({ id: monitor.id, url: monitor.url }, 'Monitor created');

  res.status(201).json({
    id: monitor.id,
    url: monitor.url,
    label: monitor.label,
    status: monitor.status,
    webhook_enabled: !!monitor.webhook_url,
    next_check: monitor.next_check,
    snapshot_taken: !!initialHash,
    message: 'Monitor active — checks every 5 minutes',
  });
});

// GET /v1/monitors — list all
router.get('/', (_req: Request, res: Response) => {
  const all = store.getAll();
  res.json({ monitors: all, count: all.length });
});

// GET /v1/monitors/:id
router.get('/:id', (req: Request, res: Response) => {
  const monitor = store.get(req.params.id);
  if (!monitor) { res.status(404).json({ error: 'Monitor not found' }); return; }
  res.json(monitor);
});

// GET /v1/monitors/:id/history
router.get('/:id/history', (req: Request, res: Response) => {
  const monitor = store.get(req.params.id);
  if (!monitor) { res.status(404).json({ error: 'Monitor not found' }); return; }
  const limit = Math.min(parseInt(req.query.limit as string) || 10, 50);
  const records = store.getHistory(req.params.id, limit);
  res.json({ id: req.params.id, url: monitor.url, count: records.length, history: records });
});

// PATCH /v1/monitors/:id
router.patch('/:id', (req: Request, res: Response) => {
  const monitor = store.get(req.params.id);
  if (!monitor) { res.status(404).json({ error: 'Monitor not found' }); return; }
  const { error, value } = updateSchema.validate(req.body);
  if (error) { res.status(400).json({ error: 'Validation failed', details: error.details[0].message }); return; }
  store.update(req.params.id, value);
  logger.info({ id: req.params.id }, 'Monitor updated');
  res.json({ id: req.params.id, ...value });
});

// DELETE /v1/monitors/:id
router.delete('/:id', (req: Request, res: Response) => {
  const monitor = store.get(req.params.id);
  if (!monitor) { res.status(404).json({ error: 'Monitor not found' }); return; }
  store.delete(req.params.id);
  logger.info({ id: req.params.id }, 'Monitor deleted');
  res.json({ id: req.params.id, status: 'deleted' });
});

export default router;
ENDMONITORS

cat > src/routes/docs.ts << 'ENDDOCS'
import { Router, Request, Response } from 'express';
const router = Router();

router.get('/', (_req: Request, res: Response) => {
  res.send(`<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8"/>
  <meta name="viewport" content="width=device-width, initial-scale=1.0"/>
  <title>Website Monitor API</title>
  <style>
    body { font-family: system-ui, sans-serif; max-width: 860px; margin: 40px auto; padding: 0 20px; background: #0f0f0f; color: #e0e0e0; }
    h1 { color: #7c3aed; } h2 { color: #a78bfa; border-bottom: 1px solid #333; padding-bottom: 8px; }
    pre { background: #1a1a1a; padding: 16px; border-radius: 8px; overflow-x: auto; font-size: 13px; }
    code { color: #c084fc; }
    .badge { display: inline-block; padding: 2px 10px; border-radius: 12px; font-size: 12px; margin-right: 8px; color: white; }
    .get { background: #065f46; } .post { background: #7c3aed; } .delete { background: #991b1b; } .patch { background: #92400e; }
    table { width: 100%; border-collapse: collapse; } td, th { padding: 8px 12px; border: 1px solid #333; text-align: left; }
    th { background: #1a1a1a; }
  </style>
</head>
<body>
  <h1>Website Monitor API</h1>
  <p>Monitor any URL for changes — detects content diffs, summarizes what changed and delivers alerts via webhook.</p>
  <h2>Endpoints</h2>
  <table>
    <tr><th>Method</th><th>Path</th><th>Description</th></tr>
    <tr><td><span class="badge post">POST</span></td><td>/v1/monitors</td><td>Create a monitor</td></tr>
    <tr><td><span class="badge get">GET</span></td><td>/v1/monitors</td><td>List all monitors</td></tr>
    <tr><td><span class="badge get">GET</span></td><td>/v1/monitors/:id</td><td>Get monitor status</td></tr>
    <tr><td><span class="badge get">GET</span></td><td>/v1/monitors/:id/history</td><td>Get change history</td></tr>
    <tr><td><span class="badge patch">PATCH</span></td><td>/v1/monitors/:id</td><td>Update or pause monitor</td></tr>
    <tr><td><span class="badge delete">DELETE</span></td><td>/v1/monitors/:id</td><td>Delete monitor</td></tr>
    <tr><td><span class="badge get">GET</span></td><td>/v1/health</td><td>Health check</td></tr>
  </table>
  <h2>Create Monitor</h2>
  <pre>POST /v1/monitors
{
  "url": "https://example.com/pricing",
  "label": "Competitor pricing page",
  "webhook_url": "https://your-app.com/webhook",
  "selector": ".price",
  "check_interval_minutes": 5
}</pre>
  <p><a href="/openapi.json" style="color:#a78bfa">OpenAPI JSON</a></p>
</body>
</html>`);
});

export default router;
ENDDOCS

cat > src/routes/openapi.ts << 'ENDOPENAPI'
import { Router, Request, Response } from 'express';
const router = Router();

router.get('/', (_req: Request, res: Response) => {
  res.json({
    openapi: '3.0.0',
    info: {
      title: 'Website Monitor API',
      version: '1.0.0',
      description: 'Monitor any URL for changes — detects content diffs, summarizes what changed and delivers alerts via webhook.',
    },
    servers: [{ url: 'https://website-monitor-api.onrender.com' }],
    paths: {
      '/v1/monitors': {
        post: { summary: 'Create a monitor', responses: { '201': { description: 'Monitor created' } } },
        get: { summary: 'List all monitors', responses: { '200': { description: 'Monitor list' } } },
      },
      '/v1/monitors/{id}': {
        get: { summary: 'Get monitor status', responses: { '200': { description: 'Monitor object' } } },
        patch: { summary: 'Update or pause monitor', responses: { '200': { description: 'Updated' } } },
        delete: { summary: 'Delete monitor', responses: { '200': { description: 'Deleted' } } },
      },
      '/v1/monitors/{id}/history': {
        get: { summary: 'Get change history', responses: { '200': { description: 'Change records' } } },
      },
      '/v1/health': {
        get: { summary: 'Health check', responses: { '200': { description: 'OK' } } },
      },
    },
  });
});

export default router;
ENDOPENAPI

cat > src/index.ts << 'ENDINDEX'
import express from 'express';
import helmet from 'helmet';
import cors from 'cors';
import compression from 'compression';
import rateLimit from 'express-rate-limit';
import { logger } from './logger';
import { startScheduler } from './scheduler';
import monitorsRouter from './routes/monitors';
import docsRouter from './routes/docs';
import openapiRouter from './routes/openapi';
import { store } from './store';

const app = express();
const PORT = process.env.PORT || 3000;

app.use(helmet());
app.use(cors());
app.use(compression());
app.use(express.json());
app.use(rateLimit({ windowMs: 60_000, max: 60, standardHeaders: true, legacyHeaders: false }));

app.get('/', (_req, res) => {
  res.json({
    service: 'website-monitor-api',
    version: '1.0.0',
    description: 'Monitor any URL for changes — detects content diffs, summarizes what changed and delivers alerts via webhook.',
    status: 'ok',
    docs: '/docs',
    health: '/v1/health',
    active_monitors: store.count(),
    endpoints: {
      create_monitor: 'POST /v1/monitors',
      list_monitors: 'GET /v1/monitors',
      get_monitor: 'GET /v1/monitors/:id',
      get_history: 'GET /v1/monitors/:id/history',
      update_monitor: 'PATCH /v1/monitors/:id',
      delete_monitor: 'DELETE /v1/monitors/:id',
    },
  });
});

app.get('/v1/health', (_req, res) => {
  res.json({
    status: 'ok',
    service: 'website-monitor-api',
    active_monitors: store.count(),
    timestamp: new Date().toISOString(),
  });
});

app.use('/v1/monitors', monitorsRouter);
app.use('/docs', docsRouter);
app.use('/openapi.json', openapiRouter);

app.use((req, res) => {
  res.status(404).json({ error: 'Not found', path: req.path });
});

startScheduler();

app.listen(PORT, () => {
  logger.info({ port: PORT }, 'Website Monitor API running');
});
ENDINDEX

echo "✅ All files created!"
echo "Next: npm install && npm run dev"