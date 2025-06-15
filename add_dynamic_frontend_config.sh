#!/bin/bash
set -e

# Navigate to the project root
cd ~/psi_pwa_linux_new || { echo "Failed to navigate to project root"; exit 1; }

# === Backend Modifications ===

# Target file for backend modifications
BACKEND_APP_PY="backend/app.py"

# Ensure jsonify is imported
# Check if jsonify is already in the import statement
if ! grep -q "from flask import Flask, request, jsonify, session" "$BACKEND_APP_PY" && grep -q "from flask import Flask, request, session" "$BACKEND_APP_PY"; then
  echo "Adding jsonify to Flask imports in $BACKEND_APP_PY"
  sed -i "s/from flask import Flask, request, session/from flask import Flask, request, jsonify, session/" "$BACKEND_APP_PY"
elif ! grep -q "jsonify" "$BACKEND_APP_PY"; then
  # If a simple replacement wasn't enough, try a more generic approach to add jsonify
  echo "Attempting to add jsonify to existing Flask import line (more generic) in $BACKEND_APP_PY"
  sed -i "/^from flask import .*Flask/ s/$/, jsonify/" "$BACKEND_APP_PY"
  if ! grep -q "jsonify" "$BACKEND_APP_PY"; then
    echo "Failed to add jsonify automatically. Please check $BACKEND_APP_PY"
  fi
fi

# Add AVAILABLE_MODELS
AVAILABLE_MODELS_LINE='AVAILABLE_MODELS = ["mistral", "deepseek-coder"]'
sed -i "/CORS(app, supports_credentials=True)/a $AVAILABLE_MODELS_LINE" "$BACKEND_APP_PY"
echo "Inserted AVAILABLE_MODELS into $BACKEND_APP_PY"

# Define the new /api/config endpoint
API_CONFIG_ROUTE_PY_ESCAPED=$(cat << 'EOF' | sed -e 's/[\/&]/\\&/g' -e 's/$/\\n/' | tr -d '\n'
@app.route('/api/config', methods=['GET'])
def get_app_config():
    config_data = {
        "appTitle": "PSI AI Agent Workplace",
        "defaultWelcomeMessage": "Hello! How can I assist you today?",
        "availableModels": AVAILABLE_MODELS,
        "availableTools": [
            {"name": schema['function']['name'], "description": schema['function']['description']}
            for schema in AVAILABLE_TOOL_SCHEMAS
        ] if AVAILABLE_TOOL_SCHEMAS else [],
        "uiSections": {"chat": True, "tasks": True, "profiles": True}
    }
    return jsonify(config_data)
EOF
)
sed -i "/if __name__ == '__main__':/i $API_CONFIG_ROUTE_PY_ESCAPED" "$BACKEND_APP_PY"
echo "Inserted /api/config route into $BACKEND_APP_PY"

echo "Backend modifications complete."

# === Frontend Modifications ===
echo "Starting frontend modifications..."
FRONTEND_APP_TSX="frontend/src/App.tsx"

# 1. Define UiConfig interface
# Insert after the last import statement: import './App.css';
UI_CONFIG_INTERFACE_TS=$(cat << 'EOF'
interface UiConfig {
  appTitle: string;
  defaultWelcomeMessage: string;
  availableModels: string[];
  availableTools: Array<{ name: string; description: string }>;
  uiSections: {
    chat: boolean;
    tasks: boolean;
    profiles: boolean;
  };
}
EOF
)
# Escape for sed
UI_CONFIG_INTERFACE_TS_ESCAPED=$(echo "$UI_CONFIG_INTERFACE_TS" | sed -e 's/[\/&]/\\&/g' -e 's/$/\\n/' | tr -d '\n' | sed 's/\\n$//')
sed -i "/import '\.\/App.css';/a $UI_CONFIG_INTERFACE_TS_ESCAPED" "$FRONTEND_APP_TSX"
echo "Inserted UiConfig interface into $FRONTEND_APP_TSX"

# 2. Add state variables for UI Config
# Insert after 'const [messagesEndRef = useRef<HTMLDivElement>(null);'
UI_CONFIG_STATES_TS=$(cat << 'EOF'
  const [uiConfig, setUiConfig] = useState<UiConfig | null>(null);
  const [configLoading, setConfigLoading] = useState<boolean>(true);
  const [configError, setConfigError] = useState<string | null>(null);
EOF
)
UI_CONFIG_STATES_TS_ESCAPED=$(echo "$UI_CONFIG_STATES_TS" | sed -e 's/[\/&]/\\&/g' -e 's/$/\\n/' | tr -d '\n' | sed 's/\\n$//')
sed -i "/const messagesEndRef = useRef<HTMLDivElement>(null);/a $UI_CONFIG_STATES_TS_ESCAPED" "$FRONTEND_APP_TSX"
echo "Inserted UI Config state variables into $FRONTEND_APP_TSX"

