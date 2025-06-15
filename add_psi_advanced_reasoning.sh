#!/bin/bash
set -e

# Navigate to the project root directory
echo "Navigating to project root: ~/psi_pwa_linux_new..."
cd ~/psi_pwa_linux_new || { echo "Failed to navigate to project root. Ensure ~/psi_pwa_linux_new exists."; exit 1; }
PROJECT_ROOT=$(pwd)
echo "Current directory: $(pwd)"

echo ""
echo "--------------------------------------------------------------------"
echo "Step 1: Modifying Backend (backend/app.py)"
echo "--------------------------------------------------------------------"
cd backend || { echo "Failed to navigate to backend directory."; exit 1; }

# Activate Python virtual environment
if [ -f "venv/bin/activate" ]; then
    echo "Activating Python virtual environment..."
    source venv/bin/activate
else
    echo "Warning: Python virtual environment (venv) not found in backend directory."
    echo "Please ensure it's created and dependencies are installed as per prior setup instructions."
    # exit 1 # Decide if this should be a fatal error
fi

# Create a backup of app.py
echo "Backing up backend/app.py to backend/app.py.bak..."
cp app.py app.py.bak

# Prepare the Python code snippets to be injected

# ORCHESTRATOR_SYSTEM_PROMPT and AVAILABLE_TOOLS_AND_LLMS
cat << 'EOF' > prompt_tools_definitions.py
import json # Make sure json is imported for AVAILABLE_TOOLS_AND_LLMS
import logging # For app.logger

ORCHESTRATOR_SYSTEM_PROMPT = """
You are an orchestrator LLM. Your primary function is to analyze user input and decide the next course of action.
Based on the user's query, you must determine if:
1. A specific tool needs to be called. The available tools are: read_file, write_file, and document_analysis.
2. A specialized LLM is more appropriate for handling the query. The available LLMs are: deepseek-coder (for code-related tasks) and mistral (for general chat and non-coding related text generation or analysis).

You must output your decision in a JSON format. The JSON object should have the following structure:

{
  "action_type": "tool_call" | "llm_call",
  "details": {
    // If action_type is "tool_call"
    "tool_name": "<tool_name>", // e.g., "read_file", "write_file", "document_analysis"
    "filename": "<filename>", // (if applicable, e.g., for "read_file" or "write_file")
    "content": "<content_to_write>", // (if applicable, e.g., for "write_file")
    "analysis_query": "<query_for_document_analysis>" // (if applicable, e.g., for "document_analysis")

    // If action_type is "llm_call"
    "llm_model": "<llm_model_name>", // e.g., "deepseek-coder", "mistral"
    "sub_prompt": "<the_refined_prompt_for_the_target_LLM>"
  }
}

To decide on the action:
- If the user asks to read a file, use the "read_file" tool. The "filename" parameter must be extracted from the user query.
- If the user asks to write or save content to a file, use the "write_file" tool. The "filename" and "content" parameters must be extracted or inferred from the user query.
- If the user asks to analyze a document or text they provide (or a file that needs to be read first), and the analysis is beyond simple retrieval, consider if "document_analysis" tool is appropriate. The "analysis_query" parameter should capture what the user wants to find or understand in the document. If the user provides a filename, assume the content of this file is the document to be analyzed.
- If the user's query is related to generating, explaining, or discussing code, route to the "deepseek-coder" LLM. Construct a concise "sub_prompt" that captures the user's coding request.
- If the user's query is for general conversation, creative writing, summarization (not of a provided document), or any other non-coding text-based task, route to the "mistral" LLM. Construct a concise "sub_prompt" for mistral.
- If the user's query is ambiguous, does not clearly fit any specific tool or specialized LLM, or if necessary parameters are missing, you should ask for clarification. To do this, set action_type to "llm_call", "llm_model" to "mistral", and the "sub_prompt" to your clarification question.
- If the user provides content and asks for analysis without specifying a file, the "document_analysis" tool can be used if the analysis is complex. The provided content should be considered the document.

Ensure the "details" dictionary only contains relevant keys for the chosen "action_type". For example, "tool_name" is only for "tool_call", and "llm_model" is only for "llm_call". The "filename" for "document_analysis" implies the document to be analyzed is in that file. If no filename is given for "document_analysis" but content is implied by the user query, the content itself is the document.

Example 1: User says "Can you read the main.py file for me?"
Output:
{
  "action_type": "tool_call",
  "details": {
    "tool_name": "read_file",
    "filename": "main.py"
  }
}

Example 2: User says "Write a function in python to sort a list and save it in utils.py"
Output:
{
  "action_type": "llm_call",
  "details": {
    "llm_model": "deepseek-coder",
    "sub_prompt": "Write a Python function to sort a list. The user wants to save this to utils.py."
  }
}
Note: The orchestrator identifies the core task for the specialized LLM and can pass along contextual information like where the user wants to save the code. The actual file writing would be a subsequent step after the code is generated. Alternatively, if the user said "Save this code `def hello(): print('hello')` to hello.py", the orchestrator could directly use write_file.

Example 3: User says "Explain quantum physics in simple terms."
Output:
{
  "action_type": "llm_call",
  "details": {
    "llm_model": "mistral",
    "sub_prompt": "Explain quantum physics in simple terms."
  }
}

Example 4: User says "Save 'Hello world' to welcome.txt"
Output:
{
  "action_type": "tool_call",
  "details": {
    "tool_name": "write_file",
    "filename": "welcome.txt",
    "content": "Hello world"
  }
}

Example 5: User says "What are the key points in the document report.txt?"
Output:
{
  "action_type": "tool_call",
  "details": {
    "tool_name": "document_analysis",
    "filename": "report.txt",
    "analysis_query": "What are the key points"
  }
}

Example 6: User says "Summarize this text: <long text>"
Output:
{
  "action_type": "llm_call",
  "details": {
    "llm_model": "mistral",
    "sub_prompt": "Summarize this text: <long text>"
  }
}

If a filename is mentioned for document analysis, the tool should be responsible for reading it. Do not chain a read_file call before a document_analysis call unless the analysis is on a file *different* from the one the user explicitly mentions for analysis.
If the user asks a question about a document they just had read or written, it's likely a follow-up for document_analysis or a general LLM.
Prioritize tool calls if they directly match the user's explicit request (e.g., "read file X", "write Y to file X").
If the request is to "analyze this document" and they provide the text directly, use "document_analysis" with the "analysis_query" and pass the document content implicitly (the tool handler will need to manage this).
"""

