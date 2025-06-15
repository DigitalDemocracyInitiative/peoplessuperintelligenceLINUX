import requests
import json
from flask import Flask, request, jsonify, session
from flask_cors import CORS
from flask_sqlalchemy import SQLAlchemy
from datetime import datetime
import os
import time

app = Flask(__name__)
# IMPORTANT: For session management, a secret key is required.
# In a production environment, this should be a strong, random key
# loaded from an environment variable or secure configuration.
app.secret_key = os.getenv('FLASK_SECRET_KEY', 'your_super_secret_key_please_change_me')
CORS(app, supports_credentials=True) # Enable CORS for credentials (cookies, session)

# Database Configuration
app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:///messages.db'
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False
db = SQLAlchemy(app)

# Define Message Model (Existing)
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

# Define AgentProfile Model (NEW)
class AgentProfile(db.Model):
    id = db.Column(db.Integer, primary_key=True)
    name = db.Column(db.String(100), unique=True, nullable=False)
    system_prompt_addition = db.Column(db.Text, nullable=False)
    description = db.Column(db.Text, nullable=True)
    is_default = db.Column(db.Boolean, default=False)

    def to_dict(self):
        return {
            'id': self.id,
            'name': self.name,
            'description': self.description,
            'is_default': self.is_default
        }

# Function to initialize the database and add default profiles
def init_db():
    with app.app_context():
        db.create_all()
        print("Database tables created or already exist.")

        # Add default profiles if they don't exist
        if not AgentProfile.query.filter_by(name='General Assistant').first():
            general_profile = AgentProfile(
                name='General Assistant',
                system_prompt_addition='You are a helpful AI assistant. Respond concisely and accurately.',
                description='A general-purpose AI assistant.'
            )
            db.session.add(general_profile)
            print("Added 'General Assistant' profile.")

        if not AgentProfile.query.filter_by(name='Code Reviewer').first():
            code_profile = AgentProfile(
                name='Code Reviewer',
                system_prompt_addition='You are a meticulous code reviewer. Focus on code quality, best practices, potential bugs, and efficiency when asked about code. Provide code examples when necessary.',
                description='Specializes in code analysis and review.'
            )
            db.session.add(code_profile)
            print("Added 'Code Reviewer' profile.")

        if not AgentProfile.query.filter_by(name='Creative Writer').first():
            creative_profile = AgentProfile(
                name='Creative Writer',
                system_prompt_addition='You are a creative and imaginative writer. Focus on storytelling, generating ideas, and expanding on narratives when asked to write or brainstorm.',
                description='Specializes in creative writing and brainstorming.'
            )
            db.session.add(creative_profile)
            print("Added 'Creative Writer' profile.")

        # Set a default profile if none is set
        if not AgentProfile.query.filter_by(is_default=True).first():
            default_profile = AgentProfile.query.filter_by(name='General Assistant').first()
            if default_profile:
                default_profile.is_default = True
                print("Set 'General Assistant' as default profile.")
        db.session.commit()

# --- Agent Tools ---
AGENT_WORKSPACE_DIR = os.path.expanduser('~/psi_pwa_linux_new/agent_workspace')

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
    """Performs basic text analysis (word and character count)."""
    print(f"DEBUG: Document processing tool called with text: '{text_content[:50]}...'" )
    time.sleep(1)

    word_count = len(text_content.split())
    char_count = len(text_content)

    return {
        "tool_name": "document_processing",
        "success": True,
        "result": f"Text analyzed: {word_count} words, {char_count} characters.",
        "word_count": word_count,
        "char_count": char_count
    }

