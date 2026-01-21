#!/bin/bash
# OMC Pre-Tool-Use Hook
# Enforces delegation by warning when orchestrator attempts direct source file edits

# Read stdin (JSON input from Claude Code)
INPUT=$(cat)

# Extract tool name and file path
TOOL_NAME=""
FILE_PATH=""
if command -v jq &> /dev/null; then
  TOOL_NAME=$(echo "$INPUT" | jq -r '.tool_name // .toolName // ""' 2>/dev/null)
  FILE_PATH=$(echo "$INPUT" | jq -r '.tool_input.file_path // .tool_input.filePath // .toolInput.file_path // .toolInput.filePath // ""' 2>/dev/null)
else
  TOOL_NAME=$(echo "$INPUT" | grep -oP '"tool_name"\s*:\s*"\K[^"]+' | head -1)
  if [ -z "$TOOL_NAME" ]; then
    TOOL_NAME=$(echo "$INPUT" | grep -oP '"toolName"\s*:\s*"\K[^"]+' | head -1)
  fi
  FILE_PATH=$(echo "$INPUT" | grep -oP '"file_path"\s*:\s*"\K[^"]+' | head -1)
  if [ -z "$FILE_PATH" ]; then
    FILE_PATH=$(echo "$INPUT" | grep -oP '"filePath"\s*:\s*"\K[^"]+' | head -1)
  fi
fi

# Handle Bash tool separately - check for file modification patterns
if [ "$TOOL_NAME" = "Bash" ] || [ "$TOOL_NAME" = "bash" ]; then
  # Extract command
  COMMAND=""
  if command -v jq &> /dev/null; then
    COMMAND=$(echo "$INPUT" | jq -r '.tool_input.command // .toolInput.command // ""' 2>/dev/null)
  else
    COMMAND=$(echo "$INPUT" | grep -oP '"command"\s*:\s*"\K[^"]+' | head -1)
  fi

  # Check for file modification patterns
  if echo "$COMMAND" | grep -qE '(sed\s+-i|>\s*[^&]|>>\s*|tee\s+|cat\s+.*>\s*|echo\s+.*>\s*|printf\s+.*>\s*)'; then
    # Check if modifying source files
    SOURCE_PATTERN='\.(ts|tsx|js|jsx|mjs|cjs|py|pyw|go|rs|java|kt|scala|c|cpp|cc|h|hpp|rb|php|svelte|vue|graphql|gql|sh|bash|zsh)'
    if echo "$COMMAND" | grep -qE "$SOURCE_PATTERN"; then
      # Might be modifying source files - warn
      WARNING="[DELEGATION NOTICE] Bash command may modify source files: $COMMAND

Recommended: Delegate to executor agent instead:
  Task(subagent_type=\"oh-my-claudecode:executor\", model=\"sonnet\", prompt=\"...\")

This is a soft warning. Operation will proceed."
      WARNING_ESCAPED=$(echo "$WARNING" | jq -Rs . 2>/dev/null || echo "\"$WARNING\"")
      echo "{\"continue\": true, \"message\": $WARNING_ESCAPED}"
      exit 0
    fi
  fi
  # Bash command is OK
  echo '{"continue": true}'
  exit 0
fi

# Only check Edit and Write tools
if [ "$TOOL_NAME" != "Edit" ] && [ "$TOOL_NAME" != "Write" ] && \
   [ "$TOOL_NAME" != "edit" ] && [ "$TOOL_NAME" != "write" ]; then
  echo '{"continue": true}'
  exit 0
fi

# No file path? Allow
if [ -z "$FILE_PATH" ]; then
  echo '{"continue": true}'
  exit 0
fi

# Check allowed paths (always OK)
if [[ "$FILE_PATH" == *".omc/"* ]] || \
   [[ "$FILE_PATH" == *".claude/"* ]] || \
   [[ "$FILE_PATH" == *"/.claude/"* ]] || \
   [[ "$FILE_PATH" == "CLAUDE.md" ]] || \
   [[ "$FILE_PATH" == *"/CLAUDE.md" ]] || \
   [[ "$FILE_PATH" == "AGENTS.md" ]] || \
   [[ "$FILE_PATH" == *"/AGENTS.md" ]]; then
  echo '{"continue": true}'
  exit 0
fi

# Check if source file extension (should warn)
EXT="${FILE_PATH##*.}"
EXT_LOWER=$(echo "$EXT" | tr '[:upper:]' '[:lower:]')

SOURCE_EXTS="ts tsx js jsx mjs cjs py pyw go rs java kt scala c cpp cc h hpp rb php svelte vue graphql gql sh bash zsh"

IS_SOURCE=false
for src_ext in $SOURCE_EXTS; do
  if [ "$EXT_LOWER" = "$src_ext" ]; then
    IS_SOURCE=true
    break
  fi
done

if [ "$IS_SOURCE" = true ]; then
  # Emit warning but allow (soft enforcement)
  WARNING="[DELEGATION NOTICE] Direct $TOOL_NAME on source file: $FILE_PATH

Recommended: Delegate to executor agent instead:
  Task(subagent_type=\"oh-my-claudecode:executor\", model=\"sonnet\", prompt=\"...\")

This is a soft warning. Operation will proceed."

  # Escape for JSON
  WARNING_ESCAPED=$(echo "$WARNING" | jq -Rs .)
  echo "{\"continue\": true, \"message\": $WARNING_ESCAPED}"
  exit 0
fi

# Not a source file, allow without warning
echo '{"continue": true}'
exit 0