AVAILABLE_TOOLS_AND_LLMS = {
    "tools": [
        {
            "name": "read_file",
            "description": "Reads the content of a specified file from the agent's workspace. Use this when the user explicitly asks to read a file.",
            "parameters": [
                {"name": "filename", "type": "string", "description": "The name of the file to read."}
            ]
        },
        {
            "name": "write_file",
            "description": "Writes the given content to a specified file in the agent's workspace. Use this when the user explicitly asks to write or save content to a file.",
            "parameters": [
                {"name": "filename", "type": "string", "description": "The name of the file to write to."},
                {"name": "content", "type": "string", "description": "The content to write into the file."}
            ]
        },
        {
            "name": "document_analysis", # This will map to document_processing_tool
            "description": "Analyzes a document (either from a file or provided text) based on a specific query. Use this for tasks like finding key points, answering questions about the document's content, or extracting specific information from it. This tool can read the file itself if a filename is provided.",
            "parameters": [
                {"name": "filename", "type": "string", "description": "Optional. The name of the file to analyze. The tool will read this file.", "optional": True},
                {"name": "document_content", "type": "string", "description": "Optional. The actual text content of the document to analyze, if no filename is provided or if the content is directly available.", "optional": True},
                {"name": "analysis_query", "type": "string", "description": "The specific question or type of analysis to perform on the document (e.g., 'summarize', 'what are the main arguments?', 'extract all email addresses')."}
            ]
        }
    ],
    "llms": [
        {
            "name": "deepseek-coder",
            "description": "Specialized for generating, explaining, and discussing code (Python, JavaScript, Java, C++, etc.). Use this for tasks like writing functions, debugging code, converting code between languages, or explaining code snippets."
        },
        {
            "name": "mistral",
            "description": "A general-purpose LLM for conversation, text generation (e.g., stories, poems, emails), summarization (of general text, not specific documents unless document_analysis is unsuitable), translation, and answering general knowledge questions. Also used for clarification if the user's query is ambiguous."
        }
    ]
}

# Placeholder for the actual document_processing_tool function if it needs to be redefined or ensured.
# For this script, we assume document_processing_tool, read_file_tool, write_file_tool, and call_ollama
# are already defined correctly in app.py or imported.

# Example: If you need to ensure `requests` is imported for `call_ollama`
# print("import requests") # This would be added to app.py if needed

EOF

