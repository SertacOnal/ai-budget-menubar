# AI Budget Menubar

A macOS menubar plugin to monitor your Anthropic and OpenAI API budgets in one place.

Works with [SwiftBar](https://github.com/swiftbar/SwiftBar) or [xbar](https://xbarapp.com/).

## Features

- 💰 View remaining budget at a glance in menubar
- 📊 Individual breakdowns for Anthropic and OpenAI
- 🔐 Secure local config file for API keys
- ⚡ Smart refresh: 5 min when active, 30 min when idle
- 🔔 Color warnings when budget is low (red < $10, orange < $50)

## Screenshot

```
💰 $142.50
─────────────
Anthropic
  ● Active
  Console →

OpenAI
  ● Active
  Remaining: $142.50
  Used (30d): $57.50
  Limit: $200.00
  Dashboard →
─────────────
Refresh
Configure API Keys...
─────────────
Last update: 14:30
Mode: Active (5min refresh)
```

## Installation

### Quick Install

```bash
git clone https://github.com/SertacOnal/ai-budget-menubar.git
cd ai-budget-menubar
./install.sh
```

### Manual Install

1. Install SwiftBar:
   ```bash
   brew install --cask swiftbar
   ```

2. Install jq (for JSON parsing):
   ```bash
   brew install jq
   ```

3. Copy the plugin:
   ```bash
   cp ai-budget.5m.sh ~/Library/Application\ Support/SwiftBar/Plugins/
   chmod +x ~/Library/Application\ Support/SwiftBar/Plugins/ai-budget.5m.sh
   ```

4. Configure API keys:
   ```bash
   mkdir -p ~/.config/ai-budget
   cat > ~/.config/ai-budget/config << EOF
   ANTHROPIC_KEY="sk-ant-..."
   OPENAI_KEY="sk-..."
   EOF
   chmod 600 ~/.config/ai-budget/config
   ```

5. Launch SwiftBar

## Configuration

API keys are stored in `~/.config/ai-budget/config`:

```bash
ANTHROPIC_KEY="sk-ant-api03-..."
OPENAI_KEY="sk-proj-..."
```

Get your keys from:
- **Anthropic:** https://console.anthropic.com/settings/keys
- **OpenAI:** https://platform.openai.com/api-keys

## Refresh Behavior

The plugin intelligently adjusts its refresh rate based on API activity:

| State | Refresh Interval | Condition |
|-------|-----------------|-----------|
| Active | 5 minutes | OpenCode logs modified in last 10 min |
| Idle | 30 minutes | No recent activity |

Activity is detected by monitoring:
- `~/.local/share/opencode/log/opencode.log`
- `~/Library/Logs/opencode.log`

## API Limitations

### Anthropic
- No public billing API available
- Shows connection status only (Active/Invalid Key)
- For actual usage, check [console.anthropic.com](https://console.anthropic.com/settings/billing)

### OpenAI
- Full usage and limits via Organization API
- Shows: remaining budget, 30-day usage, hard/soft limits
- Requires API key with organization access

## Files

| File | Purpose |
|------|---------|
| `~/.config/ai-budget/config` | API keys (chmod 600) |
| `~/.config/ai-budget/cache` | Cached API responses |
| `~/.config/ai-budget/last_activity` | Activity timestamp |

## Troubleshooting

### "jq not found"
```bash
brew install jq
```

### Plugin not appearing
1. Make sure SwiftBar is running
2. Check plugin is executable: `chmod +x ~/Library/Application\ Support/SwiftBar/Plugins/ai-budget.5m.sh`
3. Open SwiftBar preferences and set plugins folder

### Invalid API key
Check your key in `~/.config/ai-budget/config` - no extra spaces or quotes issues.

### OpenAI shows no limit
Your API key may not have organization access. Check [platform.openai.com/organization](https://platform.openai.com/organization).

## License

MIT

## Contributing

PRs welcome! Please open an issue first for major changes.
