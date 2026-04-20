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
