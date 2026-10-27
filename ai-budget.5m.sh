#!/bin/bash
# <xbar.title>AI Budget Monitor</xbar.title>
# <xbar.version>v1.1</xbar.version>
# <xbar.author>Sertac Onal</xbar.author>
# <xbar.author.github>SertacOnal</xbar.author.github>
# <xbar.desc>Monitor Anthropic and OpenAI API budgets</xbar.desc>
# <xbar.dependencies>bash,curl,jq</xbar.dependencies>

# Config file location
CONFIG_FILE="$HOME/.config/ai-budget/config"
CACHE_FILE="$HOME/.config/ai-budget/cache"
ACTIVITY_FILE="$HOME/.config/ai-budget/last_activity"

# Ensure config directory exists
mkdir -p "$HOME/.config/ai-budget"

# Load config
if [[ -f "$CONFIG_FILE" ]]; then
    source "$CONFIG_FILE"
fi

# Check for jq
if ! command -v jq &> /dev/null; then
    echo "💰 --"
    echo "---"
    echo "jq not installed | color=red"
    echo "Install: brew install jq | bash='brew install jq' terminal=true"
    exit 0
fi

# Function to check API activity (OpenCode logs)
check_activity() {
    local log_paths=(
        "$HOME/.local/share/opencode/log/opencode.log"
        "$HOME/Library/Logs/opencode.log"
    )
    
    local latest_mod=0
    for path in "${log_paths[@]}"; do
        if [[ -f "$path" ]]; then
            local mod_time=$(stat -f %m "$path" 2>/dev/null || stat -c %Y "$path" 2>/dev/null)
            if [[ "$mod_time" -gt "$latest_mod" ]]; then
                latest_mod=$mod_time
            fi
        fi
    done
    
    echo "$latest_mod"
}

# Function to test Anthropic API
get_anthropic_status() {
    if [[ -z "$ANTHROPIC_KEY" ]]; then
        echo '{"status":"no_key"}'
        return
    fi
    
    # Simple API test - just check if key is valid
    local response=$(curl -s --max-time 10 \
        -H "x-api-key: $ANTHROPIC_KEY" \
        -H "anthropic-version: 2023-06-01" \
        -H "content-type: application/json" \
        "https://api.anthropic.com/v1/messages" \
        -d '{"model":"claude-3-haiku-20240307","max_tokens":1,"messages":[{"role":"user","content":"hi"}]}' \
        2>/dev/null)
    
    if echo "$response" | jq -e '.id' &>/dev/null; then
        echo '{"status":"active"}'
    elif echo "$response" | jq -e '.error.type' &>/dev/null; then
        local error_type=$(echo "$response" | jq -r '.error.type')
        if [[ "$error_type" == "authentication_error" ]]; then
            echo '{"status":"invalid_key"}'
        else
            echo '{"status":"active"}'  # Other errors mean key works
        fi
    else
        echo '{"status":"unknown"}'
    fi
}

# Function to test OpenAI API and get usage
get_openai_status() {
    if [[ -z "$OPENAI_KEY" ]]; then
        echo '{"status":"no_key"}'
        return
    fi
    
    # Test API with a simple models list call
    local response=$(curl -s --max-time 10 \
        -H "Authorization: Bearer $OPENAI_KEY" \
        "https://api.openai.com/v1/models" \
        2>/dev/null)
    
    if echo "$response" | jq -e '.data' &>/dev/null; then
        # API works, try to get usage info
        local usage_response=$(curl -s --max-time 10 \
            -H "Authorization: Bearer $OPENAI_KEY" \
            "https://api.openai.com/v1/usage?date=$(date +%Y-%m-%d)" \
            2>/dev/null)
        
        # Try organization costs (requires special permissions)
        local start_date=$(date -v-30d +%Y-%m-%d 2>/dev/null || date -d "-30 days" +%Y-%m-%d 2>/dev/null || echo "2026-09-27")
        local end_date=$(date +%Y-%m-%d)
        
        local costs_response=$(curl -s --max-time 10 \
            -H "Authorization: Bearer $OPENAI_KEY" \
            "https://api.openai.com/v1/organization/costs?start_date=$start_date&end_date=$end_date" \
            2>/dev/null)
        
        if echo "$costs_response" | jq -e '.data' &>/dev/null; then
            # Has organization access
            local total_cost=$(echo "$costs_response" | jq '[.data[].costs[].value // 0] | add // 0' 2>/dev/null || echo "0")
            echo '{"status":"active","used":'"${total_cost:-0}"'}'
        else
            # No organization access, just show active
            echo '{"status":"active","note":"org_access_needed"}'
        fi
    elif echo "$response" | jq -e '.error' &>/dev/null; then
        local error_code=$(echo "$response" | jq -r '.error.code // .error.type // "unknown"')
        if [[ "$error_code" == "invalid_api_key" ]]; then
            echo '{"status":"invalid_key"}'
        else
            echo '{"status":"error","error":"'"$error_code"'"}'
        fi
    else
        echo '{"status":"unknown"}'
    fi
}

