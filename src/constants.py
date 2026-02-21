"""Application constants and configuration values.

This module centralizes all magic numbers and configuration constants
to improve maintainability and code clarity.
"""

# ============================================================================
# Timing Constants
# ============================================================================

# Default interval between automatic repository updates (in minutes)
DEFAULT_REFRESH_INTERVAL_MINUTES = 360  # 6 hours

# Delay for batching menu updates to reduce UI rebuilds (in seconds)
MENU_UPDATE_BATCH_DELAY_SECONDS = 0.3  # 300ms

# Interval for countdown timer updates (in seconds)
COUNTDOWN_TIMER_INTERVAL_SECONDS = 60  # 1 minute

# ============================================================================
# Performance Constants
# ============================================================================

# Maximum number of concurrent threads for API requests
THREAD_POOL_MAX_WORKERS = 5

# HTTP request timeout (in seconds)
HTTP_REQUEST_TIMEOUT_SECONDS = 10

# Maximum number of HTTP retry attempts
HTTP_MAX_RETRIES = 3

# ============================================================================
# UI Constants
# ============================================================================

# Number of days to consider a release "new" (shows green indicator)
NEW_RELEASE_THRESHOLD_DAYS = 7

# Indicator emoji for new releases
NEW_RELEASE_INDICATOR = "🟢"

# ============================================================================
# System Constants
# ============================================================================

# Launch agent identifier for macOS auto-start
LAUNCH_AGENT_LABEL = "com.nad.githubwatcher"

# Possible Homebrew installation paths (in order of preference)
HOMEBREW_PATHS = [
    "/opt/homebrew/bin/brew",  # Apple Silicon
    "/usr/local/bin/brew"      # Intel
]

# ============================================================================
# API Constants
# ============================================================================

# GitHub API base URL
GITHUB_API_BASE_URL = "https://api.github.com"

# User-Agent header for GitHub API requests
USER_AGENT = "Python-Rumps-GitHubWatcher"
