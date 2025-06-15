import requests
import json
from flask import Flask, request, jsonify, session
from flask_cors import CORS
from flask_sqlalchemy import SQLAlchemy
from datetime import datetime
import os
import sys # Added for sys.path manipulation
import time
import logging # Added for logging

# --- Pre-Flask App Initialization ---

# 1. Configure basic logging
# Moved to be one of the first things to ensure logging is available early.
logging.basicConfig(level=logging.INFO, format='%(asctime)s - %(levelname)s - %(message)s')

# 2. Discover Tools
# This needs to happen before the Flask app uses AVAILABLE_TOOLS or AVAILABLE_TOOL_SCHEMAS.
tools_dir_path = os.path.join(os.path.dirname(__file__), "tools")

# Add tools directory to sys.path to allow agent_core to import them
if tools_dir_path not in sys.path:
    sys.path.insert(0, tools_dir_path)
    logging.info(f"Tools directory '{tools_dir_path}' added to sys.path.")

try:
    from agent_core import discover_tools
    logging.info(f"Discovering tools from: {tools_dir_path}")
    AVAILABLE_TOOLS_FUNCTIONS, AVAILABLE_TOOL_SCHEMAS = discover_tools(tools_dir_path)
    logging.info(f"Discovered {len(AVAILABLE_TOOLS_FUNCTIONS)} tool functions.")
    logging.debug(f"Tool Schemas: {json.dumps(AVAILABLE_TOOL_SCHEMAS, indent=2)}")
except ImportError as e:
    logging.error(f"Failed to import discover_tools from agent_core: {e}. Ensure agent_core.py is in the backend directory or PYTHONPATH.")
    AVAILABLE_TOOLS_FUNCTIONS = {}
    AVAILABLE_TOOL_SCHEMAS = {}
except Exception as e:
    logging.error(f"An error occurred during tool discovery: {e}")
    AVAILABLE_TOOLS_FUNCTIONS = {}
    AVAILABLE_TOOL_SCHEMAS = {}


# --- Flask App Initialization ---
app = Flask(__name__)
app.secret_key = os.getenv('FLASK_SECRET_KEY', 'your_super_secret_key_please_change_me_in_production')
CORS(app, supports_credentials=True)

# Database Configuration
app.config['SQLALCHEMY_DATABASE_URI'] = os.getenv('DATABASE_URL', 'sqlite:///messages.db')
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False
db = SQLAlchemy(app)