# Update activity timestamp
update_activity() {
    local current_activity=$(check_activity)
    local last_activity=$(cat "$ACTIVITY_FILE" 2>/dev/null || echo 0)
    
    if [[ "$current_activity" -gt "$last_activity" ]]; then
        echo "$current_activity" > "$ACTIVITY_FILE"
    fi
}

# Load cache if recent
load_cache() {
    if [[ -f "$CACHE_FILE" ]]; then
        local cache_age=$(($(date +%s) - $(stat -f %m "$CACHE_FILE" 2>/dev/null || stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0)))
        local last_activity=$(cat "$ACTIVITY_FILE" 2>/dev/null || echo 0)
        local activity_age=$(($(date +%s) - $last_activity))
        
        # Active: refresh every 5 min (300s), Idle: every 30 min (1800s)
        local refresh_interval=1800
        if [[ $activity_age -lt 600 ]]; then
            refresh_interval=300
        fi
        
        if [[ $cache_age -lt $refresh_interval ]]; then
            cat "$CACHE_FILE"
            return 0
        fi
    fi
    return 1
}

# Save cache
save_cache() {
    echo "$1" > "$CACHE_FILE"
}

# Main
update_activity

# Try to load from cache first
cached_data=$(load_cache)
if [[ $? -eq 0 && -n "$cached_data" ]]; then
    anthropic_data=$(echo "$cached_data" | jq -c '.anthropic // {"status":"unknown"}')
    openai_data=$(echo "$cached_data" | jq -c '.openai // {"status":"unknown"}')
else
    # Fetch fresh data
    anthropic_data=$(get_anthropic_status)
    openai_data=$(get_openai_status)
    
    # Save to cache
    save_cache "{\"anthropic\":$anthropic_data,\"openai\":$openai_data}"
fi

# Menu bar display
openai_used=$(echo "$openai_data" | jq -r '.used // "null"')
if [[ "$openai_used" != "null" && "$openai_used" != "" ]]; then
    echo "💰 \$$(printf "%.2f" "$openai_used") used"
else
    # Check if APIs are active
    anthropic_status=$(echo "$anthropic_data" | jq -r '.status')
    openai_status=$(echo "$openai_data" | jq -r '.status')
    
    if [[ "$anthropic_status" == "active" || "$openai_status" == "active" ]]; then
        echo "💰 Active"
    else
        echo "💰 --"
    fi
fi

echo "---"

# Anthropic section
echo "Anthropic | size=14"
anthropic_status=$(echo "$anthropic_data" | jq -r '.status')
case "$anthropic_status" in
    "active")
        echo "  ● Active | color=green"
        echo "  (Check console for billing)"
        ;;
    "invalid_key")
        echo "  ● Invalid API Key | color=red"
        ;;
    "no_key")
        echo "  No API key configured | color=gray"
        echo "  Set ANTHROPIC_KEY in config | color=blue"
        ;;
    *)
        echo "  ● $anthropic_status | color=orange"
        ;;
esac
echo "  Open Console | href=https://console.anthropic.com/settings/billing"

echo "---"

# OpenAI section
echo "OpenAI | size=14"
openai_status=$(echo "$openai_data" | jq -r '.status')
case "$openai_status" in
    "active")
        echo "  ● Active | color=green"
        openai_used=$(echo "$openai_data" | jq -r '.used // "null"')
        openai_note=$(echo "$openai_data" | jq -r '.note // "null"')
        
        if [[ "$openai_used" != "null" && "$openai_used" != "" ]]; then
            echo "  Used (30d): \$$(printf "%.2f" "$openai_used")"
        fi
        
        if [[ "$openai_note" == "org_access_needed" ]]; then
            echo "  (Enable org access for detailed usage)"
        fi
        ;;
    "invalid_key")
        echo "  ● Invalid API Key | color=red"
        ;;
    "no_key")
        echo "  No API key configured | color=gray"
        echo "  Set OPENAI_KEY in config | color=blue"
        ;;
    "error")
        openai_error=$(echo "$openai_data" | jq -r '.error // "unknown"')
        echo "  ● Error: $openai_error | color=red"
        ;;
    *)
        echo "  ● $openai_status | color=orange"
        ;;
esac
echo "  Open Dashboard | href=https://platform.openai.com/usage"

echo "---"

# Actions
echo "Refresh Now | refresh=true"
echo "Edit Config... | bash='open' param1='$HOME/.config/ai-budget/config' terminal=false"
echo "Open Config Folder... | bash='open' param1='$HOME/.config/ai-budget/' terminal=false"

echo "---"

# Status
last_update=$(stat -f "%Sm" -t "%H:%M" "$CACHE_FILE" 2>/dev/null || echo "never")
echo "Last update: $last_update | color=gray size=11"

activity_age=$(($(date +%s) - $(cat "$ACTIVITY_FILE" 2>/dev/null || echo 0)))
if [[ $activity_age -lt 600 ]]; then
    echo "Mode: Active (5min refresh) | color=green size=11"
else
    echo "Mode: Idle (30min refresh) | color=gray size=11"
fi