def internet_search_tool(query: str):
    """Simulates an internet search and returns plausible results."""
    print(f"DEBUG: Internet search tool called with query: '{query}'")
    time.sleep(2) # Simulate network latency

    query_lower = query.lower()

    if "current time" in query_lower or "what time is it" in query_lower:
        result = f"The current time is {datetime.now().strftime('%Y-%m-%d %H:%M:%S')} PDT."
    elif "weather" in query_lower:
        result = "Simulated Weather Report: Sunny with a high of 75°F (24°C) in Los Angeles, California. Light breeze."
    elif "capital of france" in query_lower:
        result = "The capital of France is Paris."
    elif "latest ai advancements" in query_lower:
        result = "Simulated Search Results for 'latest AI advancements':\\n1. AI models like GPT-4o show improved multimodal capabilities.\\n2. Advancements in explainable AI (XAI) are making models more transparent.\\n3. Increased focus on ethical AI and regulatory frameworks globally."
    else:
        result = f"Simulated Search Results for '{query}':\\n1. Wikipedia: Brief overview of {query}.\\n2. Official Source: Key facts about {query}.\\n3. Related Articles: Recent news and discussions on {query}."

    return {"tool_name": "internet_search", "success": True, "query": query, "results": result}

# Mapping of tool names to functions
AVAILABLE_TOOLS = {
    "read_file": read_file_tool,
    "write_file": write_file_tool,
    "document_analysis": document_processing_tool, # Map to the actual tool function name
    "internet_search": internet_search_tool
}

