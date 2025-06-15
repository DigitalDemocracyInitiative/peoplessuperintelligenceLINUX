import json
from flask import Blueprint, request, jsonify
import datetime # Assuming Message model uses datetime


# --- Placeholder/Assumed External Functions and Variables ---
# These would be defined or imported in the actual backend/app.py

# Injected variables (as per the subtask description)
ORCHESTRATOR_SYSTEM_PROMPT = "ORCHESTRATOR_SYSTEM_PROMPT_PLACEHOLDER"
AVAILABLE_TOOLS_AND_LLMS = {"tools": [], "llms": []} # Placeholder

# Hypothetical Ollama call function
def call_ollama(model_name, prompt, history=None):
    print(f"Attempting to call Ollama with model: {model_name}")
    # Simulate LLM call
    if model_name == "mistral" and "ORCHESTRATOR_SYSTEM_PROMPT_PLACEHOLDER" in prompt:
        # Simulate orchestrator response
        if "read test.txt" in prompt:
            return json.dumps({
                "action_type": "tool_call",
                "details": {"tool_name": "read_file", "filename": "test.txt"}
            })
        elif "write 'hello' to new.txt" in prompt:
            return json.dumps({
                "action_type": "tool_call",
                "details": {"tool_name": "write_file", "filename": "new.txt", "content": "hello"}
            })
        elif "summarize doc.pdf" in prompt:
             return json.dumps({
                "action_type": "tool_call",
                "details": {"tool_name": "document_analysis", "filename": "doc.pdf", "analysis_query": "summarize"}
            })
        elif "generate python code for fibonacci" in prompt:
            return json.dumps({
                "action_type": "llm_call",
                "details": {"llm_model": "deepseek-coder", "sub_prompt": "generate python code for fibonacci"}
            })
        elif "explain black holes" in prompt:
            return json.dumps({
                "action_type": "llm_call",
                "details": {"llm_model": "mistral", "sub_prompt": "explain black holes"}
            })
        else: # Default for orchestrator if nothing matches
            return json.dumps({
                "action_type": "llm_call",
                "details": {"llm_model": "mistral", "sub_prompt": "Default fallback: " + prompt.splitlines()[-1]}
            })
    elif model_name == "deepseek-coder":
        return f"// Deepseek-coder generated code for: {prompt}"
    elif model_name == "mistral":
        return f"Mistral general response for: {prompt}"
    return "Error: Model not recognized or simulated call failed."

# Placeholder tool functions
def read_file_tool(filename):
    if filename == "test.txt":
        return {"success": True, "content": "Content of test.txt", "error": None}
    return {"success": False, "content": None, "error": f"File '{filename}' not found."}

def write_file_tool(filename, content):
    # Simulate file writing
    return {"success": True, "message": f"Content written to '{filename}'.", "error": None}

def document_analysis_tool(filename=None, document_content=None, analysis_query=None):
    doc_source = filename if filename else "provided text"
    if not doc_source and not document_content:
        return {"success": False, "result": None, "error": "No document provided for analysis."}
    return {"success": True, "result": f"Analysis of '{doc_source}' for query '{analysis_query}': Key insights found.", "error": None}

# Placeholder database models and functions
class Message: # Simplified representation
    def __init__(self, user_id, chat_id, content, role, agent_action=None, tool_details=None, system_info_message=None, timestamp=None):
        self.user_id = user_id
        self.chat_id = chat_id
        self.content = content
        self.role = role # 'user', 'assistant', 'system'
        self.agent_action = agent_action
        self.tool_details = tool_details # JSON string or dict
        self.system_info_message = system_info_message
        self.timestamp = timestamp or datetime.datetime.utcnow()

    def to_dict(self): # To simulate how it might be stored or returned
        return self.__dict__

# Placeholder DB interaction
DB_MESSAGES = [] # In-memory list to simulate DB

def add_message_to_db(message_obj):
    DB_MESSAGES.append(message_obj)
    print(f"DB: Added message - Role: {message_obj.role}, Content: {message_obj.content}, Action: {message_obj.agent_action}")

def get_chat_history_from_db(chat_id, limit=10):
    # Simulate fetching and ordering history
    return sorted([m for m in DB_MESSAGES if m.chat_id == chat_id], key=lambda x: x.timestamp, reverse=True)[:limit]

# --- End of Placeholders ---


# Define a Blueprint for API routes if this were part of a larger app structure
# For standalone, you'd use app.route directly.
# For this task, let's assume it's part of a Blueprint.
api_chat_blueprint = Blueprint('api_chat', __name__)

