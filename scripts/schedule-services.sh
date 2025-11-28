#!/bin/bash
# Set up automatic start/stop schedule using cron
# Stops services at night, starts in the morning to save costs

set -e

echo "⏰ Setting up automatic service scheduling..."
echo ""
echo "This will configure cron to:"
echo "  - Stop services at 6 PM (18:00) on weekdays"
echo "  - Start services at 8 AM (08:00) on weekdays"
echo "  - Keep services stopped on weekends"
echo ""
echo "💰 Estimated savings: ~$80/month (running 10 hours/day instead of 24/7)"
echo ""

# Get the absolute path to scripts
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# Create cron entries
CRON_STOP="0 18 * * 1-5 $SCRIPT_DIR/stop-services.sh >> /tmp/ecs-scheduler.log 2>&1"
CRON_START="0 8 * * 1-5 $SCRIPT_DIR/start-services.sh >> /tmp/ecs-scheduler.log 2>&1"

echo "Cron schedule:"
echo "  Stop:  Monday-Friday at 6 PM"
echo "  Start: Monday-Friday at 8 AM"
echo ""

read -p "Do you want to install this schedule? (y/n) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "❌ Cancelled"
    exit 0
fi

# Backup existing crontab
crontab -l > /tmp/crontab.backup 2>/dev/null || true

# Add new entries (remove old ones first if they exist)
(crontab -l 2>/dev/null | grep -v "stop-services.sh" | grep -v "start-services.sh"; echo "$CRON_STOP"; echo "$CRON_START") | crontab -

echo ""
echo "✅ Schedule installed!"
echo ""
echo "📋 Current crontab:"
crontab -l | grep -E "(stop-services|start-services)"
echo ""
echo "📝 Logs will be written to: /tmp/ecs-scheduler.log"
echo ""
echo "To remove schedule:"
echo "  crontab -e  # Then delete the lines with stop-services.sh and start-services.sh"
echo ""
echo "To test manually:"
echo "  $SCRIPT_DIR/stop-services.sh"
echo "  $SCRIPT_DIR/start-services.sh"
