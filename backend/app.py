# backend/app.py
from flask import Flask, request, jsonify, send_from_directory
from flask_sqlalchemy import SQLAlchemy
from sqlalchemy import Column, Integer, String, Text, DateTime, ForeignKey, JSON
from sqlalchemy.orm import relationship, declarative_base
from sqlalchemy.sql import func
import json
import os
from werkzeug.utils import secure_filename
from datetime import datetime
import time
import threading
import ollama
from typing import List, Dict, Any, Optional, Union
from pydantic import BaseModel, Field
import inspect

# Initialize Flask app
app = Flask(__name__)
app.config['SQLALCHEMY_DATABASE_URI'] = 'sqlite:///./test.db'
app.config['SQLALCHEMY_TRACK_MODIFICATIONS'] = False
app.config['UPLOAD_FOLDER'] = 'uploads'
app.config['KNOWLEDGE_BASE_PATH'] = 'knowledge_base' # New

db = SQLAlchemy(app)

# --- SQLAlchemy Models ---
Base = declarative_base()

class AgentProfile(db.Model):
    __tablename__ = 'agent_profile'
    id = Column(Integer, primary_key=True)
    name = Column(String(100), nullable=False, default="Monarch Agent")
    persona = Column(Text, nullable=False, default="You are a helpful AI assistant.")
    tools = Column(JSON, nullable=True, default=[]) # Store tool definitions
    current_task_id = Column(Integer, ForeignKey('background_task.id'), nullable=True)
    current_task = relationship("BackgroundTask", foreign_keys=[current_task_id])
    # New fields for agent state
    state = Column(JSON, default={}) # General purpose state
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

class AgentState(db.Model): # New Model
    __tablename__ = 'agent_state'
    id = Column(Integer, primary_key=True)
    key = Column(String(100), nullable=False, unique=True)
    value = Column(JSON, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())

class BackgroundTask(db.Model): # New Model
    __tablename__ = 'background_task'
    id = Column(Integer, primary_key=True)
    name = Column(String(100), nullable=False)
    status = Column(String(50), default="pending") # e.g., pending, in_progress, completed, failed
    result = Column(Text, nullable=True)
    created_at = Column(DateTime(timezone=True), server_default=func.now())
    updated_at = Column(DateTime(timezone=True), onupdate=func.now())
    agent_profile_id = Column(Integer, ForeignKey('agent_profile.id'), nullable=True) # Link to agent if needed

# --- Pydantic Models for API validation ---
class Message(BaseModel): # Moved from script, standard Pydantic model
    role: str
    content: str
    tool_calls: Optional[List[Dict[str, Any]]] = None

# --- Tool Discovery (from agent_core.py) ---
def discover_tools(module_or_object: Any) -> List[Dict[str, Any]]:
    """
    Discovers tools (functions with Pydantic schemas) in a given module or object.
    """
    discovered_tools = []
    for name, func in inspect.getmembers(module_or_object, inspect.isfunction):
        if hasattr(func, 'tool_schema'):
            schema = func.tool_schema.schema()
            discovered_tools.append({
                "type": "function",
                "function": {
                    "name": name,
                    "description": schema.get("description", ""),
                    "parameters": schema
                }
            })
    return discovered_tools

# --- Built-in Tools ---
class SetAgentStateSchema(BaseModel):
    key: str = Field(..., description="The key of the state variable to set.")
    value: Any = Field(..., description="The value to set for the state variable.")

def set_agent_state_tool(key: str, value: Any) -> str:
    """Sets a value in the agent's state."""
    try:
        state_item = AgentState.query.filter_by(key=key).first()
        if state_item:
            state_item.value = value
        else:
            state_item = AgentState(key=key, value=value)
            db.session.add(state_item)
        db.session.commit()
        return f"State variable '{key}' set successfully."
    except Exception as e:
        db.session.rollback()
        return f"Error setting state variable '{key}': {str(e)}"
set_agent_state_tool.tool_schema = SetAgentStateSchema

class GetAgentStateSchema(BaseModel):
    key: str = Field(..., description="The key of the state variable to retrieve.")

def get_agent_state_tool(key: str) -> Any:
    """Retrieves a value from the agent's state."""
    state_item = AgentState.query.filter_by(key=key).first()
    if state_item:
        return state_item.value
    else:
        return f"State variable '{key}' not found."
get_agent_state_tool.tool_schema = GetAgentStateSchema

# --- RAG Tool ---
KNOWLEDGE_BASE_PATH = 'knowledge_base' # Defined as per instructions

class RetrieveFromKnowledgeBaseSchema(BaseModel):
    query: str = Field(..., description="The query to search for in the knowledge base.")
    top_k: int = Field(default=3, description="Number of top results to retrieve.")

