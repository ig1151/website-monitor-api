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
