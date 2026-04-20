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