def retrieve_from_knowledge_base(query: str, top_k: int = 3) -> List[str]:
    """
    Retrieves relevant chunks from the knowledge base using Ollama embeddings.
    """
    if not os.path.exists(KNOWLEDGE_BASE_PATH):
        return ["Knowledge base directory not found."]

    all_chunks = []
    for filename in os.listdir(KNOWLEDGE_BASE_PATH):
        if filename.endswith(".txt"): # Assuming knowledge is stored in .txt files
            filepath = os.path.join(KNOWLEDGE_BASE_PATH, filename)
            with open(filepath, 'r', encoding='utf-8') as f:
                content = f.read()
                # Simple chunking by paragraph, can be improved
                paragraphs = content.split('\n\n')
                for para_idx, para in enumerate(paragraphs):
                    if para.strip():
                         all_chunks.append({"text": para.strip(), "source": filename, "paragraph": para_idx})

    if not all_chunks:
        return ["No content found in the knowledge base."]

    # Generate embeddings for all chunks
    chunk_embeddings = []
    for chunk in all_chunks:
        try:
            response = ollama.embeddings(model='mxbai-embed-large', prompt=chunk["text"])
            chunk_embeddings.append({"chunk": chunk, "embedding": response['embedding']})
        except Exception as e:
            print(f"Error generating embedding for chunk from {chunk['source']}: {e}")
            continue

    if not chunk_embeddings:
        return ["Could not generate embeddings for knowledge base content."]

    # Generate embedding for the query
    try:
        query_embedding_response = ollama.embeddings(model='mxbai-embed-large', prompt=query)
        query_embedding = query_embedding_response['embedding']
    except Exception as e:
        return [f"Error generating embedding for query: {str(e)}"]

    # Calculate similarity (cosine similarity)
    # Note: ollama client doesn't provide a direct similarity function.
    # This requires numpy or similar for efficient dot product. For simplicity,
    # we'll skip the actual math here and return a placeholder.
    # In a real scenario, you'd use numpy:
    # import numpy as np
    # similarities = [np.dot(ce["embedding"], query_embedding) / (np.linalg.norm(ce["embedding"]) * np.linalg.norm(query_embedding)) for ce in chunk_embeddings]
    # For now, just returning the first few chunks as a mock retrieval

    # Mocking similarity scoring and ranking for now
    # Replace with actual cosine similarity calculation if numpy is available
    # For demonstration, we'll just return the text of the first few chunks

    # Simulate relevance scoring (replace with actual cosine similarity if numpy is added)
    # This is a simplified example. Real RAG needs proper similarity calculation.
    # We will return chunks that contain words from the query for this example.

    relevant_chunks = []
    query_words = set(query.lower().split())
    for ce in chunk_embeddings:
        chunk_text_lower = ce["chunk"]["text"].lower()
        # Basic keyword matching for demonstration
        if any(word in chunk_text_lower for word in query_words):
            relevant_chunks.append(ce["chunk"])
            if len(relevant_chunks) >= top_k:
                break

    if not relevant_chunks:
        return ["No relevant information found for your query."]

    return [f"Source: {chunk['source']}, Paragraph {chunk['paragraph']}: {chunk['text']}" for chunk in relevant_chunks[:top_k]]

retrieve_from_knowledge_base.tool_schema = RetrieveFromKnowledgeBaseSchema


# --- Background Task Management ---
def create_background_task(name: str, agent_profile_id: Optional[int] = None) -> BackgroundTask:
    new_task = BackgroundTask(name=name, agent_profile_id=agent_profile_id)
    db.session.add(new_task)
    db.session.commit()
    return new_task

def update_background_task(task_id: int, status: str, result: Optional[str] = None):
    task = BackgroundTask.query.get(task_id)
    if task:
        task.status = status
        if result is not None:
            task.result = result
        task.updated_at = func.now()
        db.session.commit()

def simulate_long_running_process(task_id: int, duration: int):
    update_background_task(task_id, status="in_progress")
    print(f"Task {task_id}: Starting long running process for {duration} seconds.")
    time.sleep(duration) # Simulate work
    result_message = f"Task {task_id} completed after {duration} seconds."
    update_background_task(task_id, status="completed", result=result_message)
    print(result_message)


