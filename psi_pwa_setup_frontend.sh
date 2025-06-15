#!/bin/bash
set -e # Exit immediately if a command exits with a non-zero status.

echo "========================================================="
echo "        PSI PWA Linux Frontend Setup Script"
echo "========================================================="
echo ""
echo "This script will set up the foundational frontend for PSI PWA on Linux."
echo "It handles Node.js/npm installation and React project creation."
echo ""
read -p "Press Enter to begin, or Ctrl+C to cancel..."

echo ""
echo "--- Step 1: Update System Packages ---"
echo "Preparing to update system packages. This will require sudo privileges and you may be prompted for your password."
sudo apt update
echo ""

echo "--- Step 2: Install Node.js and npm (using NodeSource PPA for recent LTS) ---"
# Check if NodeSource PPA is already added
if ! grep -q "nodesource.com" /etc/apt/sources.list /etc/apt/sources.list.d/* 2>/dev/null; then
    echo "Adding NodeSource PPA for Node.js LTS... This step requires sudo privileges."
    # Fetches the NodeSource setup script for the latest LTS (Long Term Support) version of Node.js
    # and executes it using bash with sudo privileges.
    # The -E option for sudo preserves the user's environment, which can be important for some scripts.
    # If this command fails, an error is printed and the script exits.
    curl -fsSL https://deb.nodesource.com/setup_lts.x | sudo -E bash - || { echo "ERROR: Failed to add NodeSource PPA. Please check your internet connection or script permissions and try again."; exit 1; }
else
    echo "NodeSource PPA already configured."
fi
echo "Preparing to install Node.js and npm. This will require sudo privileges and you may be prompted for your password."
# Install Node.js (which typically includes npm). The -y flag auto-confirms the installation.
sudo apt install -y nodejs
echo "Node.js and npm installed."
# Verify the installed versions of Node.js and npm.
echo "Node.js version: $(node -v)"
echo "npm version: $(npm -v)"
echo ""

echo "--- Step 3: Create Project Directories and Navigate to Frontend ---"
# Create the project directory structure.
# The -p flag ensures that parent directories are created if they don't exist,
# and it doesn't error if the directory already exists.
mkdir -p ~/psi_pwa_linux_new/frontend
# Change the current working directory to the newly created/verified frontend directory.
cd ~/psi_pwa_linux_new/frontend
echo "Working directory: $(pwd)" # Display current working directory for confirmation.
echo ""

echo "--- Step 4: Create a new React Project ---"
echo "This will create a basic React application skeleton using create-react-app."
# The '.' argument means the project will be created directly in the current directory.
# The '--template typescript' flag specifies that the project should be set up with TypeScript support.
echo "Please wait, this might take a few minutes..."
# If this command fails (e.g. network issues, npm problems), an error is printed and the script exits.
npx create-react-app . --template typescript || { echo "ERROR: Failed to create React project. Please check for error messages above, ensure Node.js/npm are correctly installed, and that you have internet connectivity."; exit 1; }
echo "React project created."
echo ""

echo "--- Step 5: Install React Project Dependencies ---"
# While create-react-app typically runs 'npm install' as part of its process,
# running it explicitly here acts as a safeguard. It ensures all dependencies
# are correctly installed, which can be helpful if the initial setup was interrupted
# or if there are any lingering inconsistencies.
npm install
echo "Frontend dependencies installed."
echo ""

echo "========================================================="
echo "        PSI PWA Linux Frontend Setup Complete!"
echo "========================================================="
echo ""
echo "To run your React frontend in development mode:"
echo "1. Navigate to the frontend directory: cd ~/psi_pwa_linux_new/frontend"
echo "2. Start the development server: npm start"
echo "   (Access it in your browser, usually at http://localhost:3000)"
echo ""
echo "To build the frontend for production:"
echo "1. Navigate to the frontend directory: cd ~/psi_pwa_linux_new/frontend"
echo "2. Run the build command: npm run build"
echo ""
read -p "Press Enter to finish and exit script..."
