#!/bin/bash
# <xbar.title>AI Budget Monitor</xbar.title>
# <xbar.version>v1.0</xbar.version>
# <xbar.author>Sertac Onal</xbar.author>
# <xbar.author.github>SertacOnal</xbar.author.github>
# <xbar.desc>Monitor Anthropic and OpenAI API budgets</xbar.desc>
# <xbar.dependencies>bash,curl,jq</xbar.dependencies>
# <xbar.var>string(ANTHROPIC_API_KEY=""): Anthropic API Key</xbar.var>
# <xbar.var>string(OPENAI_API_KEY=""): OpenAI API Key</xbar.var>

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

# Use environment variables if set (SwiftBar vars)
ANTHROPIC_API_KEY="${ANTHROPIC_API_KEY:-$ANTHROPIC_KEY}"
OPENAI_API_KEY="${OPENAI_API_KEY:-$OPENAI_KEY}"

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

# Function to get Anthropic usage
get_anthropic_usage() {
    if [[ -z "$ANTHROPIC_API_KEY" ]]; then
        echo "null"
        return
    fi
    
    # Try the admin API for organization billing
    local response=$(curl -s --max-time 10 \
        -H "x-api-key: $ANTHROPIC_API_KEY" \
        -H "anthropic-version: 2023-06-01" \
        "https://api.anthropic.com/v1/messages" \
        -d '{"model":"claude-3-haiku-20240307","max_tokens":1,"messages":[{"role":"user","content":"hi"}]}' \
        -X POST 2>/dev/null)
    
    # Check for rate limit headers or error responses to estimate usage
    # Anthropic doesn't have a direct billing API, so we show "API Active" status
    if echo "$response" | jq -e '.id' &>/dev/null; then
        echo '{"status":"active","provider":"Anthropic"}'
    elif echo "$response" | jq -e '.error' &>/dev/null; then
        local error_type=$(echo "$response" | jq -r '.error.type')
        if [[ "$error_type" == "authentication_error" ]]; then
            echo '{"status":"invalid_key","provider":"Anthropic"}'
        else
            echo '{"status":"error","provider":"Anthropic","error":"'"$error_type"'"}'
        fi
    else
        echo '{"status":"unknown","provider":"Anthropic"}'
    fi
}

# Function to get OpenAI usage
get_openai_usage() {
    if [[ -z "$OPENAI_API_KEY" ]]; then
        echo "null"
        return
    fi
    
    local start_date=$(date -v-30d +%Y-%m-%d 2>/dev/null || date -d "-30 days" +%Y-%m-%d)
    local end_date=$(date +%Y-%m-%d)
    
    # Get usage/costs
    local costs_response=$(curl -s --max-time 10 \
        -H "Authorization: Bearer $OPENAI_API_KEY" \
        "https://api.openai.com/v1/organization/costs?start_date=$start_date&end_date=$end_date" 2>/dev/null)
    
    # Get subscription/limits
    local sub_response=$(curl -s --max-time 10 \
        -H "Authorization: Bearer $OPENAI_API_KEY" \
        "https://api.openai.com/v1/organization/subscription" 2>/dev/null)
    
    # Parse costs
    local total_cost=0
    if echo "$costs_response" | jq -e '.data' &>/dev/null; then
        total_cost=$(echo "$costs_response" | jq '[.data[].costs[].value // 0] | add // 0')
    fi
    
    # Parse limits
    local hard_limit=$(echo "$sub_response" | jq -r '.hard_limit_usd // "null"')
    local soft_limit=$(echo "$sub_response" | jq -r '.soft_limit_usd // "null"')
    
    local limit="null"
    if [[ "$hard_limit" != "null" ]]; then
        limit=$hard_limit
    elif [[ "$soft_limit" != "null" ]]; then
        limit=$soft_limit
    fi
    
    local remaining="null"
    if [[ "$limit" != "null" ]]; then
        remaining=$(echo "$limit - $total_cost" | bc 2>/dev/null || echo "null")
    fi
    
    # Check for errors
    if echo "$costs_response" | jq -e '.error' &>/dev/null; then
        local error_type=$(echo "$costs_response" | jq -r '.error.type // .error.code // "unknown"')
        echo '{"status":"error","provider":"OpenAI","error":"'"$error_type"'"}'
    else
        echo '{"status":"active","provider":"OpenAI","used":'"$total_cost"',"limit":'"$limit"',"remaining":'"$remaining"'}'
    fi
}

# Load cache if recent (within refresh interval)
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