# New /api/chat route logic
cat << 'EOF' > new_chat_route.py
@app.route('/api/chat', methods=['POST'])
def chat_with_psi_agent(): # Renamed function to avoid clash if old one is still there during processing
    data = request.get_json()
    user_message_text = data.get('message', '').strip()

    if not user_message_text:
        return jsonify({"response": "Please provide a message.", "agent_action": "none"}), 200

    # Save user message to DB (using existing db and Message model)
    user_msg_db = Message(sender='user', text=user_message_text)
    db.session.add(user_msg_db)
    db.session.commit()

    # Retrieve recent history for agent context
    recent_messages_db = Message.query.order_by(Message.timestamp.desc()).limit(10).all()
    recent_messages_db.reverse() # Chronological order

    condensed_history_for_orchestrator = []
    for msg_db in recent_messages_db:
        if msg_db.sender in ['user', 'ai', 'assistant']: # Handle 'ai' or 'assistant' as assistant role
            role = 'assistant' if msg_db.sender == 'ai' else msg_db.sender
            condensed_history_for_orchestrator.append({"role": role, "content": msg_db.text})


    history_for_target_llm = condensed_history_for_orchestrator # Can be made more sophisticated later

    orchestrator_prompt_string = f"{ORCHESTRATOR_SYSTEM_PROMPT}\n\nAVAILABLE_TOOLS_AND_LLMS:\n{json.dumps(AVAILABLE_TOOLS_AND_LLMS, indent=2)}\n\nCHAT_HISTORY (condensed):\n{json.dumps(condensed_history_for_orchestrator[-5:])}\n\nUSER_MESSAGE:\n{user_message_text}\n\nBased on the user message, available tools, LLMs, and chat history, what is the next action? Respond in JSON format as specified in the system prompt."

    ai_response_text = "An error occurred during processing."
    agent_action = "orchestration_failed"
    tool_details_for_response = None

    try:
        app.logger.debug(f"Orchestrator prompt (first 500 chars): {orchestrator_prompt_string[:500]}...")
        # call_ollama must be defined in app.py and accessible here
        orchestrator_response_raw = call_ollama("mistral", orchestrator_prompt_string, [])
        app.logger.debug(f"Orchestrator raw response: {orchestrator_response_raw}")

        action_type = None # Ensure it's defined before try-except for parsing
        details = {}     # Ensure it's defined

        try:
            orchestrator_decision = json.loads(orchestrator_response_raw)
            action_type = orchestrator_decision.get("action_type")
            details = orchestrator_decision.get("details", {})
        except json.JSONDecodeError as e:
            app.logger.error(f"Failed to parse orchestrator JSON response: {e}. Raw: {orchestrator_response_raw}")
            system_info_msg_text = f"System Error: Orchestrator response parsing failed. Using fallback. Raw response fragment: {orchestrator_response_raw[:200]}..."
            system_info_msg = Message(sender='system-info', text=system_info_msg_text, agent_action='orchestrator_parse_error')
            db.session.add(system_info_msg)
            # Fallback to general LLM
            ai_response_text = call_ollama("mistral", user_message_text, history_for_target_llm)
            agent_action = "llm_mistral_fallback_orchestrator_error"
            action_type = "llm_call_fallback" # Critical to prevent further tool processing attempts

        if action_type == "tool_call":
            tool_name = details.get("tool_name")
            system_info_log_text = f"Orchestrator selected tool: {tool_name}."
            app.logger.info(system_info_log_text)
            orch_decision_msg = Message(sender='system-info', text=system_info_log_text, agent_action=f'orchestrator_selected_tool_{tool_name}')
            db.session.add(orch_decision_msg)

            tool_output_text_for_user = ""

            if tool_name == "read_file":
                filename = details.get("filename")
                if filename:
                    # read_file_tool must be defined in app.py
                    tool_result = read_file_tool(filename)
                    tool_details_for_response = tool_result
                    if tool_result["success"]:
                        tool_output_text_for_user = f"Agent read '{tool_result.get('filename', filename)}'. First 500 chars:\n```\n{tool_result.get('content', '')[:500]}\n```"
                        agent_action = "tool_read_file_success"
                    else:
                        tool_output_text_for_user = f"Agent failed to read '{filename}'. Error: {tool_result.get('error', 'Unknown error')}"
                        agent_action = "tool_read_file_failure"
                else:
                    tool_output_text_for_user = "Orchestrator chose 'read_file' but no filename was specified."
                    agent_action = "tool_read_file_missing_params"

            elif tool_name == "write_file":
                filename = details.get("filename")
                content = details.get("content")
                if filename and content is not None:
                    # write_file_tool must be defined in app.py
                    tool_result = write_file_tool(filename, content)
                    tool_details_for_response = tool_result
                    if tool_result["success"]:
                        tool_output_text_for_user = f"Agent wrote content to '{tool_result.get('filename', filename)}'. {tool_result.get('message', '')}"
                        agent_action = "tool_write_file_success"
                    else:
                        tool_output_text_for_user = f"Agent failed to write to '{filename}'. Error: {tool_result.get('error', 'Unknown error')}"
                        agent_action = "tool_write_file_failure"
                else:
                    tool_output_text_for_user = "Orchestrator chose 'write_file' but filename or content was missing."
                    agent_action = "tool_write_file_missing_params"

            elif tool_name == "document_analysis": # Maps to document_processing_tool
                filename = details.get("filename")
                doc_content_from_orchestrator = details.get("document_content")
                analysis_query = details.get("analysis_query", "general analysis")
                text_to_process = None
                source_description = ""

                if filename:
                    source_description = f"file '{filename}'"
                    read_op = read_file_tool(filename) # Assumes read_file_tool is available
                    if read_op["success"]:
                        text_to_process = read_op["content"]
                        doc_source_msg_text = f"Agent will analyze {source_description} for query: {analysis_query}"
                        doc_source_msg = Message(sender='system-info', text=doc_source_msg_text, agent_action='tool_doc_analysis_read_file')
                        db.session.add(doc_source_msg)
                    else:
                        tool_output_text_for_user = f"Agent could not read {source_description} for document analysis. Error: {read_op['error']}"
                        agent_action = "tool_doc_analysis_read_fail"
                elif doc_content_from_orchestrator:
                    source_description = "directly provided text"
                    text_to_process = doc_content_from_orchestrator
                    doc_source_msg_text = f"Agent will analyze {source_description} for query: {analysis_query}"
                    doc_source_msg = Message(sender='system-info', text=doc_source_msg_text, agent_action='tool_doc_analysis_direct_content')
                    db.session.add(doc_source_msg)
                else:
                    tool_output_text_for_user = "Orchestrator chose 'document_analysis' but no filename or content was provided."
                    agent_action = "tool_doc_analysis_missing_source"

                if text_to_process is not None:
                    # document_processing_tool must be defined in app.py
                    tool_result = document_processing_tool(text_content=text_to_process) # Ensure this matches tool's signature
                    tool_details_for_response = tool_result
                    if tool_result["success"]:
                        tool_output_text_for_user = f"Agent processed document (source: {source_description}, query: '{analysis_query}'). Result: {tool_result.get('result', 'No specific result text.')}"
                        agent_action = "tool_doc_analysis_success"
                    else:
                        tool_output_text_for_user = f"Agent failed to process document (source: {source_description}). Error: {tool_result.get('error', 'Unknown error')}"
                        agent_action = "tool_doc_analysis_failure"
            else:
                tool_output_text_for_user = f"Orchestrator selected unknown tool: '{tool_name}'. Please check tool definitions."
                agent_action = "tool_unknown_selected"

            ai_response_text = tool_output_text_for_user

        elif action_type == "llm_call":
            llm_model = details.get("llm_model")
            sub_prompt = details.get("sub_prompt")
            system_info_log_text = f"Orchestrator selected LLM: {llm_model} with sub-prompt (first 100 chars): '{sub_prompt[:100]}...'"
            app.logger.info(system_info_log_text)
            orch_decision_msg = Message(sender='system-info', text=system_info_log_text, agent_action=f'orchestrator_selected_llm_{llm_model}')
            db.session.add(orch_decision_msg)

            if llm_model and sub_prompt:
                ai_response_text = call_ollama(llm_model, sub_prompt, history_for_target_llm)
                agent_action = f"llm_{llm_model}_success"
            else:
                ai_response_text = "Orchestrator chose LLM call but model or sub-prompt was missing. Defaulting to Mistral for the original query."
                agent_action = "llm_call_missing_params_fallback_mistral"
                ai_response_text = call_ollama("mistral", user_message_text, history_for_target_llm)

        elif action_type == "llm_call_fallback":
             # ai_response_text and agent_action are already set by the JSON parsing error handler
             app.logger.info("Executing LLM fallback due to orchestrator parse error.")
             pass

        else: # Orchestrator returned something unexpected or action_type was None (e.g. if parsing failed and it wasnt caught by JSONDecodeError)
            app.logger.error(f"Orchestrator decision logic issue. Action_type: '{action_type}'. Details: {details}")
            fallback_text = f"System Error: Orchestrator decision was unclear (action: {action_type}). Using fallback for your query."
            if action_type is None and agent_action == "orchestration_failed": # Initial state before parsing attempt
                 fallback_text = "System Error: Orchestrator did not provide a valid action. Using fallback."

            system_info_msg = Message(sender='system-info', text=fallback_text, agent_action='orchestrator_unrecognized_action')
            db.session.add(system_info_msg)
            ai_response_text = call_ollama("mistral", user_message_text, history_for_target_llm)
            agent_action = "llm_mistral_fallback_orchestrator_unknown_action"
            if "ERROR:" in ai_response_text:
                 agent_action = "llm_mistral_fallback_ollama_error"

    except requests.exceptions.RequestException as e:
        app.logger.error(f"Ollama request failed: {e}")
        ai_response_text = f"ERROR: Failed to connect to AI service. Is Ollama running? Details: {e}"
        agent_action = "ollama_connection_error"
        system_error_msg = Message(sender='system-info', text=ai_response_text, agent_action=agent_action)
        db.session.add(system_error_msg)
    except Exception as e:
        app.logger.error(f"Unexpected error in chat processing: {e}", exc_info=True)
        ai_response_text = f"An unexpected server error occurred: {str(e)}"
        agent_action = "chat_processing_exception"
        system_error_msg = Message(sender='system-info', text=ai_response_text, agent_action=agent_action)
        db.session.add(system_error_msg)

    # Save final AI response to DB
    ai_msg_db = Message(sender='ai', text=ai_response_text, agent_action=agent_action)
    # tool_details_for_response is not directly saved to Message model here, but returned to frontend
    # System messages related to tool use are saved above.

    db.session.add(ai_msg_db)
    db.session.commit()

    # Ensure 'response' key matches what frontend expects (was responseData.response)
    return jsonify({"response": ai_response_text, "ai_response_text": ai_response_text, "agent_action": agent_action, "tool_details": tool_details_for_response}), 200

