import { create } from 'zustand'
import { Command } from '@tauri-apps/plugin-shell'

export interface ClaudeUsageData {
  todayInput: number
  todayOutput: number
  todayCache: number
  totalInput: number
  totalOutput: number
  totalCache: number
}

// Aggregates token usage from ~/.claude/projects/**/*.jsonl
// Each assistant message entry carries a message.usage object with token counts.
const PYTHON_SCRIPT = `
import json, os, glob, datetime, sys
today = datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%d')
s = dict(today_input=0, today_output=0, today_cache=0,
         total_input=0, total_output=0, total_cache=0)
d = os.path.expanduser('~/.claude/projects')
if not os.path.isdir(d):
    print(json.dumps(s)); sys.exit()
for f in glob.glob(d + '/*/*.jsonl'):
    try:
        for line in open(f):
            line = line.strip()
            if not line: continue
            e = json.loads(line)
            msg = e.get('message', {})
            if not isinstance(msg, dict) or msg.get('role') != 'assistant': continue
            u = msg.get('usage', {})
            inp = u.get('input_tokens', 0)
            out = u.get('output_tokens', 0)
            cache = u.get('cache_creation_input_tokens', 0) + u.get('cache_read_input_tokens', 0)
            s['total_input'] += inp; s['total_output'] += out; s['total_cache'] += cache
            ts = e.get('timestamp') or ''
            if ts.startswith(today):
                s['today_input'] += inp; s['today_output'] += out; s['today_cache'] += cache
    except Exception: pass
print(json.dumps(s))
`.trim()

interface ClaudeUsageStore {
  usage: ClaudeUsageData | null
  fetchUsage: () => Promise<void>
}

export const useClaudeUsageStore = create<ClaudeUsageStore>((set) => ({
  usage: null,

  fetchUsage: async () => {
    try {
      // Embed script via base64 to avoid shell quoting issues
      const b64 = btoa(PYTHON_SCRIPT)
      const cmd = `python3 -c "import base64; exec(base64.b64decode('${b64}').decode())"`
      const result = await Command.create('exec-sh', ['-c', cmd]).execute()
      const raw = result.stdout.trim()
      if (!raw) return
      const data = JSON.parse(raw)
      set({
        usage: {
          todayInput: data.today_input,
          todayOutput: data.today_output,
          todayCache: data.today_cache,
          totalInput: data.total_input,
          totalOutput: data.total_output,
          totalCache: data.total_cache,
        },
      })
    } catch {
      // Silently ignore — widget stays hidden if data unavailable
    }
  },
}))
