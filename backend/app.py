from flask import Flask, request, jsonify
from flask_cors import CORS
import requests
import json # For handling potential json.JSONDecodeError
from flask_sqlalchemy import SQLAlchemy
from datetime import datetime

app = Flask(__name__)
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

    # Save user message to DB
    user_msg_db = Message(sender='user', text=user_message, agent_action='none')
    db.session.add(user_msg_db)
    db.session.commit()

    # Simple intent detection
    if user_message.lower().startswith("process document:"):
        document_text = user_message.split(":", 1)[1].strip()
        if not document_text:
            return jsonify({"error": "Document text is empty after 'process document:' command."}), 400 # Not saved

        # Simulate document processing (replace with actual logic if any)
        # For now, let's assume it summarizes or extracts keywords
        tool_output = {"result": f"Document processed. First 50 chars: {document_text[:50]}..."}

        # Save system message for tool usage
        system_msg_db = Message(sender='system-info', text=f"Agent used document processing tool. Result: {tool_output['result']}", agent_action='tool_used')
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