# --- LLM and Agent Logic ---
def call_ollama(model_name: str, system_prompt: str, prompt_text: str, conversation_history: list):
    """
    Utility function to call Ollama for a given model and prompt,
    including a condensed conversation history for context.
    """
    ollama_url = os.getenv("OLLAMA_API_BASE_URL", "http://localhost:11434") + "/api/generate"

    messages_for_ollama = []
    messages_for_ollama.append({"role": "system", "content": system_prompt})

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
    recent_messages.reverse() # Chronological order

    ai_response_text = ""
    agent_action = "none"
    tool_details = None
    system_info_message_text = None

    # --- Agent Orchestrator ---
    # Get current agent profile system prompt
    current_profile_id = session.get('current_profile_id')
    current_profile = None
    if current_profile_id:
        current_profile = AgentProfile.query.get(current_profile_id)
    if not current_profile:
        current_profile = AgentProfile.query.filter_by(is_default=True).first()
    if not current_profile: # Fallback if no default exists (shouldn't happen with init_db)
        current_profile = AgentProfile(name='Default', system_prompt_addition='You are a helpful AI assistant.', description='Default fallback profile.')

    orchestrator_system_prompt = f'''
    You are PSI, an advanced AI agent orchestrator. Your task is to analyze user requests and determine the best course of action.

    Based on the user's message and the conversation history, decide whether to:
    1. Call a specific tool.
    2. Delegate to a specialized LLM (Language Model).
    3. Respond directly as the orchestrator if it's a simple, general query or cannot be handled by tools/specialized LLMs.

    Available Tools:
    - "read_file": Reads content from a specified file in the agent's workspace.
      Input: {{"tool_name": "read_file", "filename": "name_of_file.txt"}}
      Use when the user explicitly asks to read a file, or indicates needing file content.
    - "write_file": Writes content to a specified file in the agent's workspace.
      Input: {{"tool_name": "write_file", "filename": "name_of_file.txt", "content": "text to write"}}
      Use when the user explicitly asks to write to a file or save content.
    - "document_analysis": Analyzes a given text for properties like word count and character count.
      Input: {{"tool_name": "document_analysis", "text": "text_to_analyze"}}
      Use when the user asks to analyze, process, or get insights from a block of text.
    - "internet_search": Performs a simulated internet search to get information.
      Input: {{"tool_name": "internet_search", "query": "search_query_string"}}
      Use when the user asks for current information, facts, definitions, or anything that requires external knowledge beyond your training data.

    Available LLMs (Approaches):
    - "deepseek-coder": Specialized for generating and understanding code.
      Input: {{"action_type": "llm_call", "llm_model": "deepseek-coder", "sub_prompt": "prompt for deepseek-coder"}}
      Use when the user asks for code, programming help, or detailed technical explanations related to coding.
    - "mistral": General-purpose conversational LLM.
      Input: {{"action_type": "llm_call", "llm_model": "mistral", "sub_prompt": "prompt for mistral"}}
      Use for general conversation, creative tasks, brainstorming, or when no specific tool or other specialized LLM is a better fit.

    Output Format:
    Your response MUST be a JSON object with one of the following structures:

    1. For Tool Call:
       {{"action_type": "tool_call", "tool_name": "name_of_tool", "tool_args": {{"arg1": "value1", "arg2": "value2"}}}}
    2. For LLM Call:
       {{"action_type": "llm_call", "llm_model": "model_name", "sub_prompt": "detailed prompt for the selected LLM"}}
    3. For Direct Orchestrator Response (if no tool/LLM is needed, or for conversational aspects of the orchestrator):
       {{"action_type": "orchestrator_response", "response": "Your direct response as orchestrator"}}

    Your persona (from the current profile) is: {current_profile.system_prompt_addition}

    Strictly adhere to the JSON output format. Do NOT include any additional text or formatting outside the JSON object.
    '''

    orchestrator_prompt = f"User request: {user_message_text}"

    print(f"DEBUG: Orchestrator is reasoning for prompt: '{user_message_text[:50]}...'" )
    system_info_message_text = "Agent is reasoning about your request..."
    db.session.add(Message(sender='system-info', text=system_info_message_text, agent_action='orchestrating'))
    db.session.commit()

    orchestrator_response_raw = call_ollama(
        "mistral", # Use mistral for orchestration
        orchestrator_system_prompt,
        orchestrator_prompt,
        recent_messages # Pass history for orchestrator context
    )

    try:
        orchestrator_decision = json.loads(orchestrator_response_raw)
        action_type = orchestrator_decision.get("action_type")

        if action_type == "tool_call":
            tool_name = orchestrator_decision.get("tool_name")
            tool_args = orchestrator_decision.get("tool_args", {})

            if tool_name in AVAILABLE_TOOLS:
                print(f"DEBUG: Orchestrator decided to call tool: {tool_name} with args: {tool_args}")
                system_info_message_text = f"Agent selected tool: '{tool_name}'"
                db.session.add(Message(sender='system-info', text=system_info_message_text, agent_action='tool_selection'))
                db.session.commit()

                tool_func = AVAILABLE_TOOLS[tool_name]
                tool_output = tool_func(**tool_args)
                tool_details = tool_output

                if tool_output.get("success"):
                    if tool_name == "read_file":
                        ai_response_text = f"Content of '{tool_output['filename']}':\\n```\\n{tool_output['content'][:500]}...\\n```\\n(Content truncated for display if too long)"
                        agent_action = "file_read_success"
                        system_info_message_text = f"Tool Used: Read file '{tool_output['filename']}' successfully."
                    elif tool_name == "write_file":
                        ai_response_text = f"Content written to '{tool_output['filename']}'. " + tool_output.get('message', '')
                        agent_action = "file_write_success"
                        system_info_message_text = f"Tool Used: Wrote to file '{tool_output['filename']}' successfully."
                    elif tool_name == "document_analysis":
                        ai_response_text = f"Document analyzed. {tool_output['result']}"
                        agent_action = "tool_used" # generic success for document analysis
                        system_info_message_text = f"Tool Used: Document analysis successfully. {tool_output['result']}"
                    elif tool_name == "internet_search":
                        ai_response_text = f"Search results for '{tool_output['query']}':\\n{tool_output['results']}"
                        agent_action = "internet_search_success"
                        system_info_message_text = f"Tool Used: Internet search for '{tool_output['query']}' successfully."
                    else:
                        ai_response_text = f"Tool '{tool_name}' executed successfully. Result: {tool_output.get('result', json.dumps(tool_output))}"
                        agent_action = "tool_used"
                else:
                    ai_response_text = f"Tool '{tool_name}' failed. Error: {tool_output.get('error', 'Unknown error.')}"
                    agent_action = f"{tool_name}_failure" # Specific failure action
                    system_info_message_text = f"Tool Failed: {tool_name}. Error: {tool_output.get('error', 'N/A')}"
            else:
                ai_response_text = f"Orchestrator requested unknown tool: {tool_name}."
                agent_action = "orchestration_error"
                system_info_message_text = f"Orchestration Error: Unknown tool '{tool_name}'."

        elif action_type == "llm_call":
            llm_model = orchestrator_decision.get("llm_model")
            sub_prompt = orchestrator_decision.get("sub_prompt")

            if llm_model in ["deepseek-coder", "mistral"]:
                print(f"DEBUG: Orchestrator decided to call LLM: {llm_model} with sub-prompt: {sub_prompt[:50]}...")
                system_info_message_text = f"Agent selected LLM: '{llm_model}' to generate response."
                db.session.add(Message(sender='system-info', text=system_info_message_text, agent_action='llm_selection'))
                db.session.commit()

                # Pass the active profile's prompt addition to the LLM call
                llm_system_prompt = f"{current_profile.system_prompt_addition}\\n\\nYour primary goal is to respond to the user based on the following refined prompt."
                ai_response_text = call_ollama(llm_model, llm_system_prompt, sub_prompt, recent_messages)
                agent_action = f"llm_{llm_model.replace('-', '_')}"
            else:
                ai_response_text = f"Orchestrator requested unknown LLM: {llm_model}."
                agent_action = "orchestration_error"
                system_info_message_text = f"Orchestration Error: Unknown LLM '{llm_model}'."

        elif action_type == "orchestrator_response":
            ai_response_text = orchestrator_decision.get("response", "Orchestrator responded directly.")
            agent_action = "orchestrator_direct"
            system_info_message_text = "Orchestrator responded directly."

        else:
            ai_response_text = "Orchestrator returned an unhandled action type."
            agent_action = "orchestration_error"
            system_info_message_text = "Orchestration Error: Unhandled action type."

    except json.JSONDecodeError as e:
        ai_response_text = f"Orchestrator response was not valid JSON. Error: {e}. Raw response: {orchestrator_response_raw}"
        agent_action = "orchestration_error"
        system_info_message_text = f"Orchestration Error: JSON parsing failed ({e})."
        print(f"ERROR: JSONDecodeError: {e}, Raw response: {orchestrator_response_raw}")
    except Exception as e:
        ai_response_text = f"An unexpected error occurred during orchestration: {e}"
        agent_action = "orchestration_error"
        system_info_message_text = f"Orchestration Error: An unexpected error occurred ({e})."
        print(f"ERROR: Orchestration failed: {e}")

    # Save system info message to DB if it was generated (for actual tool/LLM selection)
    if system_info_message_text and agent_action not in ['orchestrating']: # Don't re-log the 'reasoning' status
        db.session.add(Message(sender='system-info', text=system_info_message_text, agent_action=agent_action))
        db.session.commit()

    # Save final AI response to DB
    ai_msg_db = Message(sender='ai', text=ai_response_text, agent_action=agent_action)
    db.session.add(ai_msg_db)
    db.session.commit()

    return jsonify({"response": ai_response_text, "agent_action": agent_action, "tool_details": tool_details, "current_profile": current_profile.to_dict()}), 200