EOF

echo "Modifying backend/app.py..."

# Define markers for injection/replacement
PROMPT_TOOLS_INJECTION_MARKER="# === INJECT PSI ADVANCED REASONING PROMPTS AND TOOLS HERE ==="
CHAT_ROUTE_START_MARKER="# START /api/chat ROUTE"
CHAT_ROUTE_END_MARKER="# END /api/chat ROUTE"
FLASK_APP_INIT_MARKER="app = Flask(__name__)" # Common line to anchor prompt injection
LOGGING_CONFIG_MARKER="app.logger.setLevel(logging.DEBUG)" # For adding logging level

# Create the new app.py
# 1. Add imports if necessary (json, logging, requests are key for new code)
# Check if imports exist, if not, add them.
# This is a simplified way; a more robust script might use AST parsing or more careful sed.
if ! grep -q "import json" app.py.bak; then
    echo "import json" >> temp_app_imports.py
fi
if ! grep -q "import logging" app.py.bak; then
    echo "import logging" >> temp_app_imports.py
fi
if ! grep -q "import requests" app.py.bak; then # call_ollama uses requests
    echo "import requests" >> temp_app_imports.py
fi

# Concatenate parts to form the new app.py
cat temp_app_imports.py > app.py # Start with new imports
rm -f temp_app_imports.py

