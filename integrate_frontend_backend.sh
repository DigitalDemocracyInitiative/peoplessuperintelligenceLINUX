#!/bin/bash
set -e # Exit immediately if a command exits with a non-zero status.
set -o pipefail # Fail if any command in a pipeline fails.

echo "========================================================="
echo "        PSI PWA Linux Frontend-Backend Integration Script"
echo "========================================================="
echo ""
echo "This script will integrate the Flask backend and React frontend."
echo "It assumes previous setup scripts have been run and directories exist:"
echo "  - ~/psi_pwa_linux_new/backend"
echo "  - ~/psi_pwa_linux_new/frontend"
echo ""
read -p "Press Enter to begin, or Ctrl+C to cancel..."

PROJECT_ROOT="$HOME/psi_pwa_linux_new"
BACKEND_DIR="$PROJECT_ROOT/backend"
FRONTEND_DIR="$PROJECT_ROOT/frontend"

echo ""
echo "--- Step 1: Navigate to Project Root Directory ---"
cd "$PROJECT_ROOT"
echo "Working directory: $(pwd)"
echo ""

echo "--- Step 2: Backend Integration & API Endpoint for LLM ---"
echo "Navigating to backend directory: $BACKEND_DIR"
cd "$BACKEND_DIR"

echo "Activating Python virtual environment..."
source venv/bin/activate
if [ $? -ne 0 ]; then
echo "ERROR: Failed to activate backend virtual environment. Ensure 'venv' exists and is valid."
exit 1
fi
echo "Virtual environment activated."
echo "Modifying app.py to add /api/chat endpoint..."
# Use sed to add the new route before the 'if __name__ == "__main__":' block
# This is a bit tricky with sed, so we'll use a temporary file approach for clarity.
# First, remove existing __main__ block if any to ensure clean addition
sed -i '/if __name__ == "__main__":/,${/app.run/d; /^[[:space:]]*$/d; /^$/d}' app.py

# Add the new content, including imports and the chat route
cat << 'EOF_BACKEND_APP_PY' > app_temp.py
import requests
import json
from flask import Flask, request, jsonify
from flask_cors import CORS # Import CORS for cross-origin requests

app = Flask(__name__)
CORS(app) # Enable CORS for all routes

@app.route('/')
def hello_world():
    return 'Hello from PSI Backend!'

@app.route('/api/chat', methods=['POST'])
def chat():
    data = request.get_json()
    user_message = data.get('message')

    if not user_message:
        return jsonify({"error": "No message provided"}), 400

    ollama_url = "http://localhost:11434/api/generate"
    try:
        ollama_payload = {
            "model": "mistral", # Ensure mistral is pulled as per ollama_ai_setup.sh
            "prompt": user_message,
            "stream": False
        }
        response = requests.post(ollama_url, json=ollama_payload, timeout=60) # Added timeout
        response.raise_for_status()  # Raise an exception for HTTP errors (4xx or 5xx)
        ollama_response_json = response.json()

        # The actual response content from Ollama is typically in a "response" key
        actual_response_content = ollama_response_json.get("response")

        if actual_response_content is None:
            # Log or handle the case where "response" key is missing or None
            return jsonify({"error": "Received an empty or invalid response from Ollama service"}), 500

        return jsonify({"response": actual_response_content})

    except requests.exceptions.RequestException as e:
        # Handle network errors (e.g., connection refused, timeout)
        return jsonify({"error": "Error connecting to Ollama service", "details": str(e)}), 503
    except Exception as e:
        # Handle other potential errors (e.g., JSON parsing issues, unexpected issues)
        return jsonify({"error": "An unexpected error occurred", "details": str(e)}), 500

if __name__ == "__main__":
    app.run(debug=True, host='0.0.0.0', port=5001)
EOF_BACKEND_APP_PY

echo "Appending temporary content to app.py..."
cat app_temp.py >> app.py
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to append app_temp.py to app.py."
    rm app_temp.py # Clean up temp file even if append failed
    exit 1