# --- Core Ollama Call Function ---
def call_ollama(model: str, messages: List[Dict[str, Any]], stream: bool = False, tools: Optional[List[Dict[str, Any]]] = None) -> Union[Dict[str, Any], Any]:
    """
    Calls the Ollama API with the given model, messages, and optional tools.
    Handles streaming and non-streaming responses.
    """
    options = {
        "temperature": 0.8, # Example option
        # "top_p": 0.9,
        # "num_ctx": 4096 # Example, adjust as needed
    }
    try:
        if tools:
            response = ollama.chat(
                model=model,
                messages=messages,
                tools=tools,
                stream=stream,
                options=options
            )
        else:
            response = ollama.chat(
                model=model,
                messages=messages,
                stream=stream,
                options=options
            )
        return response
    except Exception as e:
        print(f"Error calling Ollama: {e}")
        # Fallback or error handling:
        # Check if it's a model not found error, try a default model
        if "model not found" in str(e).lower() and model != "llama3":
            print(f"Model {model} not found, trying with llama3...")
            try:
                if tools:
                    response = ollama.chat(model='llama3', messages=messages, tools=tools, stream=stream, options=options)
                else:
                    response = ollama.chat(model='llama3', messages=messages, stream=stream, options=options)
                return response
            except Exception as e2:
                print(f"Error calling Ollama with fallback model llama3: {e2}")
                return {"error": str(e2), "message": "Failed to call Ollama with primary and fallback models."}

        return {"error": str(e), "message": "Failed to call Ollama."}


# --- API Routes ---
@app.route('/')
def serve_frontend():
    return send_from_directory('../frontend/static', 'index.html')

@app.route('/<path:path>')
def serve_static_files(path):
    return send_from_directory('../frontend/static', path)

@app.route('/api/chat', methods=['POST'])
def chat_endpoint():
    data = request.json
    user_message_content = data.get('message')
    chat_history: List[Dict[str, Any]] = data.get('history', [])
    selected_model = data.get('model', 'llama3') # Default to llama3 if not specified

    # Get current agent profile (assuming one for now)
    agent_profile = AgentProfile.query.first()
    if not agent_profile:
        return jsonify({"error": "Agent profile not found. Please initialize."}), 500

    # Construct messages for Ollama
    messages = [{"role": "system", "content": agent_profile.persona}]
    messages.extend(chat_history)
    messages.append({"role": "user", "content": user_message_content})

    # Discover available tools
    # Tool functions should be defined globally or in an imported module
    available_tools_definitions = discover_tools(globals()) # Pass current module
    # Or, if tools are in a specific class/object:
    # from agent_tools import MyAgentTools
    # available_tools_definitions = discover_tools(MyAgentTools)

    # --- Advanced Orchestrator Logic ---
    MAX_TOOL_ITERATIONS = 5
    for _ in range(MAX_TOOL_ITERATIONS):
        print(f"Iteration {_ + 1}: Sending messages to Ollama: {messages}")
        if not available_tools_definitions: # If no tools, simple chat
             print("No tools defined for the agent. Proceeding with simple chat.")
             response = call_ollama(model=selected_model, messages=messages)
             if response and response.get('message'):
                return jsonify(response['message'])
             else:
                return jsonify({"error": "Failed to get response from Ollama", "details": response}), 500

        response = call_ollama(model=selected_model, messages=messages, tools=available_tools_definitions)

        if response and response.get('error'):
            return jsonify(response), 500

        if not response or 'message' not in response:
             print(f"No 'message' in Ollama response: {response}")
             return jsonify({"error": "Invalid response from Ollama", "details": response}), 500

        ai_message = response['message']
        messages.append(ai_message) # Add AI's response to history

        if ai_message.get('tool_calls'):
            tool_calls = ai_message['tool_calls']
            tool_results = []

            for tool_call in tool_calls:
                tool_name = tool_call['function']['name']
                tool_args_str = tool_call['function']['arguments']

                print(f"Tool call: {tool_name}, Args_str: {tool_args_str}")

                try:
                    tool_args = json.loads(tool_args_str)
                except json.JSONDecodeError as e:
                    print(f"Error decoding JSON arguments for tool {tool_name}: {e}")
                    print(f"Problematic string: {tool_args_str}")
                    tool_results.append({
                        "tool_call_id": tool_call['id'],
                        "output": f"Error: Invalid JSON arguments provided: {tool_args_str}"
                    })
                    continue # Skip to next tool call

                # Dynamically call the tool function
                tool_function = globals().get(tool_name)
                if tool_function and callable(tool_function):
                    try:
                        print(f"Executing tool: {tool_name} with args: {tool_args}")
                        # Ensure all required arguments are present
                        sig = inspect.signature(tool_function)
                        missing_args = [p for p in sig.parameters if p not in tool_args and sig.parameters[p].default == inspect.Parameter.empty]
                        if missing_args:
                             result = f"Error: Missing required arguments for tool {tool_name}: {', '.join(missing_args)}"
                        else:
                            result = tool_function(**tool_args)

                        # If the result is not a string, convert it (e.g., for get_agent_state_tool)
                        if not isinstance(result, str):
                            result = json.dumps(result)

                    except Exception as e:
                        result = f"Error executing tool {tool_name}: {str(e)}"
                    print(f"Tool {tool_name} result: {result}")
                else:
                    result = f"Error: Tool '{tool_name}' not found or not callable."

                tool_results.append({
                    "tool_call_id": tool_call['id'],
                    "output": result
                })

            # Add tool results to messages for the next iteration
            messages.append({
                "role": "tool",
                "content": json.dumps(tool_results) # Ensure content is a JSON string
            })
            # Continue to the next iteration of the loop to let the LLM process tool results

        else: # No tool calls, AI response is final for this turn
            return jsonify(ai_message)

    # If loop finishes, it means max iterations were hit
    return jsonify({"role": "assistant", "content": "Max tool iterations reached. Please try again or rephrase your request."})