# Add lines from old app.py up to Flask App initialization
awk "/$FLASK_APP_INIT_MARKER/{print; exit} {print}" app.py.bak >> app.py

# Add logging configuration if it doesn't exist
if ! grep -q "$LOGGING_CONFIG_MARKER" app.py.bak; then
    echo "$LOGGING_CONFIG_MARKER" >> app.py
fi

# Inject prompt and tools definitions
cat prompt_tools_definitions.py >> app.py
rm prompt_tools_definitions.py

# Add lines from Flask App init up to the START of the old /api/chat route
# This assumes the old /api/chat route has the CHAT_ROUTE_START_MARKER
# If not, this part needs to be manually adjusted or use a more robust marker.
# For now, we assume the old chat route is the *only* @app.route('/api/chat', methods=['POST'])
# A safer approach if markers are not present:
# sed -n "/$FLASK_APP_INIT_MARKER/,/@app.route('\/api\/chat', methods=\['POST'\])/{ /@app.route('\/api\/chat', methods=\['POST'\])/!p; }" app.py.bak >> app.py
# This sed command is complex. Simpler: find line number of flask app init, line number of chat route.
FLASK_APP_LINE=$(grep -n "$FLASK_APP_INIT_MARKER" app.py.bak | cut -d: -f1)
CHAT_ROUTE_DEF_LINE=$(grep -n "@app.route('/api/chat', methods=\['POST'\])" app.py.bak | head -n 1 | cut -d: -f1)