@api_chat_blueprint.route('/api/chat', methods=['POST'])
def api_chat_route():
    data = request.get_json()
    if not data:
        return jsonify({"error": "Invalid JSON payload"}), 400

    user_id = data.get('user_id', 'default_user') # Assuming user_id is part of the request
    chat_id = data.get('chat_id', 'default_chat') # Assuming chat_id for session management
    user_message_content = data.get('message')

    if not user_message_content:
        return jsonify({"error": "Missing 'message' in request"}), 400

    # 1. Save user message to DB
    user_message_obj = Message(user_id=user_id, chat_id=chat_id, content=user_message_content, role='user')
    add_message_to_db(user_message_obj)

    # 2. Retrieve chat history (condensed for orchestrator)
    # For the orchestrator, we might want a very concise history, e.g., last few turns.
    # For the target LLM, we might want a more complete history.
    raw_history = get_chat_history_from_db(chat_id, limit=10) # Get more for target LLM

    # Condense history for orchestrator: e.g., just user/assistant messages
    condensed_history_for_orchestrator = []
    for msg_obj in reversed(raw_history): # chronological
        if msg_obj.role in ['user', 'assistant']:
            condensed_history_for_orchestrator.append({"role": msg_obj.role, "content": msg_obj.content})

    # History for target LLMs (could be different, more detailed)
    history_for_target_llm = condensed_history_for_orchestrator # Keep it same for this example

    # 3. Construct prompt for Orchestrator LLM
    orchestrator_prompt_parts = [
        ORCHESTRATOR_SYSTEM_PROMPT,
        "\n\nAVAILABLE_TOOLS_AND_LLMS:\n" + json.dumps(AVAILABLE_TOOLS_AND_LLMS, indent=2),
        "\n\nCHAT_HISTORY (condensed):\n" + json.dumps(condensed_history_for_orchestrator[-5:]), # last 5 exchanges
        "\n\nUSER_MESSAGE:\n" + user_message_content,
        "\n\nBased on the user message, available tools, LLMs, and chat history, what is the next action? Respond in JSON format as specified in the system prompt."
    ]
    orchestrator_prompt = "\n".join(orchestrator_prompt_parts)

    # 4. Call Orchestrator LLM
    ai_response_text = "An error occurred." # Default response
    agent_action = "orchestrator_mistral_failed"
    tool_details_for_response = None
    system_info_message_content = None # For messages like "Orchestrator selected..."

    try:
        orchestrator_response_raw = call_ollama("mistral", orchestrator_prompt, history=[]) # Orchestrator usually doesn't need its own history

        # 5. Parse JSON response from orchestrator
        try:
            orchestrator_decision = json.loads(orchestrator_response_raw)
            action_type = orchestrator_decision.get("action_type")
            details = orchestrator_decision.get("details", {})
            agent_action = f"orchestrator_mistral_success_{action_type}"

        except json.JSONDecodeError as e:
            print(f"Error: Failed to parse orchestrator JSON response: {e}")
            print(f"Raw response was: {orchestrator_response_raw}")
            system_info_message_content = f"System Error: Orchestrator response was not valid JSON. Raw: {orchestrator_response_raw}"
            # Fallback: call general LLM
            ai_response_text = call_ollama("mistral", user_message_content, history=history_for_target_llm)
            agent_action = "llm_mistral_fallback_json_error"
            # Save system error message
            system_error_msg_obj = Message(user_id=user_id, chat_id=chat_id, content=system_info_message_content, role='system', agent_action='system_error')
            add_message_to_db(system_error_msg_obj)


        # 6. Implement logic based on parsed action_type
        if action_type == "tool_call":
            tool_name = details.get("tool_name")
            system_info_message_content = f"Orchestrator selected tool: {tool_name}."
            print(system_info_message_content) # Log to console
            # Save system message about orchestrator decision
            orch_decision_msg_obj = Message(user_id=user_id, chat_id=chat_id, content=system_info_message_content, role='system', agent_action=f"orchestrator_tool_{tool_name}")
            add_message_to_db(orch_decision_msg_obj)

            tool_output_message = "" # For the user
            tool_success_status = "failed"

            if tool_name == "read_file":
                filename = details.get("filename")
                if filename:
                    result = read_file_tool(filename)
                    if result["success"]:
                        ai_response_text = f"Successfully read '{filename}'. Content:\n{result['content']}"
                        tool_output_message = f"Tool Used: read_file. File: {filename}. Status: Success."
                        tool_success_status = "success"
                    else:
                        ai_response_text = f"Error reading file '{filename}': {result['error']}"
                        tool_output_message = f"Tool Used: read_file. File: {filename}. Status: Failed. Error: {result['error']}"
                    tool_details_for_response = {"tool_name": tool_name, "filename": filename, "success": result["success"], "error": result.get("error")}
                else:
                    ai_response_text = "Error: 'filename' not provided for read_file tool."
                    tool_output_message = "Tool Used: read_file. Status: Failed. Error: Missing filename."

            elif tool_name == "write_file":
                filename = details.get("filename")
                content = details.get("content")
                if filename and content is not None:
                    result = write_file_tool(filename, content)
                    if result["success"]:
                        ai_response_text = f"Successfully wrote to '{filename}'."
                        tool_output_message = f"Tool Used: write_file. File: {filename}. Status: Success."
                        tool_success_status = "success"
                    else:
                        ai_response_text = f"Error writing to file '{filename}': {result['error']}"
                        tool_output_message = f"Tool Used: write_file. File: {filename}. Status: Failed. Error: {result['error']}"
                    tool_details_for_response = {"tool_name": tool_name, "filename": filename, "success": result["success"], "error": result.get("error")}
                else:
                    ai_response_text = "Error: 'filename' or 'content' not provided for write_file tool."
                    tool_output_message = "Tool Used: write_file. Status: Failed. Error: Missing filename or content."

            elif tool_name == "document_analysis":
                filename = details.get("filename")
                doc_content = details.get("document_content") # Orchestrator might pass this
                analysis_query = details.get("analysis_query")
                if (filename or doc_content) and analysis_query:
                    result = document_analysis_tool(filename=filename, document_content=doc_content, analysis_query=analysis_query)
                    if result["success"]:
                        ai_response_text = f"Document Analysis Result: {result['result']}"
                        tool_output_message = f"Tool Used: document_analysis. Source: {filename if filename else 'text'}. Query: {analysis_query}. Status: Success."
                        tool_success_status = "success"
                    else:
                        ai_response_text = f"Error in document analysis: {result['error']}"
                        tool_output_message = f"Tool Used: document_analysis. Source: {filename if filename else 'text'}. Query: {analysis_query}. Status: Failed. Error: {result['error']}"
                    tool_details_for_response = {"tool_name": tool_name, "filename": filename, "document_content_provided": bool(doc_content), "analysis_query": analysis_query, "success": result["success"], "error": result.get("error")}
                else:
                    ai_response_text = "Error: Missing parameters for document_analysis tool (filename/document_content or analysis_query)."
                    tool_output_message = "Tool Used: document_analysis. Status: Failed. Error: Missing parameters."
            else:
                ai_response_text = f"Error: Unknown tool '{tool_name}' selected by orchestrator."
                tool_output_message = f"Tool Used: Unknown ({tool_name}). Status: Failed. Error: Orchestrator selected an unrecognized tool."

            agent_action = f"tool_{tool_name}_{tool_success_status}"
            # Save tool usage system message
            tool_usage_msg_obj = Message(user_id=user_id, chat_id=chat_id, content=tool_output_message, role='system', agent_action=agent_action, tool_details=tool_details_for_response)
            add_message_to_db(tool_usage_msg_obj)


        elif action_type == "llm_call":
            llm_model = details.get("llm_model")
            sub_prompt = details.get("sub_prompt")
            system_info_message_content = f"Orchestrator selected LLM: {llm_model} with sub-prompt: '{sub_prompt[:50]}...'"
            print(system_info_message_content) # Log to console
            # Save system message about orchestrator decision
            orch_decision_msg_obj = Message(user_id=user_id, chat_id=chat_id, content=system_info_message_content, role='system', agent_action=f"orchestrator_llm_{llm_model}")
            add_message_to_db(orch_decision_msg_obj)

            if llm_model and sub_prompt:
                try:
                    ai_response_text = call_ollama(llm_model, sub_prompt, history=history_for_target_llm)
                    agent_action = f"llm_{llm_model}_success"
                except Exception as e:
                    print(f"Error calling target LLM {llm_model}: {e}")
                    ai_response_text = f"Sorry, there was an error contacting the {llm_model} model."
                    agent_action = f"llm_{llm_model}_failed"
                    # Save system error message for this failure
                    llm_fail_msg_obj = Message(user_id=user_id, chat_id=chat_id, content=f"Failed to get response from {llm_model}: {e}", role='system', agent_action=agent_action)
                    add_message_to_db(llm_fail_msg_obj)
            else:
                ai_response_text = "Error: LLM model or sub-prompt not specified by orchestrator."
                agent_action = "llm_call_missing_details"
                # Fallback to general LLM if details are missing
                ai_response_text = call_ollama("mistral", user_message_content, history=history_for_target_llm)
                agent_action = "llm_mistral_fallback_bad_orchestrator_llm_call"


        elif not action_type and system_info_message_content: # This means JSON parsing failed earlier, and system message was set
            pass # ai_response_text and agent_action already set by JSON parsing error handler

        else: # Unrecognized action_type or other orchestrator logic error
            system_info_message_content = f"System Error: Orchestrator returned unrecognized action_type '{action_type}' or missing details."
            print(system_info_message_content)
            # Save system error message
            unrec_action_msg_obj = Message(user_id=user_id, chat_id=chat_id, content=system_info_message_content, role='system', agent_action='orchestrator_unrecognized_action')
            add_message_to_db(unrec_action_msg_obj)

            # Fallback to general LLM
            ai_response_text = call_ollama("mistral", user_message_content, history=history_for_target_llm)
            agent_action = "llm_mistral_fallback_unrecognized_action"


    except Exception as e:
        print(f"Error in /api/chat main try block: {e}")
        ai_response_text = "An unexpected error occurred in the chat processing."
        agent_action = "chat_api_exception"
        # Save system error message
        api_err_msg_obj = Message(user_id=user_id, chat_id=chat_id, content=f"API Exception: {e}", role='system', agent_action=agent_action)
        add_message_to_db(api_err_msg_obj)

    # 7. Save AI response to DB
    ai_message_obj = Message(
        user_id=user_id,
        chat_id=chat_id,
        content=ai_response_text,
        role='assistant',
        agent_action=agent_action,
        tool_details=json.dumps(tool_details_for_response) if tool_details_for_response else None,
        system_info_message=system_info_message_content # This is more for the AI's own message if it's a system response
    )
    add_message_to_db(ai_message_obj)

    # 8. Return response to frontend
    response_payload = {
        "ai_response_text": ai_response_text,
        "agent_action": agent_action,
        "tool_details": tool_details_for_response,
        "chat_id": chat_id, # Return chat_id so frontend can keep track
        "message_id": str(ai_message_obj.timestamp) # Example ID
    }
    if system_info_message_content and action_type not in ["tool_call", "llm_call"]: # If it was a system-level error message directly shown to user
        response_payload["system_info"] = system_info_message_content

    return jsonify(response_payload)