fi

echo "Removing temporary file app_temp.py..."
rm app_temp.py
if [ $? -ne 0 ]; then
    echo "WARNING: Failed to remove app_temp.py. Manual cleanup may be required."
    # Not exiting here as the main goal (appending) was successful
fi

echo "Backend /api/chat endpoint setup complete."
echo ""

echo "Deactivating Python virtual environment..."
deactivate
echo "Python virtual environment deactivated."
echo ""

echo "--- Step 3: Frontend Integration & Build ---"
echo "Navigating to frontend directory: $FRONTEND_DIR"
cd "$FRONTEND_DIR"
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to navigate to frontend directory $FRONTEND_DIR."
    exit 1
fi
echo "Working directory: $(pwd)"
echo ""

echo "Updating API endpoint in React app (src/App.js)..."
# Replace http://localhost:5000/api/chat with http://localhost:5001/api/chat
# Using a temporary file for sed to avoid issues with in-place editing in some environments
sed 's|http://localhost:5000/api/chat|http://localhost:5001/api/chat|g' src/App.js > src/App.js.tmp
if [ $? -ne 0 ]; then
    echo "ERROR: sed command failed to process src/App.js."
    rm -f src/App.js.tmp # Clean up temp file
    exit 1
fi
mv src/App.js.tmp src/App.js
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to replace API endpoint in src/App.js using mv."
    exit 1
fi
echo "API endpoint updated in src/App.js."
echo ""

echo "Installing frontend dependencies (npm install)..."
npm install
if [ $? -ne 0 ]; then
    echo "ERROR: npm install failed in $FRONTEND_DIR."
    exit 1
fi
echo "Frontend dependencies installed."
echo ""

echo "Building the React application (npm run build)..."
npm run build
if [ $? -ne 0 ]; then
    echo "ERROR: npm run build failed in $FRONTEND_DIR."
    exit 1
fi
echo "Frontend build complete. Static files are in the build/ directory."
echo ""

echo "--- Step 4: Serve Frontend & Start Backend ---"
echo "Serving frontend using 'serve' on port 3000 in the background..."
serve -s build -l 3000 > /dev/null 2>&1 &
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to start 'serve' for the frontend."
    echo "Ensure 'serve' is installed globally (npm install -g serve)."
    exit 1
fi
echo "Frontend should be accessible at http://localhost:3000"
echo ""

echo "Navigating back to backend directory: $BACKEND_DIR"
cd "$BACKEND_DIR"
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to navigate to backend directory $BACKEND_DIR."
    exit 1
fi
echo "Working directory: $(pwd)"
echo ""

echo "Starting Flask backend server..."
echo "Activating Python virtual environment for backend..."
source venv/bin/activate
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to activate backend Python virtual environment."
    exit 1
fi
echo "Virtual environment activated."
echo "Backend (and API) will be accessible at http://localhost:5001"
python app.py
if [ $? -ne 0 ]; then
    echo "ERROR: Failed to start Flask backend server (python app.py)."
    # Attempt to deactivate venv even if Flask fails to start, for cleanup
    deactivate
    exit 1
fi
# Deactivation will happen here if python app.py is stopped (e.g. Ctrl+C)
# Or if it exits due to an error not caught by the script's set -e
echo ""
echo "Deactivating Python virtual environment (after Flask server stops)..."
deactivate # This will run if python app.py exits cleanly or is interrupted.
echo ""

echo "========================================================="
echo "          Integration Script Finished"
echo "========================================================="
echo "To stop the servers, you'll need to manually find and kill the processes."
echo " - Frontend (serve): Find process on port 3000 (e.g., 'sudo lsof -i :3000' then 'kill PID')"
echo " - Backend (Flask): Press Ctrl+C in the terminal where 'python app.py' is running (if it was the last command)."
echo "   If 'python app.py' was backgrounded or managed differently, find its PID."
echo ""
