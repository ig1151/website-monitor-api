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