@app.route('/api/history', methods=['GET'])
def get_history():
    history = Message.query.order_by(Message.timestamp.asc()).limit(50).all() # Increased limit for better history
    return jsonify([msg.to_dict() for msg in history]), 200

@app.route('/api/profiles', methods=['GET'])
def get_profiles():
    profiles = AgentProfile.query.all()
    current_profile_id = session.get('current_profile_id')
    profiles_data = [p.to_dict() for p in profiles]
    return jsonify({"profiles": profiles_data, "current_profile_id": current_profile_id}), 200

@app.route('/api/set_profile/<int:profile_id>', methods=['POST'])
def set_profile(profile_id):
    profile = AgentProfile.query.get(profile_id)
    if profile:
        session['current_profile_id'] = profile.id
        print(f"DEBUG: Agent profile set to: {profile.name} (ID: {profile.id})")
        return jsonify({"message": f"Profile set to {profile.name}.", "current_profile": profile.to_dict()}), 200
    return jsonify({"message": "Profile not found."}), 404

if __name__ == '__main__':
    init_db() # Call init_db here to ensure models and default profiles are created
    print("Pre-pulling 'deepseek-coder' model for agent functionality...")
    os.system("ollama pull deepseek-coder || true")
    print("Pre-pulling 'mistral' model for orchestration and general chat if not already present...")
    os.system("ollama pull mistral || true")

    app.run(host='0.0.0.0', port=5000, debug=True)
