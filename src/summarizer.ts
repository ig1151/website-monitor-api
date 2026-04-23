import axios from 'axios';

export async function summarizeChange(url: string, diff: string): Promise<string> {
  const apiKey = process.env.OPENROUTER_API_KEY;
  if (!apiKey) return diff;
  try {
    const res = await axios.post(
      'https://openrouter.ai/api/v1/chat/completions',
      {
        model: 'anthropic/claude-sonnet-4-5',
        max_tokens: 100,
        messages: [{
          role: 'user',
          content: `A website changed at ${url}. Here is what changed: "${diff}". Summarize this change in one short sentence (max 15 words). Be specific and factual.`,
        }],
      },
      {
        headers: {
          'Authorization': `Bearer ${apiKey}`,
          'content-type': 'application/json',
        },
        timeout: 10000,
      }
    );
    return res.data.choices[0]?.message?.content?.trim() ?? diff;
  } catch {
    return diff;
  }
}