# Update activity timestamp
update_activity() {
    local current_activity=$(check_activity)
    local last_activity=$(cat "$ACTIVITY_FILE" 2>/dev/null || echo 0)
    
    if [[ "$current_activity" -gt "$last_activity" ]]; then
        echo "$current_activity" > "$ACTIVITY_FILE"
    fi
}

# Main
update_activity

# Try to load from cache first
cached_data=$(load_cache)
if [[ $? -eq 0 && -n "$cached_data" ]]; then
    anthropic_data=$(echo "$cached_data" | jq -r '.anthropic // "null"')
    openai_data=$(echo "$cached_data" | jq -r '.openai // "null"')
else
    # Fetch fresh data
    anthropic_data=$(get_anthropic_usage)
    openai_data=$(get_openai_usage)
    
    # Save to cache
    save_cache "{\"anthropic\":$anthropic_data,\"openai\":$openai_data}"
fi

# Calculate total
total="--"
openai_remaining=$(echo "$openai_data" | jq -r '.remaining // "null"')
if [[ "$openai_remaining" != "null" ]]; then
    total=$(printf "%.2f" "$openai_remaining")
fi

# Menu bar display
if [[ "$total" == "--" ]]; then
    echo "💰 --"
else
    # Color based on remaining budget
    if (( $(echo "$openai_remaining < 10" | bc -l 2>/dev/null || echo 0) )); then
        echo "💰 \$$total | color=red"
    elif (( $(echo "$openai_remaining < 50" | bc -l 2>/dev/null || echo 0) )); then
        echo "💰 \$$total | color=orange"
    else
        echo "💰 \$$total"
    fi
fi

echo "---"

# Anthropic section
echo "Anthropic | size=14"
if [[ "$anthropic_data" == "null" ]]; then
    echo "  No API key configured | color=gray"
    echo "  Set ANTHROPIC_API_KEY | color=blue href=https://console.anthropic.com/settings/keys"
else
    local status=$(echo "$anthropic_data" | jq -r '.status')
    case "$status" in
        "active")
            echo "  ● Active | color=green"
            echo "  (Billing API not available)"
            ;;
        "invalid_key")
            echo "  ● Invalid API Key | color=red"
            ;;
        *)
            echo "  ● $status | color=orange"
            ;;
    esac
fi
echo "  Console | href=https://console.anthropic.com/settings/billing"

echo "---"

# OpenAI section
echo "OpenAI | size=14"
if [[ "$openai_data" == "null" ]]; then
    echo "  No API key configured | color=gray"
    echo "  Set OPENAI_API_KEY | color=blue href=https://platform.openai.com/api-keys"
else
    local status=$(echo "$openai_data" | jq -r '.status')
    local used=$(echo "$openai_data" | jq -r '.used // "?"')
    local limit=$(echo "$openai_data" | jq -r '.limit // "?"')
    local remaining=$(echo "$openai_data" | jq -r '.remaining // "?"')
    
    case "$status" in
        "active")
            echo "  ● Active | color=green"
            if [[ "$remaining" != "null" && "$remaining" != "?" ]]; then
                echo "  Remaining: \$$(printf "%.2f" "$remaining")"
            fi
            if [[ "$used" != "null" && "$used" != "?" ]]; then
                echo "  Used (30d): \$$(printf "%.2f" "$used")"
            fi
            if [[ "$limit" != "null" && "$limit" != "?" ]]; then
                echo "  Limit: \$$(printf "%.2f" "$limit")"
            fi
            ;;
        "error")
            local error=$(echo "$openai_data" | jq -r '.error // "unknown"')
            echo "  ● Error: $error | color=red"
            ;;
        *)
            echo "  ● $status | color=orange"
            ;;
    esac
fi
echo "  Dashboard | href=https://platform.openai.com/usage"

echo "---"

# Footer
echo "Refresh | refresh=true"
echo "Configure API Keys... | bash='open $HOME/.config/ai-budget/' terminal=false"
echo "---"
last_update=$(stat -f "%Sm" -t "%H:%M" "$CACHE_FILE" 2>/dev/null || echo "never")
echo "Last update: $last_update | color=gray size=11"

# Activity status
activity_age=$(($(date +%s) - $(cat "$ACTIVITY_FILE" 2>/dev/null || echo 0)))
if [[ $activity_age -lt 600 ]]; then
    echo "Mode: Active (5min refresh) | color=gray size=11"
else
    echo "Mode: Idle (30min refresh) | color=gray size=11"
fi