# Example of how to register this blueprint in a main app.py
# from flask import Flask
# app = Flask(__name__)
# app.register_blueprint(api_chat_blueprint)
#
# # Inject actual ORCHESTRATOR_SYSTEM_PROMPT and AVAILABLE_TOOLS_AND_LLMS
# # import orchestrator_prompt_module
# # import tools_and_llms_module
# # ORCHESTRATOR_SYSTEM_PROMPT = orchestrator_prompt_module.ORCHESTRATOR_SYSTEM_PROMPT
# # AVAILABLE_TOOLS_AND_LLMS = tools_and_llms_module.AVAILABLE_TOOLS_AND_LLMS
#
# if __name__ == '__main__':
#     # This is just for testing the route in isolation if needed
#     # Real app would have its own run configuration
#     # Ensure ORCHESTRATOR_SYSTEM_PROMPT and AVAILABLE_TOOLS_AND_LLMS are loaded
#     # For testing, could load them from the files generated in previous steps.
#     try:
#         from orchestrator_prompt import ORCHESTRATOR_SYSTEM_PROMPT as OSP_REAL
#         from tools_and_llms import AVAILABLE_TOOLS_AND_LLMS as ATAL_REAL
#         ORCHESTRATOR_SYSTEM_PROMPT = OSP_REAL
#         AVAILABLE_TOOLS_AND_LLMS = ATAL_REAL
#         print("Successfully loaded real prompts and tool/LLM definitions for testing.")
#     except ImportError:
#         print("Could not load real prompts/tools for testing. Using placeholders.")
#
#     # A simple test client:
#     # with app.test_client() as client:
#     #     response = client.post('/api/chat', json={'message': 'read test.txt', 'chat_id': 'test_chat_1'})
#     #     print("Test Response:", response.get_json())
#     #     response = client.post('/api/chat', json={'message': 'explain black holes', 'chat_id': 'test_chat_1'})
#     #     print("Test Response:", response.get_json())
#     pass
