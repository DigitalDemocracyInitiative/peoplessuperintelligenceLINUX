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

def document_processing_tool(document_text: str):
    """Processes the given document text for simple analysis."""
    if not isinstance(document_text, str):
        return {"tool_name": "document_processor", "success": False, "error": "Invalid input: Document text must be a string."}
    if not document_text.strip():
        return {"tool_name": "document_processor", "success": False, "error": "Invalid input: Document text cannot be empty."}

    try:
        word_count = len(document_text.split())
        char_count = len(document_text)
        result_summary = f"Document processed: {word_count} words, {char_count} characters."
        return {"tool_name": "document_processor", "success": True, "result": result_summary}
    except Exception as e:
        return {"tool_name": "document_processor", "success": False, "error": f"Error during processing: {str(e)}"}

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
    # The prompt mentions "process document" or "analyze text"
    if user_message.lower().startswith("process document:") or user_message.lower().startswith("analyze text:"):
        # DEBUG print mentioned in prompt, adding it here for consistency if it was intended.
        # print("DEBUG: Agent identified a 'document processing' intent.")
        if user_message.lower().startswith("process document:"):
            document_text = user_message.split(":", 1)[1].strip()
        else: # analyze text:
            document_text = user_message.split(":", 1)[1].strip()

        if not document_text:
            # User message already saved, this is an error for the operation itself
            # We can create a system message for this failure too.
            ai_response_text = "Error: Document text is empty after command."
            agent_action = "tool_failure" # More specific: "empty_document_input_failure"
            system_msg_db = Message(sender='system-info', text=ai_response_text, agent_action=agent_action)
            db.session.add(system_msg_db)
            db.session.commit()
            return jsonify({"error": "Document text is empty after command."}), 400

        tool_output = document_processing_tool(document_text)
        tool_details = tool_output # Store the full tool output

        if tool_output.get("success"):
            ai_response_text = f"Agent used document processing tool. Result: {tool_output['result']}"
            agent_action = "tool_used"
            status_code = 200
        else:
            ai_response_text = f"Agent failed to process document. Error: {tool_output.get('error', 'Unknown error')}"
            agent_action = "tool_failure"
            status_code = 400 # Or 500 if it's an internal tool error vs bad user input handled by the tool

        system_msg_db = Message(sender='system-info', text=ai_response_text, agent_action=agent_action)
        db.session.add(system_msg_db)
        db.session.commit()
        # The response to the client should be structured consistently.
        # If success, client gets the result; if failure, client gets the error.
        if tool_output.get("success"):
            return jsonify({"response": tool_output['result'], "agent_action": agent_action}), status_code
        else:
            return jsonify({"error": tool_output.get('error', 'Unknown error'), "agent_action": agent_action}), status_code

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