@app.route('/api/agent/profile', methods=['GET', 'POST'])
def agent_profile_route():
    if request.method == 'GET':
        profile = AgentProfile.query.first()
        if profile:
            return jsonify({
                "name": profile.name,
                "persona": profile.persona,
                "tools": profile.tools,
                "state": profile.state
            })
        return jsonify({"message": "Profile not set"}), 404

    if request.method == 'POST':
        data = request.json
        profile = AgentProfile.query.first()
        if not profile:
            profile = AgentProfile()
            db.session.add(profile)

        profile.name = data.get('name', profile.name)
        profile.persona = data.get('persona', profile.persona)
        profile.tools = data.get('tools', profile.tools) # Expecting list of tool definitions
        profile.state = data.get('state', profile.state) # Update agent state
        profile.updated_at = func.now()
        db.session.commit()
        return jsonify({"message": "Profile updated successfully"})

# New API endpoint for background tasks
@app.route('/api/tasks', methods=['GET', 'POST'])
def manage_tasks():
    if request.method == 'GET':
        tasks = BackgroundTask.query.all()
        return jsonify([{
            "id": task.id,
            "name": task.name,
            "status": task.status,
            "result": task.result,
            "created_at": task.created_at.isoformat() if task.created_at else None,
            "updated_at": task.updated_at.isoformat() if task.updated_at else None
        } for task in tasks])

    if request.method == 'POST':
        data = request.json
        task_name = data.get('name', 'Unnamed Task')
        duration = data.get('duration', 10) # Duration for simulated task

        # Example: Create a task and run it in a background thread
        new_task = create_background_task(name=task_name)

        # Start the simulation in a new thread
        thread = threading.Thread(target=simulate_long_running_process, args=(new_task.id, duration))
        thread.start()

        return jsonify({"message": "Task created and started", "task_id": new_task.id}), 201

@app.route('/api/tasks/<int:task_id>', methods=['GET'])
def get_task_status(task_id):
    task = BackgroundTask.query.get(task_id)
    if task:
        return jsonify({
            "id": task.id,
            "name": task.name,
            "status": task.status,
            "result": task.result,
            "created_at": task.created_at.isoformat() if task.created_at else None,
            "updated_at": task.updated_at.isoformat() if task.updated_at else None
        })
    return jsonify({"message": "Task not found"}), 404

# New API endpoint for general config (e.g., available models)
@app.route('/api/config', methods=['GET'])
def get_config():
    try:
        # Fetch available local models from Ollama
        ollama_models = ollama.list()
        local_model_names = [model['name'] for model in ollama_models.get('models', [])]
    except Exception as e:
        print(f"Could not connect to Ollama to fetch models: {e}")
        local_model_names = ["llama3 (default, if Ollama offline)"] # Fallback

    return jsonify({
        "available_models": local_model_names,
        "knowledge_base_path": app.config['KNOWLEDGE_BASE_PATH'],
        "upload_folder": app.config['UPLOAD_FOLDER']
    })


# --- Initialization ---
def init_db(app_context):
    with app_context:
        db.create_all()
        # Create default agent profile if it doesn't exist
        if not AgentProfile.query.first():
            default_tools = discover_tools(globals()) # Discover all tools in current scope
            # Filter out tools that are not meant for the agent directly if necessary
            # For now, add all discovered tools
            profile = AgentProfile(
                name="Monarch Agent",
                persona="You are Monarch, a helpful AI assistant specializing in software development and task automation. You have access to a variety of tools to help users. Be concise and proactive.",
                tools=default_tools, # Store discovered tools
                state={"greeting_enabled": True} # Example initial state
            )
            db.session.add(profile)
            db.session.commit()
            print("Default agent profile created.")

        # Ensure knowledge base and upload directories exist
        if not os.path.exists(app.config['KNOWLEDGE_BASE_PATH']):
            os.makedirs(app.config['KNOWLEDGE_BASE_PATH'])
            print(f"Created knowledge base directory: {app.config['KNOWLEDGE_BASE_PATH']}")
        if not os.path.exists(app.config['UPLOAD_FOLDER']):
            os.makedirs(app.config['UPLOAD_FOLDER'])
            print(f"Created upload folder: {app.config['UPLOAD_FOLDER']}")

if __name__ == '__main__':
    init_db(app.app_context())
    app.run(debug=True, port=5001, host='0.0.0.0')