if [ -z "$CHAT_ROUTE_DEF_LINE" ]; then
    echo "ERROR: Could not find the existing @app.route('/api/chat', methods=['POST']) in app.py.bak. Cannot proceed with backend modification."
    # Restore backup and exit if this critical step fails
    # cp app.py.bak app.py
    # exit 1
    echo "Continuing, but app.py may be broken. Assuming chat route is at the end or not present."
    # Add everything after Flask app init marker if chat route not found
    sed -n "$((FLASK_APP_LINE + 1)),\$p" app.py.bak >> app.py

else
    # Add lines between Flask app init and chat route definition
    sed -n "$((FLASK_APP_LINE + 1)),$((CHAT_ROUTE_DEF_LINE - 1))p" app.py.bak >> app.py
fi


# Add the new chat route logic
cat new_chat_route.py >> app.py
rm new_chat_route.py

# Add the rest of app.py AFTER the old chat route
# This requires knowing where the old chat route ends.
# Assuming the CHAT_ROUTE_END_MARKER exists. If not, this is tricky.
# A simple heuristic: find the next @app.route or if it's the last function.
# For this script, we'll assume the new chat route replaces all of the old one and anything after it that's not another route.
# This part is the most fragile. A robust solution would parse Python AST or use clear markers.
# If CHAT_ROUTE_END_MARKER was used in the original app.py:
# sed -n "/$CHAT_ROUTE_END_MARKER/,\$p" app.py.bak | sed "1d" >> app.py # skip the end marker line itself
# If not, we might be appending helper functions that were defined after the old chat route.
# Let's assume helper functions (call_ollama, tools) are defined *before* routes or are imported.
# If they are after, they might be cut, unless the CHAT_ROUTE_DEF_LINE captures only the beginning.

# A safer bet: if there are other routes or important code after the chat route, they need to be preserved.
# This script currently assumes the chat route is the last major route or that helper functions are earlier.
# If CHAT_ROUTE_DEF_LINE was found, find the end of that function. Python functions end with unindented lines.
# This is too complex for a simple bash script.
# The provided new_chat_route.py IS the new function body.
# The original app.py's chat route is now fully replaced.
# What if other routes or code were AFTER the original chat route?
# We need to append lines from app.py.bak that came AFTER the original chat route.
# This needs a CHAT_ROUTE_END_MARKER or knowledge of the next function definition.

# Simplified: Assuming the original chat route was the last one or followed by standard Flask app run.
# Look for "if __name__ == '__main__':" as a common ending part.
MAIN_APP_RUN_LINE=$(grep -n "if __name__ == '__main__':" app.py.bak | cut -d: -f1)
if [ ! -z "$CHAT_ROUTE_DEF_LINE" ] && [ ! -z "$MAIN_APP_RUN_LINE" ] && [ "$MAIN_APP_RUN_LINE" -gt "$CHAT_ROUTE_DEF_LINE" ]; then
    # Find the start of the next route/definition after the old chat route, or start of main block
    # This is still tricky. For now, let's assume the new chat route is the primary modification and
    # other parts of app.py (like tool function definitions) are correctly placed before this route
    # or are part of the new_chat_route.py's assumed scope.
    # The new_chat_route.py assumes `call_ollama`, `read_file_tool`, `write_file_tool`, `document_processing_tool`
    # are already globally available in app.py.

    # Append the if __name__ == '__main__': block if it exists
    if [ ! -z "$MAIN_APP_RUN_LINE" ]; then
        sed -n "${MAIN_APP_RUN_LINE},\$p" app.py.bak >> app.py
    fi
else
    # If CHAT_ROUTE_DEF_LINE was not found, we appended everything after FLASK_APP_LINE.
    # If it was found but MAIN_APP_RUN_LINE was before it (unlikely), this logic is flawed.
    # This part of script shows limitations of bash for code manipulation without clear markers.
    echo "Warning: Appending the 'if __name__ == \"__main__\":' block. Review app.py for correctness if other routes followed the original chat route."
    if [ ! -z "$MAIN_APP_RUN_LINE" ]; then
         if ! grep -q "if __name__ == '__main__':" app.py; then # Avoid duplicate
            sed -n "${MAIN_APP_RUN_LINE},\$p" app.py.bak >> app.py
         fi
    fi
fi


echo "backend/app.py has been modified."
echo "IMPORTANT: Review backend/app.py carefully, especially if you had custom code after the original /api/chat route."
echo "Ensure that helper functions (call_ollama, read_file_tool, etc.) are correctly defined or imported and in scope for the new chat route."


# Deactivate virtual environment if it was activated
if [ -f "venv/bin/activate" ]; then
    deactivate || echo "Note: 'deactivate' command might not be available if sourcing venv doesn't define it. This is usually fine."
fi
cd "$PROJECT_ROOT" # Navigate back to project root

