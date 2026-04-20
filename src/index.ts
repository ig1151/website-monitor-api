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
