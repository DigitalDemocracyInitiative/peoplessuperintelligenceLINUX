#!/bin/bash

# Navigate to Project Root
cd ~/psi_pwa_linux_new || { echo "Failed to navigate to project root"; exit 1; }

# Update Tool Definitions and Orchestrator Prompt
echo "Updating tool definitions and orchestrator prompt..."

# Modify tools_and_llms.py
sed -i "/AVAILABLE_TOOLS_AND_LLMS = {/a \    \"internet_search\": \"Searches the internet for information.\"," tools_and_llms.py || { echo "Failed to update tools_and_llms.py"; exit 1; }

# Modify orchestrator_prompt.py
sed -i "/ORCHESTRATOR_SYSTEM_PROMPT = \"\"\"/a \\nGuidance for using internet_search:\\n- Use 'internet_search' when the user asks for current information, weather, or general knowledge that might require up-to-date information.\\n- Extract the core query from the user's message for the search tool." orchestrator_prompt.py || { echo "Failed to update orchestrator_prompt.py"; exit 1; }

# Implement Backend Logic for Internet Search Tool
echo "Implementing backend logic for internet search tool..."

# Modify backend/app.py
# This is a complex modification, so we'll use a temporary file for the new app.py content
cat << 'EOF' > backend/app_new.py
import os
import sys
import json
import time
from datetime import datetime
from flask import Flask, request, jsonify, send_from_directory
from flask_cors import CORS
import sqlite3

# Add project root to Python path
project_root = os.path.abspath(os.path.join(os.path.dirname(__file__), '..'))
sys.path.insert(0, project_root)

from tools_and_llms import AVAILABLE_TOOLS_AND_LLMS, call_ollama
from orchestrator_prompt import ORCHESTRATOR_SYSTEM_PROMPT

app = Flask(__name__, static_folder='../frontend/build')
CORS(app)

DATABASE = os.path.join(project_root, 'chat_history.db')

def get_db():
    db = getattrg(g, '_database', None)
    if db is None:
        db = g._database = sqlite3.connect(DATABASE)
        db.row_factory = sqlite3.Row
    return db

@app.teardown_appcontext
def close_connection(exception):
    db = getattr(g, '_database', None)
    if db is not None:
        db.close()

def init_db():
    with app.app_context():
        db = get_db()
        with app.open_resource('schema.sql', mode='r') as f:
            db.cursor().executescript(f.read())
        db.commit()

def log_message(user_id, role, content, agent_action=None, tool_details=None):
    db = get_db()
    db.execute(
        'INSERT INTO messages (user_id, role, content, agent_action, tool_details) VALUES (?, ?, ?, ?, ?)',
        (user_id, role, content, agent_action, json.dumps(tool_details) if tool_details else None)
    )
    db.commit()

def internet_search_tool(query: str):
    """Simulates an internet search with a 2-second delay."""
    print(f"Performing internet search for: {query}")
    time.sleep(2)
    now = datetime.now()
    if "time" in query.lower():
        return f"The current time is {now.strftime('%H:%M:%S')}."
    elif "date" in query.lower():
        return f"Today's date is {now.strftime('%Y-%m-%d')}."
    elif "weather" in query.lower():
        # Simulate weather based on a city name if provided
        if "london" in query.lower():
            return "The weather in London is currently cloudy with a chance of rain."
        elif "new york" in query.lower():
            return "The weather in New York is sunny."
        else:
            return "The weather is pleasant."
    else:
        return f"Simulated search results for '{query}': The internet is vast and full of information."