# --- Database Models ---
class Message(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    sender = db.Column(db.String(50), nullable=False) # 'user', 'ai', 'system-info', 'tool-result'
    text = db.Column(db.Text, nullable=False)
    timestamp = db.Column(db.DateTime, default=datetime.utcnow)
    agent_action = db.Column(db.String(100), nullable=True) # e.g., 'llm_mistral', 'tool_read_file'
    tool_input = db.Column(db.Text, nullable=True) # JSON string of tool arguments
    tool_output = db.Column(db.Text, nullable=True) # JSON string of tool result or error

    def to_dict(self):
        return {
            'id': self.id,
            'sender': self.sender,
            'text': self.text,
            'timestamp': self.timestamp.isoformat() + 'Z', # ISO 8601 format with Z for UTC
            'agent_action': self.agent_action,
            'tool_input': self.tool_input,
            'tool_output': self.tool_output,
        }

class AgentProfile(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(100), unique=True, nullable=False)
    system_prompt_template = db.Column(db.Text, nullable=False) # Uses {tool_schemas}
    description = db.Column(db.Text, nullable=True)
    is_default = db.Column(db.Boolean, default=False)

    def to_dict(self):
        return {
            'id': self.id,
            'name': self.name,
            'system_prompt_template': self.system_prompt_template,
            'description': self.description,
            'is_default': self.is_default
        }

def init_db():
    with app.app_context():
        db.create_all()
        logging.info("Database tables created or verified.")

        if not AgentProfile.query.filter_by(name='General Assistant').first():
            general_profile = AgentProfile(
                name='General Assistant',
                system_prompt_template="""You are a helpful AI assistant.
                Available tools: {tool_schemas}
                Respond concisely and accurately. If using a tool, explain which tool and why.
                If a tool fails, report the error. If a tool succeeds, summarize the result.
                """,
                description='A general-purpose AI assistant capable of using various tools.'
            )
            db.session.add(general_profile)
            logging.info("Added 'General Assistant' profile.")

        if not AgentProfile.query.filter_by(name='Code Reviewer').first():
            code_profile = AgentProfile(
                name='Code Reviewer',
                system_prompt_template="""You are a meticulous code reviewer.
                Available tools: {tool_schemas}
                Focus on code quality, best practices, potential bugs, and efficiency.
                Provide code examples when necessary.
                If using a tool for analysis, explain its findings.
                """,
                description='Specializes in code analysis and review, can use tools for file operations.'
            )
            db.session.add(code_profile)
            logging.info("Added 'Code Reviewer' profile.")

        default_profile = AgentProfile.query.filter_by(is_default=True).first()
        if not default_profile:
            ga_profile = AgentProfile.query.filter_by(name='General Assistant').first()
            if ga_profile:
                ga_profile.is_default = True
                logging.info("Set 'General Assistant' as default profile.")
        db.session.commit()

# --- Ollama Interaction ---
def call_ollama_chat_api(model_name: str, system_prompt: str, user_prompt: str, conversation_history: list):
    ollama_url = os.getenv("OLLAMA_API_BASE_URL", "http://localhost:11434") + "/api/chat"

    messages = [{"role": "system", "content": system_prompt}]
    for msg in conversation_history: # Assumes history is correctly formatted
        messages.append({"role": msg['sender'], "content": msg['text']})
    messages.append({"role": "user", "content": user_prompt})

    payload = {
        "model": model_name,
        "messages": messages,
        "stream": False,
        "options": { # Example options, adjust as needed
            "temperature": 0.7,
            "top_p": 0.9
        }
    }
    logging.debug(f"Ollama payload: {json.dumps(payload, indent=2)}")

    try:
        response = requests.post(ollama_url, json=payload, timeout=180) # Increased timeout
        response.raise_for_status()
        ollama_response_data = response.json()

        ai_message_content = ollama_response_data.get('message', {}).get('content', 'No content from AI.')

        # Log usage details (optional, but good for debugging)
        if 'total_duration' in ollama_response_data and 'prompt_eval_count' in ollama_response_data:
            logging.info(
                f"Ollama call successful for model '{model_name}'. "
                f"Duration: {ollama_response_data['total_duration']/1e9:.2f}s. "
                f"Prompt tokens: {ollama_response_data['prompt_eval_count']}. "
                f"Response tokens: {ollama_response_data.get('eval_count',0)}."
            )
        return ai_message_content

    except requests.exceptions.RequestException as e:
        logging.error(f"Ollama request failed: {e}")
        return f"ERROR: AI service request failed: {e}"
    except json.JSONDecodeError:
        logging.error(f"Invalid JSON response from Ollama for model {model_name}. Response: {response.text}")
        return "ERROR: Invalid response from AI service."
    except Exception as e:
        logging.error(f"Unexpected error during Ollama call: {e}")
        return f"ERROR: Unexpected AI error: {e}"


# --- Flask Routes ---
@app.route('/')
def hello_world():
    return 'Hello from PSI Agent Backend!'

@app.route('/api/chat', methods=['POST'])
def chat():
    data = request.get_json()
    user_message_text = data.get('message', '').strip()
    profile_id = data.get('profile_id') # Allow client to specify profile

    if not user_message_text:
        return jsonify({"error": "Empty message received."}), 400

    # --- Profile Selection ---
    active_profile = None
    if profile_id:
        active_profile = AgentProfile.query.get(profile_id)
    if not active_profile:
        active_profile = AgentProfile.query.filter_by(is_default=True).first()
    if not active_profile: # Fallback if database is empty or no default
        logging.error("No active or default agent profile found. Chat functionality may be impaired.")
        # Create a temporary emergency profile
        system_prompt_for_chat = "You are a helpful AI assistant. No tools are available at the moment."
        profile_name_for_log = "Emergency Fallback Profile"
    else:
        profile_name_for_log = active_profile.name
        # Format the system prompt with available tool schemas
        formatted_tool_schemas = json.dumps(AVAILABLE_TOOL_SCHEMAS, indent=2)
        system_prompt_for_chat = active_profile.system_prompt_template.format(tool_schemas=formatted_tool_schemas)

    logging.info(f"Using agent profile: {profile_name_for_log}")

    # --- Store User Message ---
    user_msg_db = Message(sender='user', text=user_message_text)
    db.session.add(user_msg_db)
    db.session.commit()

    # --- Prepare Conversation History for Ollama ---
    # Retrieve last N messages for context, could be made configurable
    # For now, let's keep it simple and send only the current user message after the system prompt
    # More advanced history management can be added later.
    # For tool use, history might be more critical.
    ollama_history = [] # Example: [{'sender': 'user', 'text': 'previous_message'}, {'sender': 'assistant', 'text': 'previous_response'}]
    # For now, we'll let the system prompt and current user message drive the conversation.
    # A more sophisticated approach would fetch and format recent Message objects.


    # --- Initial Orchestrator Call ---
    # The orchestrator decides if a tool is needed or can respond directly.
    # For simplicity, the orchestrator prompt is the same as the chat system prompt for now.
    # A more advanced orchestrator would have its own meta-prompt.

    orchestrator_model = os.getenv("OLLAMA_ORCHESTRATOR_MODEL", "mistral") # e.g., mistral, or a fine-tuned model
    logging.info(f"Orchestrator model: {orchestrator_model}")

    # The user prompt to the orchestrator LLM includes instructions to choose a tool or respond.
    # This is a simplified version. A more robust version would use a specific orchestrator prompt.
    orchestrator_user_prompt = f"""
User's message: "{user_message_text}"

Based on the user's message and the available tools (schemas provided in the system prompt),
decide if a tool needs to be called or if you can respond directly.

Your response MUST be a JSON object.
If a tool is needed, structure it like this:
{{
  "action_type": "tool_call",
  "tool_name": "name_of_the_tool_function",
  "tool_args": {{ "arg1": "value1", "arg2": "value2" }}
}}
(Ensure 'tool_name' matches one of the available tools: {', '.join(AVAILABLE_TOOLS_FUNCTIONS.keys())})

If you can respond directly without a tool, structure it like this:
{{
  "action_type": "direct_response",
  "response_text": "Your answer here."
}}

Do NOT add any text outside this JSON object.
"""

    logging.info("Phase 1: Orchestrator decision making.")
    orchestrator_response_raw = call_ollama_chat_api(
        orchestrator_model,
        system_prompt_for_chat, # System prompt includes tool schemas
        orchestrator_user_prompt,
        ollama_history # Pass relevant history for context
    )

    ai_response_text = ""
    agent_action_log = "orchestrator_decision"
    tool_input_log = None
    tool_output_log = None

    try:
        decision_data = json.loads(orchestrator_response_raw)
        action_type = decision_data.get("action_type")
        logging.info(f"Orchestrator decision: {action_type}")

        if action_type == "tool_call":
            tool_name = decision_data.get("tool_name")
            tool_args = decision_data.get("tool_args", {})
            tool_input_log = json.dumps(tool_args)
            agent_action_log = f"tool_{tool_name}"

            if tool_name in AVAILABLE_TOOLS_FUNCTIONS:
                tool_func = AVAILABLE_TOOLS_FUNCTIONS[tool_name]
                logging.info(f"Executing tool: {tool_name} with args: {tool_args}")

                # Log system message about tool usage
                tool_system_msg = Message(sender='system-info', text=f"Using tool: {tool_name} with input: {json.dumps(tool_args)}", agent_action=f"tool_call_{tool_name}", tool_input=tool_input_log)
                db.session.add(tool_system_msg)
                db.session.commit()

                try:
                    tool_result = tool_func(**tool_args) # Execute the tool
                    tool_output_log = json.dumps(tool_result)
                    logging.info(f"Tool '{tool_name}' result: {tool_result}")

                    # Log tool result message
                    tool_result_msg = Message(sender='tool-result', text=f"Tool {tool_name} output: {json.dumps(tool_result)}", agent_action=f"tool_result_{tool_name}", tool_output=tool_output_log)
                    db.session.add(tool_result_msg)
                    db.session.commit()

                    # Phase 2: LLM call to formulate response based on tool output
                    # This prompt asks the LLM to interpret the tool's output for the user.
                    formulation_user_prompt = f"""
The user's original message was: "{user_message_text}"
You decided to use the tool '{tool_name}' with arguments {json.dumps(tool_args)}.
The tool returned the following output:
{json.dumps(tool_result)}

Based on this, formulate a helpful and informative response to the user.
If the tool was successful, explain what it did and the result.
If the tool seems to have failed or returned an error, inform the user clearly but politely.
"""
                    logging.info("Phase 2: Formulating response after tool execution.")
                    ai_response_text = call_ollama_chat_api(
                        os.getenv("OLLAMA_CHAT_MODEL", "mistral"), # Use general chat model here
                        system_prompt_for_chat, # Original system prompt
                        formulation_user_prompt,
                        ollama_history # Could include user_msg + orchestrator decision + tool_result
                    )
                except Exception as e:
                    logging.error(f"Error executing tool {tool_name} or processing its result: {e}")
                    ai_response_text = f"An error occurred while executing tool {tool_name}: {e}"
                    tool_output_log = json.dumps({"error": str(e), "tool_name": tool_name})
                    # Log error tool result
                    tool_error_msg = Message(sender='tool-result', text=f"Tool {tool_name} error: {str(e)}", agent_action=f"tool_error_{tool_name}", tool_output=tool_output_log)
                    db.session.add(tool_error_msg)
                    db.session.commit()


            else:
                logging.warning(f"Orchestrator requested unknown tool: '{tool_name}'. Responding directly.")
                ai_response_text = f"I tried to use a tool called '{tool_name}', but I don't have it. I'll try to answer directly."
                # Fallback to direct response if tool is unknown
                # (This part could be refined, maybe another LLM call or a standard message)
                ai_response_text = call_ollama_chat_api(
                    os.getenv("OLLAMA_CHAT_MODEL", "mistral"), system_prompt_for_chat, user_message_text, ollama_history
                )
                agent_action_log = "unknown_tool_fallback"

        elif action_type == "direct_response":
            ai_response_text = decision_data.get("response_text", "I'm not sure how to respond to that yet.")
            agent_action_log = "direct_response"
            logging.info(f"Orchestrator chose direct response: {ai_response_text[:100]}...")

        else:
            logging.error(f"Orchestrator gave unhandled action_type: '{action_type}'. Raw: {orchestrator_response_raw}")
            ai_response_text = "I received an unexpected decision from my internal processing. I'll try to answer directly."
            # Fallback to direct response
            ai_response_text = call_ollama_chat_api(
                 os.getenv("OLLAMA_CHAT_MODEL", "mistral"), system_prompt_for_chat, user_message_text, ollama_history
            )
            agent_action_log = "unhandled_action_fallback"

    except json.JSONDecodeError:
        logging.error(f"Failed to parse orchestrator JSON response: {orchestrator_response_raw}")
        ai_response_text = "My decision-making process (orchestrator) returned an invalid format. I'll try to answer directly."
        # Fallback to direct response
        ai_response_text = call_ollama_chat_api(
             os.getenv("OLLAMA_CHAT_MODEL", "mistral"), system_prompt_for_chat, user_message_text, ollama_history
        )
        agent_action_log = "orchestrator_json_error_fallback"
    except Exception as e:
        logging.error(f"Error processing orchestrator response or executing action: {e}")
        ai_response_text = f"An unexpected error occurred: {e}. I'll try to answer directly."
        # Fallback to direct response
        ai_response_text = call_ollama_chat_api(
            os.getenv("OLLAMA_CHAT_MODEL", "mistral"), system_prompt_for_chat, user_message_text, ollama_history
        )
        agent_action_log = "orchestrator_exception_fallback"

    # --- Store AI Response ---
    ai_msg_db = Message(
        sender='ai',
        text=ai_response_text,
        agent_action=agent_action_log,
        tool_input=tool_input_log,
        tool_output=tool_output_log
    )
    db.session.add(ai_msg_db)
    db.session.commit()

    logging.info(f"Final AI Response (action: {agent_action_log}): {ai_response_text[:100]}...")

    return jsonify({
        "response": ai_response_text,
        "agent_action": agent_action_log,
        "profile_name": profile_name_for_log,
        "tool_input": tool_input_log,
        "tool_output": tool_output_log
    }), 200


@app.route('/api/history', methods=['GET'])
def get_history():
    try:
        limit = request.args.get('limit', 100, type=int)
        messages = Message.query.order_by(Message.timestamp.asc()).limit(limit).all()
        return jsonify([msg.to_dict() for msg in messages]), 200
    except Exception as e:
        logging.error(f"Error fetching history: {e}")
        return jsonify({"error": "Failed to fetch history", "details": str(e)}), 500

@app.route('/api/profiles', methods=['GET'])
def get_profiles_route():
    try:
        profiles = AgentProfile.query.all()
        current_profile_id = session.get('current_profile_id') # Assuming session might store this
        active_profile = AgentProfile.query.filter_by(is_default=True).first()

        # If current_profile_id is not in session, use the default profile's ID
        if not current_profile_id and active_profile:
            current_profile_id = active_profile.id

        return jsonify({
            "profiles": [p.to_dict() for p in profiles],
            "current_profile_id": current_profile_id, # ID of the currently active/default profile
            "default_profile_id": active_profile.id if active_profile else None
        }), 200
    except Exception as e:
        logging.error(f"Error fetching profiles: {e}")
        return jsonify({"error": "Failed to fetch profiles", "details": str(e)}), 500

@app.route('/api/set_profile', methods=['POST'])
def set_profile_route():
    data = request.get_json()
    profile_id = data.get('profile_id')
    if not profile_id:
        return jsonify({"error": "profile_id is required"}), 400

    new_default_profile = AgentProfile.query.get(profile_id)
    if not new_default_profile:
        return jsonify({"error": "Profile not found"}), 404

    try:
        # Unset current default
        current_default = AgentProfile.query.filter_by(is_default=True).first()
        if current_default:
            current_default.is_default = False
            db.session.add(current_default)

        # Set new default
        new_default_profile.is_default = True
        db.session.add(new_default_profile)
        db.session.commit()

        session['current_profile_id'] = new_default_profile.id # Optional: update session
        logging.info(f"Default agent profile changed to: {new_default_profile.name}")
        return jsonify({"message": f"Default profile set to {new_default_profile.name}.", "current_profile": new_default_profile.to_dict()}), 200
    except Exception as e:
        db.session.rollback()
        logging.error(f"Error setting profile: {e}")
        return jsonify({"error": "Failed to set profile", "details": str(e)}), 500


# --- Main Execution ---
if __name__ == '__main__':
    with app.app_context():
        init_db() # Initialize DB and add default profiles

    # Pre-pull models (optional, good for first run)
    # Consider moving to a startup script or Dockerfile
    ollama_check_url = os.getenv("OLLAMA_API_BASE_URL", "http://localhost:11434")
    try:
        requests.get(ollama_check_url, timeout=5) # Check if Ollama is running
        logging.info("Ollama service detected. Checking/pulling models...")
        # Models to pre-pull - make these configurable via environment variables
        orchestrator_model_name = os.getenv("OLLAMA_ORCHESTRATOR_MODEL", "mistral")
        chat_model_name = os.getenv("OLLAMA_CHAT_MODEL", "mistral")

        # Using os.system for simplicity, subprocess is generally safer/more flexible
        if os.system(f"ollama pull {orchestrator_model_name}") != 0:
             logging.warning(f"Could not pre-pull orchestrator model '{orchestrator_model_name}'. Ensure Ollama is running and the model is valid.")
        else:
            logging.info(f"Orchestrator model '{orchestrator_model_name}' is available.")

        if orchestrator_model_name != chat_model_name: # Avoid pulling same model twice
            if os.system(f"ollama pull {chat_model_name}") != 0:
                logging.warning(f"Could not pre-pull chat model '{chat_model_name}'.")
            else:
                logging.info(f"Chat model '{chat_model_name}' is available.")
        else:
            logging.info(f"Chat model is the same as orchestrator model ('{chat_model_name}'), no separate pull needed.")

    except requests.exceptions.ConnectionError:
        logging.warning(f"Ollama service not reachable at {ollama_check_url}. Cannot pre-pull models. Please ensure Ollama is running.")
    except Exception as e:
        logging.error(f"An error occurred during model pre-pull check: {e}")

    app.run(host='0.0.0.0', port=5000, debug=os.getenv('FLASK_DEBUG', 'False').lower() == 'true')
