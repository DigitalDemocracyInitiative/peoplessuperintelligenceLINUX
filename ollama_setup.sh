#!/bin/bash
# ==============================================================================
# PSI PWA Linux Ollama & Core AI Setup Script
#
# Description:
#   This script automates the installation of Ollama, pulls a specified LLM model,
#   and sets up a project directory. It is designed for Linux systems with systemd.
#
# Usage:
#   ./ollama_setup.sh [options] [PROJECT_DIRECTORY] [MODEL_NAME]
#
# Options:
#   -y, --yes   : Skip all confirmation prompts and proceed with defaults.
#   -h, --help  : Display this help message and exit.
#
# Arguments:
#   PROJECT_DIRECTORY : Optional. Path to the project directory.
#                       Defaults to '~/psi_pwa_linux_new'.
#   MODEL_NAME        : Optional. Name of the Ollama model to pull.
#                       Defaults to 'mistral'.
#
# Dependencies:
#   - curl: For downloading the Ollama installation script.
#   - systemd: For managing the Ollama service (systemctl).
#   - sudo: Required for installing Ollama and managing the service.
#
# Exit Codes:
#   0: Success
#   1: General error / Prerequisites not met
#   2: Ollama installation failed
#   3: Ollama service failed to start
# ==============================================================================

set -e  # Exit immediately if a command exits with a non-zero status.
set -o pipefail # Causes a pipeline to return the exit status of the last command in the pipe that failed.

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check for required dependencies
check_dependencies() {
    local missing_deps=0
    if ! command_exists curl; then
        echo "ERROR: 'curl' is not installed. Please install curl and try again." >&2
        missing_deps=1
    fi
    if ! command_exists systemctl; then
        echo "ERROR: 'systemctl' is not installed. This script requires a systemd-based Linux distribution." >&2
        missing_deps=1
    fi
    if [ "$missing_deps" -eq 1 ]; then
        exit 1
    fi
    echo "All required dependencies (curl, systemctl) are present."
}

# Function to inform about sudo usage
inform_sudo_usage() {
    echo "INFO: This script will use 'sudo' for operations like installing Ollama and managing system services."
    echo "You may be prompted for your password."
}

# --- Initial Checks ---
echo "--- Step 0: Initial Checks ---"
check_dependencies
inform_sudo_usage
echo ""

# --- Configuration ---
DEFAULT_PROJECT_DIR="~/psi_pwa_linux_new"
DEFAULT_MODEL_NAME="mistral"
INTERACTIVE_MODE=true
PROJECT_DIR=""
MODEL_NAME=""

# Function to display help message
display_help() {
    echo "PSI PWA Linux Ollama & Core AI Setup Script"
    echo "--------------------------------------------------"
    echo "This script automates the installation of Ollama, pulls a specified LLM model,"
    echo "and sets up a project directory."
    echo ""
    echo "Usage: $0 [options] [PROJECT_DIRECTORY] [MODEL_NAME]"
    echo ""
    echo "Options:"
    echo "  -y, --yes   : Skip all confirmation prompts and proceed with defaults."
    echo "  -h, --help  : Display this help message and exit."
    echo ""
    echo "Arguments:"
    echo "  PROJECT_DIRECTORY : Optional. Path to the project directory."
    echo "                      Defaults to '$DEFAULT_PROJECT_DIR'."
    echo "  MODEL_NAME        : Optional. Name of the Ollama model to pull."
    echo "                      Defaults to '$DEFAULT_MODEL_NAME'."
    echo ""
    echo "Dependencies:"
    echo "  - curl, systemctl, sudo"
    exit 0
}

# --- Argument Parsing ---
# Initialize variables from defaults
PROJECT_DIR="$DEFAULT_PROJECT_DIR"
MODEL_NAME="$DEFAULT_MODEL_NAME"

# Parse options
POS_ARG1_SET=""
POS_ARG2_SET=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help)
            display_help
            ;;
        -y|--yes)
            INTERACTIVE_MODE=false
            shift # past argument
            ;;
        *)
            # First non-option argument is PROJECT_DIR, second is MODEL_NAME
            if [ -z "$POS_ARG1_SET" ]; then
                PROJECT_DIR="$1"
                POS_ARG1_SET=true
            elif [ -z "$POS_ARG2_SET" ]; then
                MODEL_NAME="$1"
                POS_ARG2_SET=true
            else
                echo "ERROR: Too many arguments. Use -h or --help for usage." >&2
                exit 1
            fi
            shift # past argument
            ;;
    esac
done

# Expand tilde for project directory
PROJECT_DIR=$(eval echo "$PROJECT_DIR")

echo "--- Configuration Summary ---"
echo "Project Directory: $PROJECT_DIR"
echo "LLM Model: $MODEL_NAME"
echo "Interactive Mode: $INTERACTIVE_MODE"
echo ""