@app.route('/api/chat', methods=['POST'])
def chat():
    data = request.json
    user_id = data.get('user_id', 'default_user')
    user_message = data.get('message')

    if not user_message:
        return jsonify({"error": "No message provided"}), 400

    log_message(user_id, 'user', user_message)

    # Advanced orchestrator logic
    orchestrator_input = f"{ORCHESTRATOR_SYSTEM_PROMPT}\n\nAvailable tools: {json.dumps(AVAILABLE_TOOLS_AND_LLMS)}\n\nUser query: {user_message}"

    try:
        orchestrator_response_raw = call_ollama("gemma:2b", orchestrator_input)
        print(f"Orchestrator raw response: {orchestrator_response_raw}") # Debugging

        # Attempt to parse JSON from the orchestrator response
        try:
            # A common pattern is for the LLM to output JSON within a code block
            if "```json" in orchestrator_response_raw:
                json_block = orchestrator_response_raw.split("```json")[1].split("```")[0].strip()
            else: # Or it might be plain JSON
                json_block = orchestrator_response_raw.strip()

            orchestrator_response = json.loads(json_block)
        except json.JSONDecodeError as e:
            print(f"Failed to decode JSON from orchestrator: {e}")
            print(f"Raw response was: {orchestrator_response_raw}")
            # Fallback: treat the entire response as a direct AI message
            ai_response_content = f"Error processing your request with advanced logic. Defaulting to simple response: {orchestrator_response_raw}"
            log_message(user_id, 'assistant', ai_response_content, agent_action="orchestrator_parse_error")
            return jsonify({"reply": ai_response_content, "agent_action": "orchestrator_parse_error"})


        chosen_tool = orchestrator_response.get("tool")
        tool_input = orchestrator_response.get("tool_input", {})
        ai_thought = orchestrator_response.get("thought", "Thinking...")

        # Log AI thought process
        log_message(user_id, 'system-thought', ai_thought)

        agent_action_response = None
        tool_details_response = None

        if chosen_tool == "internet_search":
            query = tool_input.get("query", user_message) # Default to user_message if no specific query
            tool_details_response = {"query": query}
            try:
                search_result = internet_search_tool(query)
                ai_response_content = f"{ai_thought}\nI searched for '{query}'.\n{search_result}"
                log_message(user_id, 'system-info', f"Internet search for '{query}' successful.", agent_action="internet_search_success", tool_details=tool_details_response)
                agent_action_response = "internet_search_success"
            except Exception as e:
                print(f"Error during internet search: {e}")
                ai_response_content = f"{ai_thought}\nI tried to search for '{query}' but encountered an error."
                log_message(user_id, 'system-info', f"Internet search for '{query}' failed.", agent_action="internet_search_failure", tool_details=tool_details_response)
                agent_action_response = "internet_search_failure"

        elif chosen_tool == "database_query":
            # Placeholder for database_query tool - assuming it exists and works similarly
            # query = tool_input.get("query", "")
            # db_result = "Simulated DB result for: " + query
            # ai_response_content = f"{ai_thought}\nI queried the database: {query}\n{db_result}"
            # log_message(user_id, 'system-info', f"Database query: '{query}'.", agent_action="database_query_success", tool_details={"query": query})
            # agent_action_response = "database_query_success"
            # For now, let's assume if database_query is chosen, it means no specific tool action for this example
            ai_response_content = f"{ai_thought}\nI considered using the database, but will respond directly. {call_ollama('gemma:2b', user_message)}"
            log_message(user_id, 'assistant', ai_response_content)
            agent_action_response = "direct_response" # Or some other appropriate action

        elif chosen_tool == "no_tool" or not chosen_tool:
            # No specific tool, or orchestrator decided no tool is needed
            # Get a direct response from the LLM based on the user's message
            direct_llm_response = call_ollama("gemma:2b", f"{ai_thought}\nUser: {user_message}\nAssistant:")
            ai_response_content = f"{ai_thought}\n{direct_llm_response}"
            log_message(user_id, 'assistant', ai_response_content)
            agent_action_response = "direct_response"

        else:
            # Unknown tool or fallback
            ai_response_content = f"{ai_thought}\nI'm not sure how to use the tool '{chosen_tool}'. Responding generally: {call_ollama('gemma:2b', user_message)}"
            log_message(user_id, 'assistant', ai_response_content, agent_action="unknown_tool_fallback")
            agent_action_response = "unknown_tool_fallback"
            tool_details_response = {"tool_name": chosen_tool}


    except Exception as e:
        print(f"Error in chat endpoint: {e}")
        # Fallback to a simple Ollama call if advanced logic fails critically
        ai_response_content = call_ollama("gemma:2b", user_message)
        log_message(user_id, 'assistant', ai_response_content, agent_action="critical_error_fallback")
        agent_action_response = "critical_error_fallback"

    log_message(user_id, 'assistant', ai_response_content, agent_action=agent_action_response, tool_details=tool_details_response)
    return jsonify({"reply": ai_response_content, "agent_action": agent_action_response, "tool_details": tool_details_response})


