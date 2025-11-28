#!/bin/bash
# Setup script for Infracost

set -e

echo "🔧 Setting up Infracost for cost estimation..."
echo ""

# Check if Infracost is installed
if ! command -v infracost &> /dev/null; then
    echo "📦 Infracost not found. Installing..."
    
    if [[ "$OSTYPE" == "darwin"* ]]; then
        # macOS
        if command -v brew &> /dev/null; then
            brew install infracost
        else
            echo "❌ Homebrew not found. Please install from: https://brew.sh/"
            exit 1
        fi
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        # Linux
        curl -fsSL https://raw.githubusercontent.com/infracost/infracost/master/scripts/install.sh | sh
    else
        echo "❌ Unsupported OS. Please install manually: https://www.infracost.io/docs/#quick-start"
        exit 1
    fi
else
    echo "✅ Infracost already installed: $(infracost --version)"
fi

echo ""
echo "🔑 Setting up Infracost API key..."
echo ""
echo "You need a free Infracost API key. This will open your browser."
echo "Press Enter to continue..."
read

infracost auth login

echo ""
echo "✅ Infracost setup complete!"
echo ""
echo "📊 Running your first cost estimate..."
echo ""

cd terraform
infracost breakdown --path . --usage-file infracost-usage.yml

echo ""
echo "🎉 Done! Your infrastructure costs approximately shown above."
echo ""
echo "Next steps:"
echo "  1. Review the cost breakdown"
echo "  2. Adjust usage estimates in terraform/infracost-usage.yml"
echo "  3. Add INFRACOST_API_KEY to GitHub secrets for PR comments"
echo ""
echo "See docs/COST_ESTIMATION.md for more details!"