# --- User Confirmation ---
if [ "$INTERACTIVE_MODE" = true ]; then
    read -p "Press Enter to begin the setup, or Ctrl+C to cancel..."
else
    echo "Non-interactive mode enabled. Proceeding with setup..."
fi
echo ""

# --- Step 1: Prepare Project Directory ---
echo "--- Step 1: Prepare Project Directory ---"
if [ -z "$PROJECT_DIR" ]; then
    echo "ERROR: Project directory not set." >&2
    exit 1
fi
echo "Ensuring project directory '$PROJECT_DIR' exists..."
mkdir -p "$PROJECT_DIR"
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to create project directory '$PROJECT_DIR'." >&2
    exit 1
fi
cd "$PROJECT_DIR"
echo "Working directory: $(pwd)"
echo "Project directory prepared successfully."
echo ""

# --- Step 2: Install Ollama ---
echo "--- Step 2: Install Ollama ---"
echo "This command will download and run the Ollama installation script."
echo "The Ollama script may prompt for your sudo password."
if [ "$INTERACTIVE_MODE" = true ]; then
    # Adding a specific prompt here before a potentially big download and execution
    read -p "Press Enter to download and install Ollama, or Ctrl+C to cancel..."
else
    echo "Proceeding with Ollama installation..."
fi

curl -fsSL https://ollama.com/install.sh | sh
if [ $? -ne 0 ]; then
    echo ""
    echo "ERROR: Failed to install Ollama. Please check your internet connection or curl/Ollama script output." >&2
    echo "This script will now exit." >&2
    exit 2 # Specific exit code for Ollama installation failure
else
    echo "Ollama installed successfully."
fi
echo ""

# --- Step 3: Verify Ollama Service Status ---
echo "--- Step 3: Verify Ollama Service Status ---"
echo "Checking if Ollama service is running..."
# Attempt to start the service if it's not active.
# The 'ollama' installer should set up the systemd service.
if ! systemctl is-active --quiet ollama; then
    echo "Ollama service is not active. Attempting to start with sudo..."
    sudo systemctl start ollama
    # Wait a moment for the service to start
    sleep 3
fi

# Check status again
if ! systemctl is-active --quiet ollama; then
    echo ""
    echo "ERROR: Ollama service failed to start or is not active." >&2
    echo "Please check systemctl logs for 'ollama' (e.g., 'journalctl -u ollama')." >&2
    echo "This script will now exit." >&2
    exit 3 # Specific exit code for service failure
else
    echo "Ollama service is active and running."
fi
echo ""

# --- Step 4: Pull LLM Model ---
echo "--- Step 4: Pull LLM Model (\$MODEL_NAME) ---"
echo "Downloading the '$MODEL_NAME' model. This may take some time depending on your internet speed and requires sufficient disk space."
echo "If this step fails, you can try 'ollama pull $MODEL_NAME' manually later."

if [ "$INTERACTIVE_MODE" = true ]; then
    read -p "Press Enter to download the '$MODEL_NAME' model, or Ctrl+C to skip this step..."
else
    echo "Proceeding with '$MODEL_NAME' model download..."
fi

ollama pull "$MODEL_NAME"
if [ $? -ne 0 ]; then
    echo ""
    echo "WARNING: Failed to pull '$MODEL_NAME' model. Ollama is installed, but the model may need to be pulled manually." >&2
    echo "You can try 'ollama pull $MODEL_NAME' in your terminal later." >&2
    # Do not exit here, as Ollama itself is installed. This is a non-critical failure.
else
    echo "LLM model '$MODEL_NAME' was pulled successfully or was already present."
fi
echo ""

# --- Final Summary ---
echo "========================================================="
echo "        PSI PWA Linux Ollama & Core AI Setup Complete!"
echo "========================================================="
echo ""
echo "Ollama has been installed."
echo "Project directory is at: $PROJECT_DIR"

# Check if the model was attempted and provide appropriate message
if ollama list | grep -q "$MODEL_NAME"; then
    echo "LLM Model '$MODEL_NAME' is downloaded and available."
    echo "You can chat with the model directly via: ollama run $MODEL_NAME"
else
    # This case covers if the download was skipped or failed
    echo "LLM Model '$MODEL_NAME' was not successfully downloaded or was skipped."
    echo "If you intended to download it, you can try manually: ollama pull $MODEL_NAME"
fi

echo ""
echo "To verify Ollama service status: systemctl status ollama"
echo "To list downloaded models: ollama list"
echo ""

if [ "$INTERACTIVE_MODE" = true ]; then
    read -p "Press Enter to finish and exit script..."
else
    echo "Script finished in non-interactive mode."
fi

exit 0
