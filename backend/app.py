import requests
import json
from flask import Flask, request, jsonify
from flask_cors import CORS
from flask_sqlalchemy import SQLAlchemy
from datetime import datetime
import os
import time

app = Flask(__name__)
CORS(app)

# Database Configuration
app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:///messages.db'
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False
db = SQLAlchemy(app)

# Define Message Model
class Message(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    sender = db.Column(db.String(50), nullable=False) # 'user', 'ai', 'system-info'
    text = db.Column(db.Text, nullable=False)
    timestamp = db.Column(db.DateTime, default=datetime.utcnow)
    agent_action = db.Column(db.String(100), nullable=True) # e.g., 'llm_mistral', 'tool_used'

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
        print("Database tables created or already exist.")

# --- Agent Tools ---
AGENT_WORKSPACE_DIR = os.path.expanduser('~/psi_pwa_linux_new/agent_workspace') # Path to agent workspace

def _resolve_filepath(filename: str):
    """Safely resolves a filename to be within the agent workspace."""
    if not filename:
        return None, "Filename cannot be empty."

    safe_filename = filename.lstrip('/')

    filepath = os.path.join(AGENT_WORKSPACE_DIR, safe_filename)

    if not os.path.abspath(filepath).startswith(os.path.abspath(AGENT_WORKSPACE_DIR)):
        return None, f"Attempted to access file outside workspace: {filename}"

    return filepath, None

def read_file_tool(filename: str):
    """Reads content from a file within the agent workspace."""
    filepath, error = _resolve_filepath(filename)
    if error:
        return {"tool_name": "read_file", "success": False, "error": error}

    try:
        if not os.path.exists(filepath):
            return {"tool_name": "read_file", "success": False, "error": f"File not found: {filename}"}
        if not os.path.isfile(filepath):
            return {"tool_name": "read_file", "success": False, "error": f"Path is not a file: {filename}"}

        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()
        return {"tool_name": "read_file", "success": True, "filename": filename, "content": content}
    except Exception as e:
        return {"tool_name": "read_file", "success": False, "filename": filename, "error": str(e)}

def write_file_tool(filename: str, content: str):
    """Writes content to a file within the agent workspace."""
    filepath, error = _resolve_filepath(filename)
    if error:
        return {"tool_name": "write_file", "success": False, "error": error}

    try:
        os.makedirs(os.path.dirname(filepath), exist_ok=True)
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(content)
        return {"tool_name": "write_file", "success": True, "filename": filename, "message": f"Content written to {filename}"}
    except Exception as e:
        return {"tool_name": "write_file", "success": False, "filename": filename, "error": str(e)}

def document_processing_tool(text_content: str):
    """
    Performs basic text analysis (word and character count).
    """
    print(f"DEBUG: Document processing tool called with text: '{text_content[:50]}...'")
    time.sleep(1) # Simulate processing time

    word_count = len(text_content.split())
    char_count = len(text_content)

    return {
        "tool_name": "document_processing",
        "success": True,
        "result": f"Text analyzed: {word_count} words, {char_count} characters.",
        "word_count": word_count,
        "char_count": char_count
    }

# --- LLM and Agent Logic ---
def call_ollama(model_name: str, prompt_text: str, conversation_history: list):
    """
    Utility function to call Ollama for a given model and prompt,
    including a condensed conversation history for context.
    """
    ollama_url = os.getenv("OLLAMA_API_BASE_URL", "http://localhost:11434") + "/api/generate"

    messages_for_ollama = []
    messages_for_ollama.append({"role": "system", "content": "You are PSI, a helpful AI agent. Use provided tools if necessary. Keep responses concise unless asked for details."})

    for msg in conversation_history[-5:]: # Get last 5 messages for context
        if msg.sender == 'user':
            messages_for_ollama.append({"role": "user", "content": msg.text})
        elif msg.sender == 'ai':
            messages_for_ollama.append({"role": "assistant", "content": msg.text})

    messages_for_ollama.append({"role": "user", "content": prompt_text})

    try:
        ollama_payload = {
            "model": model_name,
            "prompt": prompt_text,
            "messages": messages_for_ollama,
            "stream": False
        }
        print(f"DEBUG: Calling Ollama with model '{model_name}' for prompt: '{prompt_text[:50]}...' with history.")
        response = requests.post(ollama_url, json=ollama_payload, timeout=120)
        response.raise_for_status()
        ollama_response = response.json()
        ai_message = ollama_response.get('response', 'No response from AI.')
        return ai_message
    except requests.exceptions.RequestException as e:
        print(f"ERROR: Failed to connect to Ollama ({ollama_url}) or request failed: {e}")
        return f"ERROR: Failed to connect to local AI service ({model_name}). Is Ollama running and model pulled? ({e})"
    except json.JSONDecodeError:
        print(f"ERROR: Invalid JSON response from Ollama for model {model_name}.")
        return "ERROR: Invalid response from local AI service."
    except Exception as e:
        print(f"ERROR: An unexpected error occurred during Ollama call: {e}")
        return f"ERROR: An unexpected error occurred with AI: {e}"

@app.route('/')
def hello_world():
    return 'Hello from PSI Backend!'

@app.route('/api/chat', methods=['POST'])
def chat():
    data = request.get_json()
    user_message_text = data.get('message', '').strip()

    if not user_message_text:
        return jsonify({"response": "Please provide a message.", "agent_action": "none"}), 200

    # Save user message to DB
    user_msg_db = Message(sender='user', text=user_message_text)
    db.session.add(user_msg_db)
    db.session.commit()

    # Retrieve recent history for agent context
    recent_messages = Message.query.order_by(Message.timestamp.desc()).limit(5).all()
    recent_messages.reverse() # Reverse to get chronological order for context

    ai_response_text = ""
    agent_action = "none"
    tool_details = None
    system_info_message = None # To store system message about tool action

    # --- Enhanced Agent Orchestration Logic with File and Document Tools ---
    lower_message = user_message_text.lower()

    if "read file" in lower_message or "show content of" in lower_message:
        filename_match = lower_message.replace("read file", "").replace("show content of", "").strip()
        if filename_match:
            print(f"DEBUG: Agent identified 'read file' intent for: '{filename_match}'")
            tool_output = read_file_tool(filename_match)
            tool_details = tool_output # Capture tool details
            if tool_output["success"]:
                ai_response_text = f"Agent read '{tool_output['filename']}'. Content: \n```\n{tool_output['content'][:500]}...\n```\n(Content truncated for display if too long)"
                agent_action = "file_read_success"
                system_info_message = Message(sender='system-info', text=f"Tool Used: Read file '{tool_output['filename']}' successfully.", agent_action='file_read_success')
            else:
                ai_response_text = f"Agent failed to read '{filename_match}'. Error: {tool_output['error']}"
                agent_action = "file_read_failure"
                system_info_message = Message(sender='system-info', text=f"Tool Failed: Read file '{filename_match}'. Error: {tool_output['error']}.", agent_action='file_read_failure')
        else:
            ai_response_text = "Please specify a filename to read."
            agent_action = "tool_needed"

    elif "write to" in lower_message or "save to" in lower_message:
        parts = []
        if "write to" in lower_message:
            parts = lower_message.split("write to", 1)
        elif "save to" in lower_message:
            parts = lower_message.split("save to", 1)

        filename = ""
        content = ""
        if len(parts) > 1:
            remainder = parts[1].strip()
            if " content " in remainder:
                file_parts = remainder.split(" content ", 1)
                filename = file_parts[0].strip()
                content = file_parts[1].strip()
            elif ":" in remainder and remainder.count(":") == 1: # "save to [filename]: [content]"
                file_parts = remainder.split(":", 1)
                filename = file_parts[0].strip()
                content = file_parts[1].strip()

        if filename and content:
            print(f"DEBUG: Agent identified 'write file' intent for: '{filename}'")
            tool_output = write_file_tool(filename, content)
            tool_details = tool_output # Capture tool details
            if tool_output["success"]:
                ai_response_text = f"Agent wrote content to '{tool_output['filename']}'. " + tool_output.get('message', '')
                agent_action = "file_write_success"
                system_info_message = Message(sender='system-info', text=f"Tool Used: Wrote to file '{tool_output['filename']}' successfully.", agent_action='file_write_success')
            else:
                ai_response_text = f"Agent failed to write to '{filename}'. Error: {tool_output['error']}"
                agent_action = "file_write_failure"
                system_info_message = Message(sender='system-info', text=f"Tool Failed: Write to file '{filename}'. Error: {tool_output['error']}.", agent_action='file_write_failure')
        else:
            ai_response_text = "Please specify a filename and content to write (e.g., 'write to my_file.txt content This is my text')."
            agent_action = "tool_needed"

    elif "process document" in lower_message or "analyze text" in lower_message:
        print("DEBUG: Agent identified a 'document processing' intent.")
        document_text = user_message_text.replace("process document", "").replace("analyze text", "").strip()
        if not document_text:
            ai_response_text = "Please provide text to process with the 'process document' command."
            agent_action = "tool_needed"
        else:
            tool_output = document_processing_tool(document_text)
            tool_details = tool_output # Capture tool details
            if tool_output["success"]:
                ai_response_text = f"Agent used document processing tool. Result: {tool_output['result']}"
                agent_action = "tool_used" # Keep as 'tool_used' for generic success
                system_info_message = Message(sender='system-info', text=f"Tool Used: Document processing successfully. {tool_output['result']}", agent_action='tool_used')
            else:
                ai_response_text = f"Agent failed to process document. Error: {tool_output['error']}"
                agent_action = "tool_failure" # New action type for tool failures if needed, or re-use tool_needed
                system_info_message = Message(sender='system-info', text=f"Tool Failed: Document processing. Error: {tool_output['error']}.", agent_action='tool_failure')
    elif "code" in lower_message or "python" in lower_message or "javascript" in lower_message:
        print("DEBUG: Agent identified a 'coding' intent. Using deepseek-coder.")
        ai_response_text = call_ollama("deepseek-coder", user_message_text, recent_messages)
        agent_action = "llm_deepseek"
    else:
        print("DEBUG: Agent identified a 'general chat' intent. Using mistral.")
        ai_response_text = call_ollama("mistral", user_message_text, recent_messages)
        agent_action = "llm_mistral"

    # Save system info message to DB if it was generated
    if system_info_message:
        db.session.add(system_info_message)
        db.session.commit()

    # Save AI response to DB
    ai_msg_db = Message(sender='ai', text=ai_response_text, agent_action=agent_action)
    db.session.add(ai_msg_db)
    db.session.commit()

    return jsonify({"response": ai_response_text, "agent_action": agent_action, "tool_details": tool_details}), 200

@app.route('/api/history', methods=['GET'])
def get_history():
    history = Message.query.order_by(Message.timestamp.asc()).limit(20).all()
    return jsonify([msg.to_dict() for msg in history]), 200

if __name__ == '__main__':
    init_db()
    print("Pre-pulling 'deepseek-coder' model for agent functionality...")
    os.system("ollama pull deepseek-coder || true")

    app.run(host='0.0.0.0', port=5000, debug=True)
