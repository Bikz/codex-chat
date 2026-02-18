#!/bin/bash
# Checks for secrets in staged files using gitleaks

if ! command -v gitleaks &> /dev/null; then
    echo "⚠️  gitleaks is not installed. Skipping secret scan."
    echo "   To install: brew install gitleaks"
    exit 0
fi

echo "🔒 Running gitleaks check..."
gitleaks protect --staged --verbose --redact

if [ $? -ne 0 ]; then
    echo "❌ gitleaks found secrets in your changes!"
    echo "   Please remove them before committing."
    exit 1
fi

echo "✅ gitleaks check passed."
exit 0