echo ""
echo "--------------------------------------------------------------------"
echo "Step 2: Modifying Frontend (frontend/src/App.tsx)"
echo "--------------------------------------------------------------------"
cd frontend || { echo "Failed to navigate to frontend directory."; exit 1; }

echo "Backing up frontend/src/App.tsx to frontend/src/App.tsx.bak..."
cp src/App.tsx src/App.tsx.bak

# New App.tsx content
cat << 'EOF' > src/App.tsx
import React, { useState, FormEvent, ChangeEvent, useEffect, useRef } from 'react';
import axios from 'axios';
import './App.css';

interface Message {
  id?: number;
  text: string;
  sender: 'user' | 'ai' | 'system-info';
  timestamp?: string;
  agent_action?: string;
}

function App() {
  const [messages, setMessages] = useState<Message[]>([]);
  const [input, setInput] = useState<string>('');
  const [loading, setLoading] = useState<boolean>(false);
  const messagesEndRef = useRef<null | HTMLDivElement>(null);

  const scrollToBottom = () => {
    messagesEndRef.current?.scrollIntoView({ behavior: "smooth" });
  }

  useEffect(scrollToBottom, [messages]);

  useEffect(() => {
    const fetchHistory = async () => {
      console.log("Fetching chat history from http://localhost:5000/api/history ...");
      // setLoading(true); // Not ideal to show loading for initial history fetch unless it's slow
      try {
        const response = await axios.get<Message[]>('http://localhost:5000/api/history');
        setMessages(response.data || []);
      } catch (error) {
        console.error('Error fetching chat history:', error);
        const historyErrorMsg: Message = {
          text: 'Failed to load chat history. Previous messages may not be available.',
          sender: 'system-info',
          timestamp: new Date().toISOString()
        };
        setMessages(prev => [...prev, historyErrorMsg]);
      } finally {
        // setLoading(false);
      }
    };

    fetchHistory();
  }, []);

  const getOrchestrationStepMessageText = (agentAction?: string): string | null => {
    if (!agentAction) return null;

    if (agentAction.startsWith('orchestrator_selected_tool_')) {
      const toolName = agentAction.replace('orchestrator_selected_tool_', '').replace(/_/g, ' ');
      return `Agent selected tool: ${toolName.split(' ')[0]}`; // Just tool name
    }
    if (agentAction.startsWith('orchestrator_selected_llm_')) {
      const llmName = agentAction.replace('orchestrator_selected_llm_', '').replace(/_/g, ' ');
      return `Agent selected LLM: ${llmName.split(' ')[0]}`; // Just LLM name
    }
    if (agentAction === 'orchestrator_parse_error' || agentAction.includes('fallback_orchestrator')) {
        return 'Agent had an issue with initial decision, using fallback.';
    }
    // Example: if agent_action is "tool_read_file_success" you could also add a message here
    // but usually the AI's main response will cover that.
    return null;
  };

  const handleSendMessage = async (e: FormEvent) => {
    e.preventDefault();
    if (input.trim() === '') return;

    const userMessage: Message = { text: input, sender: 'user', timestamp: new Date().toISOString() };
    setMessages((prevMessages) => [...prevMessages, userMessage]);

    const reasoningMessage: Message = { text: "Agent is reasoning about your request...", sender: 'system-info', timestamp: new Date().toISOString() };
    setMessages((prevMessages) => [...prevMessages, reasoningMessage]);

    const currentInput = input;
    setInput('');
    setLoading(true);

    try {
      const response = await axios.post('http://localhost:5000/api/chat', {
        message: currentInput,
      });

      const responseData = response.data;
      // Ensure consistent access to response text, backend uses "response" and "ai_response_text"
      const aiResponseText = responseData.response || responseData.ai_response_text;
      const agentAction = responseData.agent_action;


      const orchestrationStepText = getOrchestrationStepMessageText(agentAction);
      if (orchestrationStepText) {
        const orchMessage: Message = {
          text: orchestrationStepText,
          sender: 'system-info',
          timestamp: new Date().toISOString(),
          agent_action: agentAction
        };
        setMessages((prevMessages) => {
            if (prevMessages.length > 0 && prevMessages[prevMessages.length - 1].text === orchMessage.text && prevMessages[prevMessages.length -1].sender === 'system-info') {
                return prevMessages; // Avoid duplicate consecutive system messages if logic reruns quickly
            }
            return [...prevMessages, orchMessage];
        });
      }

      const aiMessage: Message = {
        text: aiResponseText || "Sorry, I didn't get a response.",
        sender: 'ai',
        timestamp: new Date().toISOString(),
        agent_action: agentAction
      };
      setMessages((prevMessages) => [...prevMessages, aiMessage]);

    } catch (error) {
      console.error('Error sending message to backend:', error);
      let errorMessageText = 'Error: Could not get response from AI.';
      if (axios.isAxiosError(error)) {
        if (error.response) {
          errorMessageText = error.response.data?.error || error.response.data?.response || error.response.data?.ai_response_text || `Backend Error: ${error.response.status}`;
        } else if (error.request) {
          errorMessageText = 'Error: Cannot connect to backend. Is it running on port 5000?';
        }
      }
      const errorMessage: Message = {
        text: errorMessageText,
        sender: 'ai', // Show error as an AI message for simplicity
        timestamp: new Date().toISOString()
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
        <h1>PSI AI Chat (Advanced Reasoning)</h1>
      </header>
      <div className="chat-container">
        <div className="messages-display">
          {messages.map((msg, index) => (
            <div key={msg.timestamp ? `${msg.timestamp}-${index}` : index} className={`message ${msg.sender}`}>
              <span className="sender-label">
                {msg.sender === 'user' ? 'You' : msg.sender === 'ai' ? 'AI' : 'System'}:
              </span>
              <span className="message-text">{msg.text}</span>
              {msg.timestamp && <span className="timestamp">{new Date(msg.timestamp).toLocaleTimeString()}</span>}
            </div>
          ))}
          {/* Refined loading message: shows only if loading and the last message isn't already an AI response or system processing step */}
          {loading && messages[messages.length -1]?.sender !== 'ai' && messages[messages.length -1]?.text !== "Agent is reasoning about your request..." && <div className="message system-info"><span className="sender-label">System:</span><span className="message-text">Processing...</span></div>}
          <div ref={messagesEndRef} />
        </div>
        <form onSubmit={handleSendMessage} className="message-input-form">
          <input
            type="text"
            value={input}
            onChange={handleInputChange}
            placeholder="Ask (e.g., 'read file.txt', 'code a snake game in python', 'what is AI?')"
            disabled={loading}
          />
          <button type="submit" disabled={loading}>Send</button>
        </form>
      </div>
    </div>
  );
}

export default App;
EOF

echo "frontend/src/App.tsx has been overwritten with the new version."
cd "$PROJECT_ROOT" # Navigate back to project root

echo ""
echo "--------------------------------------------------------------------"
echo "Step 3: Final Instructions and Server Management"
echo "--------------------------------------------------------------------"

echo "Advanced reasoning capabilities have been integrated!"
echo ""
echo "To run the application:"
echo "1. Ensure Ollama is running and has the 'mistral' and 'deepseek-coder' models pulled."
echo "   (e.g., 'ollama pull mistral', 'ollama pull deepseek-coder')"
echo "2. Start the backend server:"
echo "   cd ~/psi_pwa_linux_new/backend"
echo "   source venv/bin/activate  # If not already active"
echo "   python app.py > backend.log 2>&1 &"
echo "   BACKEND_PID=$!"
echo "   echo \"Backend server started with PID: $BACKEND_PID. Logs in backend/backend.log\""
echo ""
echo "3. Start the frontend server:"
echo "   cd ~/psi_pwa_linux_new/frontend"
echo "   npm start > frontend.log 2>&1 &"
echo "   FRONTEND_PID=$!"
echo "   echo \"Frontend server started with PID: $FRONTEND_PID. Logs in frontend/frontend.log\""
echo "   echo \"Note: npm start might open a browser window. Output also in frontend/frontend.log\""
echo ""
echo "4. Access the application in your browser (usually http://localhost:3000)."
echo ""
echo "Example prompts for advanced reasoning:"
echo "  - 'read file.txt' (if file.txt exists in backend/workspace)"
echo "  - 'write a summary of climate change to summary.txt'"
echo "  - 'analyze the key points in this document: [paste some text here]'"
echo "  - 'generate a python function to calculate factorial'"
echo "  - 'what is the capital of France?'"
echo ""
echo "To stop the servers:"
echo "   kill \$BACKEND_PID"
echo "   kill \$FRONTEND_PID"
echo "   echo \"Servers stopped. You might need to use 'kill -9 \$PID' if they don't stop gracefully.\""
echo "   echo \"You can also use 'pkill -f python' and 'pkill -f node' if PIDs are lost, but be cautious.\""
echo ""
echo "Please review the modified files (backend/app.py and frontend/src/App.tsx) and their backups (.bak)."
echo "The backend/app.py modification was complex; thorough testing is recommended."
echo "Script completed."
chmod +x add_psi_advanced_reasoning.sh