# 3. Fetch configuration in useEffect
FETCH_CONFIG_USEEFFECT_TS=$(cat << 'EOF'

  useEffect(() => {
    const fetchAppConfig = async () => {
      try {
        const response = await axios.get('http://localhost:5000/api/config');
        setUiConfig(response.data);
      } catch (error) {
        console.error('Error fetching app configuration:', error);
        setConfigError('Failed to load application configuration. Some features may be unavailable or use default settings.');
        setUiConfig({ // Basic fallback
          appTitle: "PSI AI Agent (Fallback)",
          defaultWelcomeMessage: "Welcome! The application configuration could not be loaded.",
          availableModels: [],
          availableTools: [],
          uiSections: { chat: true, tasks: false, profiles: true }
        });
      } finally {
        setConfigLoading(false);
      }
    };
    fetchAppConfig();
  }, []);
EOF
)
FETCH_CONFIG_USEEFFECT_TS_ESCAPED=$(echo "$FETCH_CONFIG_USEEFFECT_TS" | sed -e 's/[\/&]/\\&/g' -e 's/$/\\n/' | tr -d '\n' | sed 's/\\n$//')
sed -i "/useEffect(() => {.*const loadData = async () => {/i $FETCH_CONFIG_USEEFFECT_TS_ESCAPED" "$FRONTEND_APP_TSX"
echo "Inserted useEffect for fetching app configuration into $FRONTEND_APP_TSX"


# 4. Display Loading/Error State for Config
# Insert before 'return ('
CONFIG_LOADING_STATE_TS=$(cat << 'EOF'
  if (configLoading) {
    return <div className="loading-container"><h1>Loading configuration...</h1></div>;
  }

  // if (!uiConfig && configError) { // Fallback in useEffect handles !uiConfig
  //   return <div className="error-container"><h1>Error</h1><p>{configError}</p></div>;
  // }
EOF
)
CONFIG_LOADING_STATE_TS_ESCAPED=$(echo "$CONFIG_LOADING_STATE_TS" | sed -e 's/[\/&]/\\&/g' -e 's/$/\\n/' | tr -d '\n' | sed 's/\\n$//')
sed -i "/return (/{i $CONFIG_LOADING_STATE_TS_ESCAPED" "$FRONTEND_APP_TSX"
echo "Inserted config loading/error display into $FRONTEND_APP_TSX"

# 5. Dynamic App Title
sed -i "s/<h1>PSI AI Agent Chat<\\/h1>/<h1>{uiConfig?.appTitle || 'PSI AI Agent Chat'}<\\/h1>/g" "$FRONTEND_APP_TSX"
echo "Made app title dynamic in $FRONTEND_APP_TSX"

# 6. New useEffect for Welcome Message
WELCOME_MSG_USEEFFECT_TS=$(cat << 'EOF'

  useEffect(() => {
    if (uiConfig && messages.length === 0 && !loading && !configLoading) {
      const welcomeMsg: Message = { text: uiConfig.defaultWelcomeMessage, sender: 'system-info', timestamp: new Date().toISOString() };
      if (!messages.find(m => m.text === welcomeMsg.text && m.sender === 'system-info')) {
        setMessages([welcomeMsg]);
      }
    }
  }, [uiConfig, messages, loading, configLoading]);
EOF
)
WELCOME_MSG_USEEFFECT_TS_ESCAPED=$(echo "$WELCOME_MSG_USEEFFECT_TS" | sed -e 's/[\/&]/\\&/g' -e 's/$/\\n/' | tr -d '\n' | sed 's/\\n$//')
sed -i "/useEffect(() => {.*scrollToBottom();.*}, \[messages\]);/a $WELCOME_MSG_USEEFFECT_TS_ESCAPED" "$FRONTEND_APP_TSX"
echo "Inserted useEffect for default welcome message into $FRONTEND_APP_TSX"

# 7.1 Conditional UI Rendering: Profiles Section
sed -i "s|<div className=\"profile-selector\">|{uiConfig?.uiSections.profiles && (<div className=\"profile-selector\">|" "$FRONTEND_APP_TSX"
sed -i "s|<\\/div>.*<\\/header>|</div>)}\n      </header>|" "$FRONTEND_APP_TSX"
echo "Made profile selector conditional in $FRONTEND_APP_TSX"