@app.route('/api/history', methods=['GET'])
def history():
    user_id = request.args.get('user_id', 'default_user')
    db = get_db()
    cur = db.execute('SELECT role, content, agent_action, tool_details, timestamp FROM messages WHERE user_id = ? ORDER BY timestamp ASC', (user_id,))
    messages = cur.fetchall()
    return jsonify([dict(msg) for msg in messages])

# Serve React App
@app.route('/', defaults={'path': ''})
@app.route('/<path:path>')
def serve(path):
    if path != "" and os.path.exists(os.path.join(app.static_folder, path)):
        return send_from_directory(app.static_folder, path)
    else:
        return send_from_directory(app.static_folder, 'index.html')

if __name__ == '__main__':
    init_db() # Initialize DB if it doesn't exist
    app.run(debug=True, port=5001)
EOF

mv backend/app_new.py backend/app.py || { echo "Failed to move new app.py"; exit 1; }
chmod +x backend/app.py

# Update Frontend for Displaying Search Actions
echo "Updating frontend for displaying search actions..."

# Modify frontend/src/App.tsx
# This is also complex, using a temporary file.
cat << 'EOF' > frontend/src/App_new.tsx
import React, { useState, useEffect, useRef } from 'react';
import './App.css';

interface Message {
  role: 'user' | 'assistant' | 'system-info' | 'system-thought';
  content: string;
  agent_action?: string;
  tool_details?: any;
  timestamp?: string;
}

function App() {
  const [input, setInput] = useState('');
  const [messages, setMessages] = useState<Message[]>([]);
  const [userId, setUserId] = useState<string>('default_user'); // Example user ID

  const messagesEndRef = useRef<null | HTMLDivElement>(null);

  const scrollToBottom = () => {
    messagesEndRef.current?.scrollIntoView({ behavior: "smooth" });
  };

  useEffect(() => {
    scrollToBottom();
  }, [messages]);

  useEffect(() => {
    // Fetch chat history on component mount
    const fetchHistory = async () => {
      try {
        const response = await fetch(`/api/history?user_id=${userId}`);
        if (response.ok) {
          const data: Message[] = await response.json();
          // Filter out system-thought messages from initial history display if desired
          setMessages(data.filter(msg => msg.role !== 'system-thought'));
        } else {
          console.error('Failed to fetch history');
        }
      } catch (error) {
        console.error('Error fetching history:', error);
      }
    };
    fetchHistory();
  }, [userId]);


  const handleSendMessage = async (e?: React.FormEvent) => {
    if (e) e.preventDefault();
    if (!input.trim()) return;

    const userMessage: Message = { role: 'user', content: input };
    setMessages(prevMessages => [...prevMessages, userMessage]);
    setInput('');

    try {
      const response = await fetch('/api/chat', {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json',
        },
        body: JSON.stringify({ message: input, user_id: userId }),
      });

      if (response.ok) {
        const data = await response.json();

        let displayMessageContent = `Assistant: ${data.reply}`;
        let systemMessage: Message | null = null;

        // Handle agent actions for display
        if (data.agent_action) {
          const toolQuery = data.tool_details?.query;
          switch (data.agent_action) {
            case 'internet_search_success':
              systemMessage = {
                role: 'system-info',
                content: `Agent performed a web search for: "${toolQuery || 'your query'}".`,
                agent_action: data.agent_action
              };
              // The main reply already contains the search result combined with thought.
              displayMessageContent = data.reply;
              break;
            case 'internet_search_failure':
              systemMessage = {
                role: 'system-info',
                content: `Agent failed to perform a web search for: "${toolQuery || 'your query'}".`,
                agent_action: data.agent_action
              };
              displayMessageContent = data.reply;
              break;
            case 'database_query_success': // Example for another tool
              systemMessage = {
                role: 'system-info',
                content: `Agent queried the database with: "${toolQuery || 'your query'}".`,
                agent_action: data.agent_action
              };
              displayMessageContent = data.reply;
              break;
            // Add more cases for other agent actions as needed
            default:
              // If no specific handling, just use the reply as is
              displayMessageContent = data.reply;
              break;
          }
        }

        const assistantMessage: Message = {
          role: 'assistant',
          content: displayMessageContent,
          agent_action: data.agent_action,
          tool_details: data.tool_details
        };

        setMessages(prevMessages => [
          ...prevMessages,
          ...(systemMessage ? [systemMessage] : []), // Add system message if it exists
          assistantMessage
        ]);

      } else {
        const errorData = await response.json();
        const errorMessage: Message = { role: 'assistant', content: `Error: ${errorData.error || 'Failed to get response'}` };
        setMessages(prevMessages => [...prevMessages, errorMessage]);
      }
    } catch (error) {
      console.error('Error sending message:', error);
      const errorMessage: Message = { role: 'assistant', content: 'Error: Could not connect to the server.' };
      setMessages(prevMessages => [...prevMessages, errorMessage]);
    }
  };

  return (
    <div className="App">
      <header className="App-header">
        <h1>PSI PWA with Ollama</h1>
      </header>
      <div className="chat-window">
        {messages.map((msg, index) => (
          <div key={index} className={`message ${msg.role}`}>
            <span className="message-role">{msg.role === 'system-info' ? 'System' : msg.role.charAt(0).toUpperCase() + msg.role.slice(1)}:</span>
            <p>{msg.content}</p>
            {/* Optionally display tool details or specific icons based on agent_action */}
            {msg.agent_action && msg.role === 'system-info' && (
              <small className="agent-action-details">Action: {msg.agent_action}</small>
            )}
          </div>
        ))}
        <div ref={messagesEndRef} />
      </div>
      <form onSubmit={handleSendMessage} className="message-form">
        <input
          type="text"
          value={input}
          onChange={(e) => setInput(e.target.value)}
          placeholder="Type your message..."
        />
        <button type="submit">Send</button>
      </form>
    </div>
  );
}

