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
