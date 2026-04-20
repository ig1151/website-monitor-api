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