# 7.2 Conditional UI Rendering: Tasks Section
TASKS_SECTION_TS_ESCAPED=$(cat << 'EOF' | sed -e 's/[\/&]/\\&/g' -e 's/$/\\n/' | tr -d '\n' | sed 's/\\n$//'
      {uiConfig?.uiSections.tasks && <div className="tasks-section"><h2>Background Tasks</h2><p>Tasks functionality will be here.</p></div>}
EOF
)
sed -i "/<div className=\"chat-container\">/i $TASKS_SECTION_TS_ESCAPED" "$FRONTEND_APP_TSX"
echo "Inserted conditional Tasks section into $FRONTEND_APP_TSX"

# 7.3 Conditional UI Rendering: Chat Section
sed -i "s|<div className=\"chat-container\">|{uiConfig?.uiSections.chat && (<div className=\"chat-container\">|" "$FRONTEND_APP_TSX"
# Use corrected sed command for closing JSX tag, robust to whitespace
sed -i '/<\/form>/{N;s|<\/form>\n\s*<\/div>|<\/form>\n<\/div> )}|}' "$FRONTEND_APP_TSX"
echo "Made chat container conditional in $FRONTEND_APP_TSX"


# 8. Available Models Display
AVAILABLE_MODELS_TS_ESCAPED=$(cat << 'EOF' | sed -e 's/[\/&]/\\&/g' -e 's/$/\\n/' | tr -d '\n' | sed 's/\\n$//'

        {uiConfig?.availableModels && uiConfig.availableModels.length > 0 && (<div className="available-models">Available Models: {uiConfig.availableModels.join(', ')}</div>)}
EOF
)
sed -i "/<\\/div>)}.*<\\/header>/a $AVAILABLE_MODELS_TS_ESCAPED" "$FRONTEND_APP_TSX"
echo "Inserted available models display into $FRONTEND_APP_TSX"


echo "Frontend modifications supposedly complete."
echo "Please review $FRONTEND_APP_TSX carefully."

echo "Script finished. Below are instructions for building, running, and verifying:"
# End of script (marker for instruction append)

cat << 'EOF_INSTRUCTIONS'

echo ""
echo "-------------------------------------------------------------------"
echo "PSI PWA Dynamic Configuration Script Completed"
echo "-------------------------------------------------------------------"
echo ""
echo "Next Steps:"
echo ""
echo "1. Review the changes:"
echo "   - backend/app.py (for the new /api/config endpoint)"
echo "   - frontend/src/App.tsx (for dynamic config fetching and usage)"
echo ""
echo "2. Ensure backend dependencies are up to date (if any were added, though this script doesn't add new ones):"
echo "   cd backend"
echo "   # source .venv/bin/activate  (or your venv activation command)"
echo "   # pip install -r requirements.txt "
echo "   cd .."
echo ""
echo "3. Build the frontend:"
echo "   cd frontend"
echo "   npm install"
echo "   npm run build"
echo "   cd .."
echo ""
echo "4. Run the backend:"
echo "   cd backend"
echo "   echo 'Starting backend server... (Press Ctrl+C to stop)'"
echo "   # Ensure your Python virtual environment is activated if you haven't already!"
echo "   # Example: source .venv/bin/activate"
echo "   python app.py"
echo "   # Keep this terminal open."
echo "   cd .."
echo ""
echo "5. In a new terminal, serve the frontend:"
echo "   cd frontend"
echo "   echo 'Starting frontend server... (Requires serve, install with: npm install -g serve)'"
echo "   serve -s build -l 3000"
echo "   # Keep this terminal open. Access the app at http://localhost:3000"
echo "   cd .."
echo ""
echo "6. Verification:"
echo "   - Open your browser to http://localhost:3000 (or the port serve uses)."
echo "   - Check if the application title is 'PSI AI Agent Workplace'."
echo "   - If the chat history is empty, you should see the welcome message: 'Hello! How can I assist you today?'."
echo "   - Verify that the 'Agent Profile' selector is visible (if uiSections.profiles is true, which it is by default)."
echo "   - Verify that a 'Background Tasks' section placeholder is visible (if uiSections.tasks is true, which it is by default)."
echo "   - Check for a display of 'Available Models' (e.g., 'Available Models: mistral, deepseek-coder')."
echo "   - Open your browser's developer tools, go to the Network tab, and check for a GET request to /api/config. Inspect its response."
echo ""
echo "If you encounter issues, check the terminal output for errors in both the backend and frontend."
echo "-------------------------------------------------------------------"
EOF_INSTRUCTIONS
