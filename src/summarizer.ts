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
