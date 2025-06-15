#!/bin/bash
set -e

echo ">>> Navigating to project root..."
cd ~/psi_pwa_linux_new || { echo "Failed to navigate to project root. Exiting."; exit 1; }

echo ">>> Creating agent_workspace directory..."
mkdir -p agent_workspace

echo ">>> Overwriting backend/app.py..."
cat <<'EOF_APP_PY' > backend/app.py
import os
import re # Import re for potential future use, even if not immediately used
from flask import Flask, request, jsonify
from flask_cors import CORS
import requests
import json # For handling potential json.JSONDecodeError
from flask_sqlalchemy import SQLAlchemy
from datetime import datetime

app = Flask(__name__)
agent_workspace_path = os.path.abspath("agent_workspace")
app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:///messages.db'
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False
db = SQLAlchemy(app)

# Define the Message model
class Message(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    sender = db.Column(db.String(50), nullable=False)  # 'user' or 'ai'
    text = db.Column(db.Text, nullable=False)
    timestamp = db.Column(db.DateTime, default=datetime.utcnow)
    agent_action = db.Column(db.String(100), nullable=True)  # Optional field for AI actions

    def to_dict(self):
        return {
            'id': self.id,
            'sender': self.sender,
            'text': self.text,
            'timestamp': self.timestamp.isoformat(),
            'agent_action': self.agent_action
        }

# Function to initialize the database
def init_db():
    with app.app_context():
        db.create_all()
    print("Database initialized!")

init_db() # Initialize the database

CORS(app) # Enable CORS for all routes

# Helper function to call Ollama
def call_ollama(model_name: str, prompt_text: str, conversation_history: list):
    ollama_url = "http://localhost:11434/api/generate"

    messages_for_ollama = [{"role": "system", "content": "You are PSI, a helpful AI agent."}]
    for msg in conversation_history:
        if msg.sender == 'user':
            messages_for_ollama.append({"role": "user", "content": msg.text})
        elif msg.sender == 'ai':
            messages_for_ollama.append({"role": "assistant", "content": msg.text})
    messages_for_ollama.append({"role": "user", "content": prompt_text})

    ollama_payload = {
        "model": model_name,
        "prompt": prompt_text, # Retained for compatibility, but messages is primary
        "messages": messages_for_ollama,
        "stream": False
    }
    try:
        response = requests.post(ollama_url, json=ollama_payload, timeout=120)
        response.raise_for_status()
        ollama_response = response.json()
        return ollama_response.get('response', 'No response from AI.')
    except requests.exceptions.Timeout:
        print(f"Error: Timeout while communicating with Ollama for model {model_name}.")
        # Reraise the exception to be handled by the route
        raise
    except requests.exceptions.ConnectionError:
        print(f"Error: Connection error while communicating with Ollama for model {model_name}.")
        raise
    except requests.exceptions.RequestException as e:
        print(f"Error communicating with Ollama for model {model_name}: {e}")
        raise
    except json.JSONDecodeError:
        print(f"Error decoding JSON from Ollama response for model {model_name}.")
        raise
    # Do not catch generic Exception here, let it propagate if it's not a request/JSON error


@app.route('/')
def hello_world():
    return 'Hello from PSI Backend!'

@app.route('/api/chat', methods=['POST'])
def chat():
    # Fetch last 5 messages for conversation history
    conversation_history = Message.query.order_by(Message.timestamp.desc()).limit(5).all()
    conversation_history.reverse() # Chronological order

    data = request.get_json()
    user_message = data.get('message', '').strip()

    if not user_message:
        return jsonify({"error": "Please provide a message."}), 400 # Not saved to DB

    user_message_lower = user_message.lower()
    user_agent_action = 'none' # Default agent action for user message

    # File operation command parsing
    # Initialize file_op_processed to False. If a file operation is handled, this will be set to True.
    file_op_processed = False
    agent_action = None # To store action type like 'file_read_success'
    response_data = None # To store response for file ops
    status_code = 200 # Default success code

    # Attempt to save user message first
    # The agent_action for the user message will be updated if it's a file op

    # Read commands
    if user_message_lower.startswith("read file ") or user_message_lower.startswith("show me content of "):
        file_op_processed = True
        user_agent_action = 'user_command_read_file'
        try:
            if user_message_lower.startswith("read file "):
                file_path = user_message.split(" ", 2)[2]
            else: # "show me content of "
                file_path = user_message.split(" ", 4)[4]

            result = read_file_tool(file_path)
            if result.startswith("Error:"):
                agent_action = "file_read_error"
                status_code = 400 # Or another appropriate error code
            else:
                agent_action = "file_read_success"
            response_data = result
        except IndexError:
            result = "Error: Malformed read command. Use 'read file <filename>' or 'show me content of <filename>'."
            agent_action = "file_read_error"
            response_data = result
            status_code = 400
        except Exception as e: # Catch any other unexpected errors during parsing/tool call
            result = f"Error: An unexpected error occurred processing read command. {str(e)}"
            agent_action = "file_read_error"
            response_data = result
            status_code = 500


    # Write commands
    elif user_message_lower.startswith("write to ") or user_message_lower.startswith("save this to "):
        file_op_processed = True
        user_agent_action = 'user_command_write_file'
        file_path = None
        content = None
        try:
            if user_message_lower.startswith("write to "): # "write to <filename> content <content>"
                # Split out "write to " part
                command_body = user_message.split(" ", 2)[2]
                if " content " in command_body:
                    filename_part, content_part = command_body.split(" content ", 1)
                    file_path = filename_part.strip()
                    content = content_part
                else:
                    result = "Error: Malformed write command. Use 'write to <filename> content <content>'."
                    agent_action = "file_write_error"
                    response_data = result
                    status_code = 400

            elif user_message_lower.startswith("save this to "): # "save this to <filename>: <content>"
                # Split out "save this to " part
                command_body = user_message.split(" ", 3)[3]
                if ": " in command_body:
                    filename_part, content_part = command_body.split(": ", 1)
                    file_path = filename_part.strip()
                    content = content_part
                else:
                    result = "Error: Malformed write command. Use 'save this to <filename>: <content>'."
                    agent_action = "file_write_error"
                    response_data = result
                    status_code = 400

            if file_path and content is not None: # Ensure parsing was successful before calling tool
                result = write_file_tool(file_path, content)
                if result.startswith("Error:"):
                    agent_action = "file_write_error"
                    status_code = 400 # Or another appropriate error code
                else:
                    agent_action = "file_write_success"
                response_data = result
            elif not response_data: # If response_data wasn't set by a parsing error message
                result = "Error: Could not parse filename or content for write operation."
                agent_action = "file_write_error"
                response_data = result
                status_code = 400

        except IndexError:
            result = "Error: Malformed write command structure."
            agent_action = "file_write_error"
            response_data = result
            status_code = 400
        except Exception as e: # Catch any other unexpected errors
            result = f"Error: An unexpected error occurred processing write command. {str(e)}"
            agent_action = "file_write_error"
            response_data = result
            status_code = 500

    # Save user message to DB (action updated if it was a file op)
    user_msg_db = Message(sender='user', text=user_message, agent_action=user_agent_action)
    db.session.add(user_msg_db)
    db.session.commit()

    if file_op_processed:
        # Save system message for file operation outcome
        system_msg_text = f"Agent action: {agent_action}. File: '{file_path if 'file_path' in locals() and file_path else 'N/A'}'. Result: {response_data}"
        if agent_action and response_data: # Ensure these are set
             system_msg_db = Message(sender='system-info', text=system_msg_text, agent_action=agent_action)
             db.session.add(system_msg_db)
             db.session.commit()
        return jsonify({"response": response_data, "agent_action": agent_action}), status_code

    # If not a file op, proceed with existing logic (document processing, LLM calls)
    # Simple intent detection (existing logic)
    if user_message.lower().startswith("process document:"):
        document_text = user_message.split(":", 1)[1].strip()
        if not document_text:
            # User message already saved, this is an error for the operation itself
            return jsonify({"error": "Document text is empty after 'process document:' command."}), 400

        tool_output = {"result": f"Document processed. First 50 chars: {document_text[:50]}..."}
        system_msg_db = Message(sender='system-info', text=f"Agent used document processing tool. Result: {tool_output['result']}", agent_action='tool_used_document_processing')
        db.session.add(system_msg_db)
        db.session.commit()
        return jsonify({"response": tool_output['result'], "agent_action": "document_processed"}), 200

    elif "code" in user_message.lower() or "deepseek-coder" in user_message.lower():
        model_to_use = "deepseek-coder"
        agent_action_label = "llm_deepseek"
    else:
        model_to_use = "mistral"
        agent_action_label = "llm_mistral"

    try:
        response_text = call_ollama(model_to_use, user_message, conversation_history)

        ai_msg_db = Message(sender='ai', text=response_text, agent_action=agent_action_label)
        db.session.add(ai_msg_db)
        db.session.commit()

        return jsonify({"response": response_text, "agent_action": agent_action_label}), 200
    except requests.exceptions.Timeout:
        return jsonify({"error": f"Failed to connect to Ollama ({model_to_use}): Timeout"}), 500
    except requests.exceptions.ConnectionError:
        return jsonify({"error": f"Failed to connect to Ollama ({model_to_use}): Connection Error"}), 500
    except requests.exceptions.RequestException as e:
        return jsonify({"error": f"Failed to communicate with Ollama ({model_to_use}): {e}"}), 500
    except json.JSONDecodeError:
        return jsonify({"error": f"Invalid JSON response from Ollama ({model_to_use})"}), 500
    except Exception as e:
        print(f"An unexpected error occurred in chat endpoint: {e}")
        return jsonify({"error": f"An unexpected server error occurred: {str(e)}"}), 500

@app.route('/api/history', methods=['GET'])
def get_history():
    messages_db = Message.query.order_by(Message.timestamp.asc()).all()
    messages_list = [msg.to_dict() for msg in messages_db]
    return jsonify(messages_list), 200

if __name__ == '__main__':
    # Removed db.create_all() from here as it's called by init_db()
    app.run(host='0.0.0.0', port=5000, debug=True)

# File tool functions
def read_file_tool(file_path: str):
    try:
        full_path = os.path.join(agent_workspace_path, file_path)
        # Security check
        if not os.path.abspath(full_path).startswith(agent_workspace_path):
            return "Error: Access denied."
        with open(full_path, 'r') as f:
            content = f.read()
        return content
    except FileNotFoundError:
        return "Error: File not found."
    except (IOError, OSError) as e:
        print(f"Error reading file {full_path}: {e}")
        return "Error: Could not read file due to system error."

def write_file_tool(file_path: str, content: str):
    try:
        full_path = os.path.join(agent_workspace_path, file_path)
        # Security check
        if not os.path.abspath(full_path).startswith(agent_workspace_path):
            return "Error: Access denied."
        with open(full_path, 'w') as f:
            f.write(content)
        return "Success: File written."
    except (IOError, OSError) as e:
        print(f"Error writing to file {full_path}: {e}")
        return "Error: Could not write to file due to system error."
EOF_APP_PY

echo ">>> Overwriting frontend/src/App.tsx..."
cat <<'EOF_APP_TSX' > frontend/src/App.tsx
import React, { useState, FormEvent, ChangeEvent, useEffect } from 'react';
import axios from 'axios';
import './App.css'; // Assuming create-react-app made this

interface Message {
  id?: number; // Optional, as it might not be present for new messages
  text: string;
  sender: 'user' | 'ai' | 'system-info'; // Added 'system-info'
  timestamp?: string; // Optional, for messages from history
}

function App() {
  const [messages, setMessages] = useState<Message[]>([]);
  const [input, setInput] = useState<string>('');
  const [loading, setLoading] = useState<boolean>(false);

  useEffect(() => {
    const fetchHistory = async () => {
      console.log("Fetching chat history...");
      setLoading(true);
      try {
        const response = await axios.get<Message[]>('http://localhost:5000/api/history');
        // Assuming backend returns messages in chronological order (timestamp asc)
        setMessages(response.data);
      } catch (error) {
        console.error('Error fetching chat history:', error);
        // Add a system message to the chat indicating failure
        const historyErrorMsg: Message = {
          text: 'Failed to load chat history. Previous messages may not be available.',
          sender: 'system-info'
        };
        setMessages(prev => [...prev, historyErrorMsg]);
      } finally {
        setLoading(false);
      }
    };

    fetchHistory();
  }, []); // Empty dependency array ensures this runs only once on mount

  const handleSendMessage = async (e: FormEvent) => {
    e.preventDefault();
    if (input.trim() === '') return;

    const userMessage: Message = { text: input, sender: 'user' };
    setMessages((prevMessages) => [...prevMessages, userMessage]);
    const currentInput = input; // Capture current input before clearing
    setInput('');
    setLoading(true);

    try {
      const response = await axios.post('http://localhost:5000/api/chat', {
        message: currentInput, // Use captured input
      });

      const agentAction = response.data.agent_action;
      const responseText = response.data.response;

      const aiMessage: Message = {
        text: responseText,
        sender: 'ai'
      };

      if (agentAction && typeof agentAction === 'string' && agentAction.startsWith('file_')) {
        aiMessage.text = `[File Tool] ${responseText}`;
      }

      setMessages((prevMessages) => [...prevMessages, aiMessage]);
    } catch (error) {
      console.error('Error sending message to backend:', error);
      let errorMessageText = 'Error: Could not get response from AI. Check backend (http://localhost:5000) and Ollama (http://localhost:11434).';
      if (axios.isAxiosError(error) && error.response) {
        // If backend provides a specific error message, prefer that.
        errorMessageText = error.response.data.error || errorMessageText;
      } else if (axios.isAxiosError(error) && error.request) {
        // Network error or backend not reachable
         errorMessageText = 'Error: Cannot connect to backend. Please ensure it is running.';
      }
      const errorMessage: Message = {
        text: errorMessageText,
        sender: 'ai',
      };
      setMessages((prevMessages) => [...prevMessages, errorMessage]);
    } finally {
      setLoading(false);
    }
  };

  const handleInputChange = (e: ChangeEvent<HTMLInputElement>) => {
    setInput(e.target.value);
  };

  return (
    <div className="App">
      <header className="App-header">
        <h1>PSI AI Chat</h1>
      </header>
      <div className="chat-container">
        <div className="messages-display">
          {messages.map((msg, index) => (
            <div key={msg.id || index} className={`message ${msg.sender}`}>
              <strong>{msg.sender === 'user' ? 'You' : msg.sender === 'ai' ? 'AI' : 'System'}:</strong> {msg.text}
              {msg.timestamp && <span className="timestamp">{new Date(msg.timestamp).toLocaleTimeString()}</span>}
            </div>
          ))}
          {loading && messages.length === 0 && <div className="message system-info"><strong>System:</strong> Loading history...</div>}
          {loading && messages.length > 0 && <div className="message ai"><strong>AI:</strong> Thinking...</div>}
        </div>
        <form onSubmit={handleSendMessage} className="message-input-form">
          <input
            type="text"
            value={input}
            onChange={handleInputChange}
            placeholder="Type your message..."
            disabled={loading && messages.length > 0}
          />
          <button type="submit" disabled={loading && messages.length > 0}>Send</button>
        </form>
      </div>
    </div>
  );
}

export default App;
EOF_APP_TSX

echo ">>> Activating Python virtual environment..."
source backend/venv/bin/activate || { echo "Failed to activate Python venv. Check backend/venv. Exiting."; exit 1; }

echo ">>> Starting Flask backend server..."
nohup python backend/app.py > backend.log 2>&1 &
echo "Backend server logs will be in backend.log"

echo ">>> Starting React frontend server..."
cd frontend || { echo "Failed to navigate to frontend directory. Exiting."; exit 1; }
nohup npm start > ../frontend.log 2>&1 &
cd .. || { echo "Failed to navigate back to project root. Exiting."; exit 1; } # Navigate back to root for consistency
echo "Frontend server logs will be in frontend.log (in project root)"
echo "Wait a few moments for the servers to initialize."

echo "---------------------------------------------------------------------"
echo "PSI PWA with File Management Tool Setup Complete!"
echo "---------------------------------------------------------------------"
echo ""
echo "The backend and frontend servers have been started in the background."
echo ""
echo "Backend API server should be running on: http://localhost:5000"
echo "Frontend React app should be accessible at: http://localhost:3000 (or the port indicated by npm)"
echo ""
echo "New File Management Capabilities:"
echo "You can now instruct the agent to read and write files in its workspace."
echo "Example prompts:"
echo "  'write to my_notes.txt content This is a test note about project X.'"
echo "  'read file my_notes.txt'"
echo "  'show me content of my_notes.txt'"
echo "  'save this to important_ideas.md: Start with a clear objective...'"
echo ""
echo "Important Notes:"
echo "- Files are stored in the 'agent_workspace' directory within the project."
echo "- Ensure Ollama (Mistral, Deepseek-coder) is running separately (http://localhost:11434)."
echo "- Make sure you have run 'npm install' in the 'frontend' directory if you haven't already."
echo ""
echo "To check logs:"
echo "  tail -f backend.log"
echo "  tail -f frontend.log"
echo ""
echo "To stop the servers:"
echo "  pkill -f 'python backend/app.py'"
echo "  pkill -f 'npm start'" # Simplified pkill for npm start
echo "  echo 'Servers stopped.'"
echo ""
echo "If you encounter issues, check backend.log and frontend.log for errors."
echo "---------------------------------------------------------------------"

echo "Script finished."
