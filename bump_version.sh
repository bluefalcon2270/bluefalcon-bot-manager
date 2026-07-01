#!/bin/bash
# ==========================================
# BlueFalcon Version Bumper Utility
# ==========================================

if [ -z "$1" ]; then
    echo "Usage: ./bump_version.sh <new_version>"
    echo "Example: ./bump_version.sh 3.6.0"
    exit 1
fi

NEW_VERSION=$1

# Update VERSION file
echo "$NEW_VERSION" > VERSION
echo "✅ Updated VERSION file to $NEW_VERSION"

# Prepend entry to CHANGELOG.md safely
if [ -f "CHANGELOG.md" ]; then
    # Create temporary file
    TMP_FILE=$(mktemp)
    
    # Read first 4 lines (Header)
    head -n 4 CHANGELOG.md > "$TMP_FILE"
    
    # Insert new version entry
    echo "## v${NEW_VERSION} (Update Details Here):" >> "$TMP_FILE"
    echo "- Describe your changes here." >> "$TMP_FILE"
    echo "" >> "$TMP_FILE"
    
    # Append the rest of the old changelog
    tail -n +5 CHANGELOG.md >> "$TMP_FILE"
    
    # Replace old changelog with new one
    mv "$TMP_FILE" CHANGELOG.md
    echo "✅ Added template for v${NEW_VERSION} to CHANGELOG.md"
fi

echo "🎉 Version bumped successfully to $NEW_VERSION!"
