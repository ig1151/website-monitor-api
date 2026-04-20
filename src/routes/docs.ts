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
