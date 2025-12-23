#!/bin/bash
set -e

# Define the directory for the Flutter SDK to avoid cloning it into the project
FLUTTER_SDK_DIR=~/plezy_flutter_sdk

# --- Flutter SDK Setup ---
echo "--- Setting up Flutter SDK in $FLUTTER_SDK_DIR ---"

# Clone the Flutter repository if it doesn't exist in the dedicated directory
if [ ! -d "$FLUTTER_SDK_DIR" ]; then
  echo "Cloning Flutter repository to $FLUTTER_SDK_DIR..."
  git clone https://github.com/flutter/flutter.git "$FLUTTER_SDK_DIR"
fi

# Navigate to the Flutter SDK directory to run git commands
cd "$FLUTTER_SDK_DIR"

# Switch to the stable channel and pull the latest changes
echo "Switching to the stable channel and pulling the latest changes..."
git checkout stable
git pull

# Pre-cache the Flutter SDK binaries. Running a command like 'flutter doctor'
# triggers the download of the Dart SDK and other platform-specific tools.
echo "Downloading necessary Flutter SDK binaries..."
"$FLUTTER_SDK_DIR/bin/flutter" doctor

# --- Project Setup ---
echo "--- Setting up the Plezy project ---"

# Go back to the original directory where the script was executed
cd - > /dev/null

# Add the specific Flutter SDK to the PATH for the remainder of this script's execution
export PATH="$FLUTTER_SDK_DIR/bin:$PATH"

# Install and upgrade project dependencies
echo "Installing and upgrading project dependencies..."
flutter pub get
flutter pub upgrade



echo "---"
echo "SUCCESS: The environment is set up for this script's execution."
echo
echo "To use this version of Flutter in your current terminal session, run:"
echo "  export PATH=\"$FLUTTER_SDK_DIR/bin:\$PATH\""
echo
echo "For permanent use, add this line to your shell's configuration file (e.g., ~/.bashrc, ~/.zshrc)."