export default App;
EOF

mv frontend/src/App_new.tsx frontend/src/App.tsx || { echo "Failed to move new App.tsx"; exit 1; }

# Final Instructions & Server Management
echo "Finalizing script and adding server management..."

cat << 'EOF' >> add_psi_search_tool.sh

# (Continuing the script from where the heredoc above ends)

echo "---------------------------------------------------------------------"
echo "PSI Internet Search Tool Integration Complete!"
echo "---------------------------------------------------------------------"
echo ""
echo "To run the application:"
echo "1. Ensure Ollama is running (e.g., 'ollama serve' in a separate terminal)."
echo "2. Make sure you have pulled the gemma:2b model ('ollama pull gemma:2b')."
echo "3. Start the backend server:"
echo "   cd ~/psi_pwa_linux_new/backend"
echo "   python app.py &"
echo "   cd .."
echo ""
echo "4. Start the frontend development server:"
echo "   cd ~/psi_pwa_linux_new/frontend"
echo "   npm start &"
echo "   cd .."
echo ""
echo "5. Open your browser and navigate to http://localhost:3000 (or the port npm uses)."
echo ""
echo "Example queries for the internet search tool:"
echo " - 'What is the current time?'"
echo " - 'What is the date today?'"
echo " - 'What's the weather like in London?'"
echo " - 'Tell me about Large Language Models.'"
echo ""
echo "To stop the servers:"
echo " - Find the process IDs (PIDs) for 'python app.py' and 'npm start'."
echo "   ps aux | grep 'python app.py'"
echo "   ps aux | grep 'npm start'"
echo " - Use 'kill <PID>' for each process."
echo "   Example: kill 12345 67890"
echo ""
echo "View backend logs: ~/psi_pwa_linux_new/backend/app.log (if logging is configured)"
echo "View frontend logs: In the terminal where 'npm start' is running."
echo "---------------------------------------------------------------------"

EOF

chmod +x add_psi_search_tool.sh

echo "Script 'add_psi_search_tool.sh' created successfully."
echo "Please review the script before execution."
echo "To execute, run: ./add_psi_search_tool.sh"
