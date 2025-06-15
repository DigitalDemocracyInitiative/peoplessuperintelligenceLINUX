#!/bin/bash

# This script automates the integration of a multi-agent workflow
# into the existing PSI (Python/Flask backend, React/TypeScript frontend) application.

echo "Starting multi-agent workflow integration script..."
echo "ENSURE THIS SCRIPT IS RUN FROM THE PROJECT ROOT: ~/psi_pwa_linux_new"
echo "Current directory: $(pwd)"
echo "-----------------------------------------------------------------------"
sleep 3 # Give user time to read the above

# Section 1: Navigate to Project Root (and confirm)
# ------------------------------------
echo "Step 1: Confirming Project Root and Navigating..."
PROJECT_ROOT="$HOME/psi_pwa_linux_new"

# Check if current directory is already the project root
if [ "$(pwd)" != "$PROJECT_ROOT" ]; then
    echo "Not in project root. Navigating to $PROJECT_ROOT..."
    if [ -d "$PROJECT_ROOT" ]; then
        cd "$PROJECT_ROOT" || { echo "ERROR: Failed to navigate to project root: $PROJECT_ROOT. Exiting."; exit 1; }
    else
        echo "ERROR: Project root directory $PROJECT_ROOT does not exist. Exiting."
        exit 1
    fi
else
    echo "Already in project root: $(pwd)."
fi
echo "Current directory set to: $(pwd) (Project Root)"
echo "-----------------------------------------------------------------------"


# Section 2: Backend (Python/Flask) Multi-Agent Workflow Implementation
# ---------------------------------------------------------------------
echo ""
echo "--- Starting Backend Modifications ---"

# 2.1 Navigate to the backend directory
echo "Step 2.1: Navigating to backend directory..."
if [ -d "backend" ]; then
    cd backend || { echo "ERROR: Failed to navigate to backend directory from $(pwd). Exiting."; exit 1; }
else
    echo "ERROR: backend directory not found in $(pwd). Exiting."
    exit 1
fi
echo "Current directory: $(pwd) (Backend)"

# 2.2 Activate the Python virtual environment
echo "Step 2.2: Activating Python virtual environment..."
# Standard venv names: .venv or venv
VENV_PATH=""
if [ -d ".venv" ]; then
    VENV_PATH=".venv/bin/activate"
elif [ -d "venv" ]; then
    VENV_PATH="venv/bin/activate"
fi

if [ -n "$VENV_PATH" ] && [ -f "$VENV_PATH" ]; then
    source "$VENV_PATH" || { echo "ERROR: Failed to activate virtual environment at $VENV_PATH. Exiting."; exit 1; }
    echo "Python virtual environment activated from $VENV_PATH."
else
    echo "WARNING: Python virtual environment (.venv or venv) not found in $(pwd)."
    echo "Backend scripts might not run correctly without dependencies."
fi

# 2.3 Modify app.py - Update Orchestrator System Prompt
echo "Step 2.3: Updating Orchestrator System Prompt in app.py..."
cat > /tmp/new_orchestrator_prompt_content.py << 'EOF_PROMPT'
ORCHESTRATOR_SYSTEM_PROMPT = """You are an orchestrator AI. Your primary role is to analyze user requests and determine the most effective way to fulfill them. This may involve a single action or a multi-step plan involving different specialized agents.

**Single Action Tasks:**

If the user request can be handled by a single action, identify the appropriate `action_type` and formulate a `prompt` for the designated agent. The available single action types are:
*   `text_completion`: For generating text, answering questions, providing explanations.
*   `image_generation`: For creating images based on textual descriptions.
*   `file_search`: For finding files within the project directory. The prompt should be the filename or a pattern to search for.
*   `file_edit`: For modifying existing files. The prompt should contain the `file_path` and the `new_content` for the file.

Output JSON for single action tasks should look like this:
{
  "action_type": "text_completion",
  "prompt": "Explain the theory of relativity in simple terms."
}

**Multi-Stage Requests & Multi-Agent Planning:**

If the user request is complex and requires multiple steps or different specialized capabilities, you must break it down into a sequence of sub-tasks. For such requests, you will output an `action_type: "multi_agent_plan"`.

The `multi_agent_plan` object must contain a list of steps, where each step specifies:
*   `sub_task`: A concise description of what this step aims to achieve.
*   `agent_role`: The role of the agent best suited for this sub-task (e.g., "Researcher", "Summarizer", "Coder", "FileIO", "Explainer").
*   `sub_prompt`: The specific instruction or query for the assigned agent for this step. This prompt should be self-contained and provide all necessary context for the agent to perform its task. If a step depends on the output of a previous step, you should indicate this in the `sub_prompt`, for example, by referring to "[output of previous step]".

**Examples of `multi_agent_plan` JSON output:**

1.  If the user asks: "Research the latest advancements in quantum computing and then summarize the key findings."
    ```json
    {
      "action_type": "multi_agent_plan",
      "plan": [
        {
          "sub_task": "Research information on quantum computing",
          "agent_role": "Researcher",
          "sub_prompt": "Find the latest advancements in quantum computing, focusing on the last 1-2 years."
        },
        {
          "sub_task": "Summarize the findings",
          "agent_role": "Summarizer",
          "sub_prompt": "Summarize the provided text about the latest advancements in quantum computing. Ensure the summary is concise and highlights key breakthroughs."
        }
      ]
    }
    ```

2.  If the user asks: "Find an example of a recursive Python function for factorial, write it to a file named 'recursive_factorial.py', and then explain how it works."
    ```json
    {
      "action_type": "multi_agent_plan",
      "plan": [
        {
          "sub_task": "Find an example of a recursive Python function for factorial",
          "agent_role": "Coder",
          "sub_prompt": "Provide a simple, correct example of a recursive function in Python to calculate factorial. The function should be clearly defined."
        },
        {
          "sub_task": "Write the function to a file named 'recursive_factorial.py'",
          "agent_role": "FileIO",
          "sub_prompt": "Write the following Python code to a file named 'recursive_factorial.py': [code from previous step]"
        },
        {
          "sub_task": "Explain how the recursive function works",
          "agent_role": "Explainer",
          "sub_prompt": "Explain the provided Python recursive factorial function. Describe its base case and recursive step."
        }
      ]
    }
    ```

Analyze the user's request carefully. If it implies a sequence of actions or requires distinct types of processing, formulate a `multi_agent_plan`. Otherwise, choose the appropriate single action.
"""
EOF_PROMPT
if [ ! -f "app.py" ]; then echo "ERROR: app.py not found in $(pwd). Exiting."; rm -f /tmp/new_orchestrator_prompt_content.py; exit 1; fi
BACKUP_APP_PY_PROMPT="app.py.bak.prompt.$(date +%s)"
cp app.py "$BACKUP_APP_PY_PROMPT"
echo "Backup of app.py created as $BACKUP_APP_PY_PROMPT"
awk 'BEGIN{p=0}/ORCHESTRATOR_SYSTEM_PROMPT = """/{if(!p){while((getline line<"/tmp/new_orchestrator_prompt_content.py")>0)print line;close("/tmp/new_orchestrator_prompt_content.py");p=1}next}p&&/"""/{p=0;next}!p{print}' "$BACKUP_APP_PY_PROMPT" > app.py
if grep -q "multi_agent_plan" app.py; then echo "Orchestrator prompt in app.py updated successfully."; else echo "ERROR updating orchestrator prompt in app.py. Check $BACKUP_APP_PY_PROMPT."; fi
rm -f /tmp/new_orchestrator_prompt_content.py

# 2.4 Add Imports and Multi-Agent Logic to app.py
echo "Step 2.4: Adding Imports and Multi-Agent Logic to app.py..."
if [ -f app.py ] && grep -q "from flask import Flask, request, jsonify, session" app.py; then
    if ! grep -q "from .tools import internet_search, write_file_tool, read_file_tool" app.py; then
        sed -i "/from flask import Flask, request, jsonify, session/a \
from .tools import internet_search, write_file_tool, read_file_tool \\\n\
from .llm_calls import call_mistral_llm, call_deepseek_coder_llm \\\n\
from .utils import add_message_to_db \\\n\
import json \\\n\
import re \\\n\
import logging \\\n\
logger = logging.getLogger(__name__)" app.py
        echo "Imports added to app.py."
    else
        echo "Imports seem to exist already in app.py."
    fi
else
    echo "WARNING: Could not add imports automatically to app.py. Anchor line or app.py missing."
fi

cat << 'EOPYTHON_LOGIC' > /tmp/multi_agent_logic.py
elif action_type == "multi_agent_plan":
    final_ai_response_text = "An unexpected error occurred in the multi-agent workflow."
    final_agent_action = {"type": "multi_agent_error", "error_message": "Workflow did not complete."}
    try:
        logger.info("Orchestrator is planning a multi-agent workflow...")
        add_message_to_db(session_id, "system", "Orchestrator is planning a multi-agent workflow...", "multi_agent_planning", "System", None)
        plan = orchestrator_response_json.get('plan', [])
        if not plan:
            logger.error("Multi-agent plan is empty or malformed.")
            raise ValueError("Multi-agent plan is empty or malformed.")
        logger.info(f"Multi-agent plan devised: {json.dumps(plan)}")
        add_message_to_db(session_id, "system", f"Multi-agent plan devised: {json.dumps(plan)}", "multi_agent_planning", "System", {"plan": plan})
        accumulated_results_details = []
        previous_step_result_text = None
        for step_idx, step in enumerate(plan):
            sub_task_description = step.get('sub_task')
            agent_role = step.get('agent_role')
            sub_prompt = step.get('sub_prompt')
            if not all([sub_task_description, agent_role, sub_prompt]):
                logger.error(f"Malformed step in multi-agent plan: {step}")
                raise ValueError(f"Malformed step {step_idx+1} in plan. Critical information missing.")
            step_message = f"Executing Step {step_idx+1}/{len(plan)}: Agent ({agent_role}) - Task: {sub_task_description}"
            logger.info(step_message)
            add_message_to_db(session_id, "system", step_message, "sub_agent_executing", agent_role, {"role": agent_role, "task": sub_task_description, "step": step_idx+1, "total_steps": len(plan)})
            current_step_output_text = f"Error: Agent role '{agent_role}' not recognized or failed."
            context_for_current_step = f"Your task is: {sub_prompt}"
            if previous_step_result_text:
                context_for_current_step += f"\n\nRelevant information from the previous step that might be useful:\n{previous_step_result_text}"
            if agent_role == "Researcher":
                raw_result = internet_search(sub_prompt, session_id)
                if isinstance(raw_result, dict): current_step_output_text = raw_result.get("results", raw_result.get("summary", json.dumps(raw_result)))
                elif isinstance(raw_result, str): current_step_output_text = raw_result
                else: current_step_output_text = "No specific results found from research."
                logger.info(f"Researcher output (first 200 chars): {str(current_step_output_text)[:200]}...")
            elif agent_role == "Summarizer":
                text_to_summarize = previous_step_result_text if previous_step_result_text else sub_prompt
                max_len = 3800
                summarizer_final_prompt = f"{sub_prompt}\n\nText to summarize (first {max_len} chars):\n{text_to_summarize[:max_len]}"
                llm_response = call_mistral_llm(summarizer_final_prompt, session_id)
                current_step_output_text = llm_response.get('text', "Summary not available.")
                logger.info(f"Summarizer output (first 200 chars): {str(current_step_output_text)[:200]}...")
            elif agent_role == "Coder":
                llm_response = call_deepseek_coder_llm(context_for_current_step, session_id)
                current_step_output_text = llm_response.get('text', "Code not generated.")
                logger.info(f"Coder output (first 200 chars): {str(current_step_output_text)[:200]}...")
                if "```" not in current_step_output_text and agent_role == "Coder": current_step_output_text = f"```python\n{current_step_output_text}\n```"
            elif agent_role == "FileIO":
                operation, filename = None, None
                content_for_writing = str(previous_step_result_text) if previous_step_result_text else ""
                fn_match = re.search(r"(?:file named\s*['\"]?(?P<fn1>[^'\"]+)['\"]?|filename\s+(?P<fn2>[^\s]+))", sub_prompt.lower())
                if fn_match: filename = fn_match.group('fn1') or fn_match.group('fn2')
                if not filename:
                    if "write to file" in sub_prompt.lower():
                        try: filename = sub_prompt.lower().split("write to file")[-1].strip().split()[0].replace("'", "").replace('"',"")
                        except: pass
                    elif "read file" in sub_prompt.lower():
                        try: filename = sub_prompt.lower().split("read file")[-1].strip().split()[0].replace("'", "").replace('"',"")
                        except: pass
                if "write" in sub_prompt.lower(): operation = "write"
                elif "read" in sub_prompt.lower(): operation = "read"
                if not filename: current_step_output_text = f"Error: FileIO filename could not be reliably determined from prompt: '{sub_prompt}'."
                elif operation == "write":
                    if not content_for_writing:
                        logger.warning(f"FileIO: Write for {filename} called but previous_step_result_text is empty.")
                        current_step_output_text = f"FileIO: No content from previous step to write to {filename} for prompt: '{sub_prompt}'."
                    else:
                        write_response = write_file_tool({"filename": filename, "content": str(content_for_writing)}, session_id)
                        current_step_output_text = write_response.get("message", f"Content written to {filename}.")
                        logger.info(f"FileIO: Wrote to {filename}")
                elif operation == "read":
                    read_response = read_file_tool({"filename": filename}, session_id)
                    current_step_output_text = read_response.get("content", f"Successfully read {filename}, content empty.") if read_response.get("success") else read_response.get("error", f"Could not read file {filename}.")
                    logger.info(f"FileIO: Read from {filename}. Success: {read_response.get('success')}")
                else: current_step_output_text = f"Error: FileIO operation (read/write) not determined from prompt: '{sub_prompt}'. Filename: '{filename}'."
                if not current_step_output_text: current_step_output_text = f"FileIO task '{sub_prompt}' for '{filename}' processed."
            elif agent_role == "Explainer":
                text_to_explain = previous_step_result_text if previous_step_result_text else sub_prompt
                explainer_final_prompt = f"{sub_prompt}\n\nItem to explain (first 3800 chars):\n{text_to_explain[:3800]}"
                llm_response = call_mistral_llm(explainer_final_prompt, session_id)
                current_step_output_text = llm_response.get('text', "Explanation not available.")
                logger.info(f"Explainer output (first 200 chars): {str(current_step_output_text)[:200]}...")
            else:
                logger.warning(f"Unknown agent role: {agent_role} for sub-task: {sub_task_description}")
                current_step_output_text = f"Unknown agent role: '{agent_role}'. Step skipped."
            accumulated_results_details.append(f"### Step {step_idx+1} ({agent_role}): {sub_task_description}\n**Output:**\n{current_step_output_text}")
            previous_step_result_text = str(current_step_output_text)
        synthesis_message = "All sub-tasks completed. Synthesizing final response..."
        logger.info(synthesis_message)
        add_message_to_db(session_id, "system", synthesis_message, "multi_agent_synthesis", "System", None)
        final_ai_response_text = "\n\n---\n\n".join(accumulated_results_details)
        if not final_ai_response_text.strip(): final_ai_response_text = "Multi-agent workflow completed with no textual output."
        final_agent_action = {"type": "multi_agent_complete", "summary": "Multi-agent workflow completed."}
        response_message_id = add_message_to_db(session_id, "ai", final_ai_response_text, "multi_agent_complete", "AI", final_agent_action)
    except ValueError as ve:
        logger.error(f"ValueError in multi-agent workflow: {str(ve)}", exc_info=True)
        error_msg = f"Config error in multi-agent workflow: {str(ve)}."
        add_message_to_db(session_id, "system", error_msg, "multi_agent_error", "System", {"error": str(ve)})
        final_ai_response_text = error_msg
        final_agent_action = {"type": "multi_agent_error", "error_message": str(ve)}
        response_message_id = add_message_to_db(session_id, "ai", final_ai_response_text, "multi_agent_error", "AI", final_agent_action)
    except Exception as e:
        logger.error(f"General Exception in multi-agent workflow: {str(e)}", exc_info=True)
        error_msg = f"Unexpected error in multi-agent workflow: {str(e)}."
        add_message_to_db(session_id, "system", error_msg, "multi_agent_error", "System", {"error": str(e)})
        final_ai_response_text = error_msg
        final_agent_action = {"type": "multi_agent_error", "error_message": str(e)}
        response_message_id = add_message_to_db(session_id, "ai", final_ai_response_text, "multi_agent_error", "AI", final_agent_action)
EOPYTHON_LOGIC
APP_PY_FILE="app.py" # Already in backend directory
if grep -q "#MULTI_AGENT_INSERTION_POINT" "$APP_PY_FILE"; then
  echo "Marker #MULTI_AGENT_INSERTION_POINT found. Inserting multi-agent logic."
  BACKUP_LOGIC_INSERT="app.py.bak.logic_insert.$(date +%s)"
  cp "$APP_PY_FILE" "$BACKUP_LOGIC_INSERT"
  sed -i -e "/#MULTI_AGENT_INSERTION_POINT/r /tmp/multi_agent_logic.py" -e "/#MULTI_AGENT_INSERTION_POINT/d" "$APP_PY_FILE"
  echo "Multi-agent logic inserted via marker. Verify $APP_PY_FILE. Backup: $BACKUP_LOGIC_INSERT"
else
  echo "WARNING: Marker #MULTI_AGENT_INSERTION_POINT not found. Using fallback awk method for app.py logic insertion."
  BACKUP_FALLBACK_LOGIC="app.py.bak.fallback_logic.$(date +%s)"
  cp "$APP_PY_FILE" "$BACKUP_FALLBACK_LOGIC"
  awk 'BEGIN{ins=0}/^[[:space:]]*else:/{if(!ins){while((getline line<"/tmp/multi_agent_logic.py")>0)print line;close("/tmp/multi_agent_logic.py");ins=1}}{print}' "$BACKUP_FALLBACK_LOGIC" > "$APP_PY_FILE"
  if grep -q 'elif action_type == "multi_agent_plan":' "$APP_PY_FILE"; then echo "Fallback insertion of multi_agent_plan block in app.py successful. Verify $APP_PY_FILE."; else echo "ERROR: Fallback insertion in app.py FAILED. Verify $APP_PY_FILE and $BACKUP_FALLBACK_LOGIC."; fi
fi
rm -f /tmp/multi_agent_logic.py
echo "Backend modifications for multi-agent logic complete."
echo "--- Finished Backend Modifications ---"
echo ""

# Return to Project Root before frontend changes
echo "Step 2.5: Returning to Project Root..."
cd "$PROJECT_ROOT" || { echo "ERROR: Failed to return to project root. Exiting."; exit 1; }
echo "Current directory: $(pwd) (Project Root for Frontend Changes)"
echo "-----------------------------------------------------------------------"


# Section 3: Frontend (React/TypeScript) Display Modifications
# -------------------------------------------------------------
echo ""
echo "--- Starting Frontend Modifications (in frontend/src/App.tsx) ---"
FRONTEND_APP_TSX="frontend/src/App.tsx"

if [ ! -f "$FRONTEND_APP_TSX" ]; then
    echo "ERROR: $FRONTEND_APP_TSX not found! Skipping frontend modifications."
else
    echo "Step 3.1: Backing up $FRONTEND_APP_TSX..."
    FRONTEND_APP_TSX_BAK="${FRONTEND_APP_TSX}.$(date +%Y%m%d%H%M%S).bak"
    cp "$FRONTEND_APP_TSX" "$FRONTEND_APP_TSX_BAK"
    echo "Backup created: $FRONTEND_APP_TSX_BAK"

    echo "Step 3.2: Adding new agentAction types to $FRONTEND_APP_TSX..."
    NEW_TYPES_TO_ADD="'multi_agent_planning' | 'sub_agent_executing' | 'multi_agent_synthesis' | 'multi_agent_complete' | 'multi_agent_error'"
    if ! grep -q "'multi_agent_planning'" "$FRONTEND_APP_TSX"; then
        # Try to insert using a marker first
        if grep -q "// ADD_AGENT_ACTION_TYPES_HERE" "$FRONTEND_APP_TSX"; then
             sed -i "/\/\/ ADD_AGENT_ACTION_TYPES_HERE/a \ \ | ${NEW_TYPES_TO_ADD}" "$FRONTEND_APP_TSX"
             echo "Types added using marker // ADD_AGENT_ACTION_TYPES_HERE."
        # Fallback: try common patterns if marker not found
        elif sed -i.typesbak -e "/type:.*final_response'.*;/ s,'final_response';,'final_response' | ${NEW_TYPES_TO_ADD};'," "$FRONTEND_APP_TSX" && grep -q "'multi_agent_planning'" "$FRONTEND_APP_TSX"; then
            echo "Types added by extending 'final_response' in a type definition."
        elif sed -i.typesbak -e "/type .* = .*'final_response'.*;/ s,'final_response';,'final_response' | ${NEW_TYPES_TO_ADD};'," "$FRONTEND_APP_TSX" && grep -q "'multi_agent_planning'" "$FRONTEND_APP_TSX"; then
            echo "Types added by extending 'final_response' in a type alias."
        else
             echo "WARNING: Failed to automatically add new agentAction types to $FRONTEND_APP_TSX using heuristics."
             echo "Please MANUALLY add the following types to your agent_action type definition (e.g., AgentActionType, Message['agent_action']['type']):"
             echo "${NEW_TYPES_TO_ADD}"
             echo "Using a marker like \`// ADD_AGENT_ACTION_TYPES_HERE\` in your TSX file is recommended."
        fi
        [ -f "${FRONTEND_APP_TSX}.typesbak" ] && rm -f "${FRONTEND_APP_TSX}.typesbak"
    else
        echo "New agent action types ('multi_agent_planning', etc.) seem to already exist in $FRONTEND_APP_TSX."
    fi
    if grep -q "'multi_agent_planning'" "$FRONTEND_APP_TSX"; then echo "Agent action types addition/verification successful."; else echo "WARNING: Agent action types may not have been added correctly."; fi


    echo "Step 3.3: Updating messages-display logic in $FRONTEND_APP_TSX..."
    cat << 'EOFTSX_CASES' > /tmp/frontend_multi_agent_cases.tsx
    // Cases for multi-agent workflow visualization
    case 'multi_agent_planning':
      return (
        <div style={{ color: '#666', fontStyle: 'italic', padding: '5px 0' }}>
          <span role="img" aria-label="planning-icon">🤔</span> Orchestrator is planning a multi-agent workflow...
          {message.agent_action?.metadata?.plan && (
            <pre style={{ fontSize: '0.8em', color: '#888', whiteSpace: 'pre-wrap', wordBreak: 'break-all', maxHeight: '100px', overflowY: 'auto', background: '#f9f9f9', border: '1px solid #eee', padding: '5px' }}>
              Plan: {JSON.stringify(message.agent_action.metadata.plan, null, 2)}
            </pre>
          )}
        </div>
      );
    case 'sub_agent_executing':
      const role = message.agent_action?.metadata?.role || 'Agent';
      const task = message.agent_action?.metadata?.task || 'a sub-task';
      const stepInfo = message.agent_action?.metadata?.step && message.agent_action?.metadata?.total_steps
        ? ` (Step ${message.agent_action.metadata.step}/${message.agent_action.metadata.total_steps})`
        : '';
      return (
        <div style={{ color: '#007bff', fontStyle: 'italic', padding: '5px 0' }}>
          <span role="img" aria-label="executing-icon">🏃</span> {role}{stepInfo} is executing: {task}
        </div>
      );
    case 'multi_agent_synthesis':
      return (
        <div style={{ color: '#28a745', fontStyle: 'italic', padding: '5px 0' }}>
          <span role="img" aria-label="synthesis-icon">🔄</span> Combining results from sub-agents...
        </div>
      );
    case 'multi_agent_error':
      const errorDetails = message.agent_action?.error_message || message.agent_action?.metadata?.error || 'Unknown error';
      return (
        <div style={{ color: 'red', fontStyle: 'italic', padding: '10px', border: '1px solid red', borderRadius: '4px', background: '#fff5f5' }}>
          <span role="img" aria-label="error-icon">⚠️</span> Multi-agent workflow error:
          <pre style={{ whiteSpace: 'pre-wrap', wordBreak: 'break-all', margin: '5px 0 0 0', maxHeight: '150px', overflowY: 'auto', background: '#fff', border: '1px solid #fdd', padding: '5px' }}>{errorDetails}</pre>
        </div>
      );

EOFTSX_CASES
    if grep -q "// ADD_NEW_AGENT_ACTION_CASES_HERE" "$FRONTEND_APP_TSX"; then
        awk -v r="/tmp/frontend_multi_agent_cases.tsx" '/\/\/ ADD_NEW_AGENT_ACTION_CASES_HERE/{print;while((getline line<r)>0)print line;close(r);next}1' "$FRONTEND_APP_TSX_BAK" > "$FRONTEND_APP_TSX"
        echo "Rendering logic for new types inserted using marker '// ADD_NEW_AGENT_ACTION_CASES_HERE'."
    elif grep -q "switch (message.agent_action?.type)" "$FRONTEND_APP_TSX"; then
        echo "Marker not found. Attempting fallback: insert before 'default:' in a switch statement."
        awk -v r="/tmp/frontend_multi_agent_cases.tsx" '/^[[:space:]]*default:/{while((getline line<r)>0)print line;close(r)}1' "$FRONTEND_APP_TSX_BAK" > "$FRONTEND_APP_TSX"
        echo "Attempted to insert rendering logic before 'default:' case. MANUALLY VERIFY $FRONTEND_APP_TSX."
    else
        echo "WARNING: Could not find marker '// ADD_NEW_AGENT_ACTION_CASES_HERE' or a suitable switch statement for message rendering logic."
        echo "Please MANUALLY insert the content of /tmp/frontend_multi_agent_cases.tsx into the message rendering logic in $FRONTEND_APP_TSX."
    fi
    if grep -q "case 'multi_agent_planning':" "$FRONTEND_APP_TSX"; then echo "Frontend rendering cases addition/verification successful."; else echo "WARNING: Frontend rendering cases may not have been added correctly."; fi
    rm -f /tmp/frontend_multi_agent_cases.tsx
    echo "Frontend modification attempts complete."
fi
echo "--- Finished Frontend Modifications ---"
echo "-----------------------------------------------------------------------"

# Section 4: Finalizing Script - Adding Server Startup and Instructions
# (These commands are appended to THIS script, to be run when THIS script is executed)
echo ""
echo "--- Finalizing Script: Adding Server Startup and Instructions ---"

# Backend Server Startup (to be run by the user via this script)
echo ""
echo "Step 4.1: Starting Backend Server..."
echo "Navigating to backend directory: $(pwd)/backend" # pwd is project root here
cd backend || { echo "ERROR: Failed to navigate to backend directory. Exiting."; exit 1; }

echo "Activating Python virtual environment (checking .venv then venv)..."
VENV_PATH_START=""
if [ -d ".venv" ]; then VENV_PATH_START=".venv/bin/activate"; fi
if [ -z "$VENV_PATH_START" ] && [ -d "venv" ]; then VENV_PATH_START="venv/bin/activate"; fi

if [ -n "$VENV_PATH_START" ] && [ -f "$VENV_PATH_START" ]; then
    source "$VENV_PATH_START" || echo "WARNING: Failed to activate backend virtual environment $VENV_PATH_START."
    echo "Backend virtual environment at $VENV_PATH_START activated/checked."
else
    echo "WARNING: Python virtual environment (.venv or venv) not found in backend directory."
    echo "The backend server might not start correctly without its dependencies."
fi

echo "Starting Flask backend server (port 5001) in the background..."
if [ ! -f "requirements.txt" ]; then echo "WARNING: requirements.txt not found in backend. Dependencies might be missing."; fi
nohup flask run --host=0.0.0.0 --port=5001 > ../backend_server.log 2>&1 &
BACKEND_PID=$!
echo "Backend server started with PID: $BACKEND_PID. Logs: backend_server.log (in project root)"
cd .. # Return to project root
echo $BACKEND_PID > backend_server.pid
echo "Backend PID $BACKEND_PID written to backend_server.pid"


# Frontend Server Startup (to be run by the user via this script)
echo ""
echo "Step 4.2: Starting Frontend Server..."
echo "Navigating to frontend directory: $(pwd)/frontend" # pwd is project root here
cd frontend || { echo "ERROR: Failed to navigate to frontend directory. Exiting."; exit 1; }

echo "Starting React frontend server (port 3000) in the background..."
if [ ! -f "package.json" ]; then echo "WARNING: package.json not found. Node modules might be missing (run npm install)."; fi
nohup npm start > ../frontend_server.log 2>&1 &
FRONTEND_PID=$!
echo "Frontend server process started with PID: $FRONTEND_PID (npm script runner). Logs: frontend_server.log (in project root)"
echo "To ensure the frontend is running, check http://localhost:3000 (or its configured port) in a few moments."
cd .. # Return to project root
echo $FRONTEND_PID > frontend_server.pid
echo "Frontend PID $FRONTEND_PID written to frontend_server.pid"

# Final Instructions Block (Echoed to user when this script finishes)
echo ""
echo "-----------------------------------------------------------------------"
echo ">>> SCRIPT EXECUTION COMPLETE - PSI PWA Multi-Agent Workflow Setup <<<"
echo "-----------------------------------------------------------------------"
echo ""
echo "The PSI PWA has been updated with simulated multi-agent workflow capabilities!"
echo ""
echo "IMPORTANT NEXT STEPS & INFORMATION:"
echo "1.  VERIFICATION: Please MANUALLY VERIFY the changes made to:"
echo "    - backend/app.py (Orchestrator prompt, imports, multi-agent logic)"
echo "    - frontend/src/App.tsx (TypeScript types, message rendering cases)"
echo "    Backup files (.bak.*) were created in the respective directories."
echo ""
echo "2.  DEPENDENCIES (if not handled by other setup scripts):"
echo "    - Backend: cd backend && pip install -r requirements.txt (ensure venv is active)"
echo "    - Frontend: cd frontend && npm install"
echo ""
echo "3.  SERVERS & LOGS:"
echo "    - This script attempted to start both servers in the background."
echo "    - Backend (Flask on port 5001): Logs at backend_server.log (project root)"
echo "    - Frontend (React on port 3000): Logs at frontend_server.log (project root)"
echo "    - Access the application at: http://localhost:3000 (or your frontend port)"
echo ""
echo "4.  TESTING THE MULTI-AGENT WORKFLOW:"
echo "    Try prompts that require multiple steps or capabilities, for example:"
echo "    - 'Research the Mars Perseverance rover's latest findings and then summarize them for a non-technical audience.'"
echo "    - 'Find a Python code snippet for quicksort, write it to 'quicksort.py', and then explain its time complexity.'"
echo "    - 'Read the file 'backend/app.py', then list its main Flask routes.'"
echo ""
echo "5.  OBSERVING THE WORKFLOW:"
echo "    - System messages in the chat UI will indicate planning, sub-agent execution, and synthesis."
echo "    - Detailed backend activity is in backend_server.log."
echo ""
echo "6.  STOPPING THE SERVERS:"
echo "    PIDs were saved to backend_server.pid and frontend_server.pid in the project root."
echo "    - Stop Backend: kill \$(cat backend_server.pid)"
echo "    - Stop Frontend: kill \$(cat frontend_server.pid) (may need to also kill child processes like 'node')"
echo "    Alternatively, use port-based commands (e.g., 'sudo lsof -t -i:5001 | xargs kill -9')."
echo ""
echo "If you encounter issues, check the logs and review the script's output for warnings or errors."
echo "Enjoy your enhanced Personal Task Orchestrator!"
echo "-----------------------------------------------------------------------"

echo ""
echo ">>> This setup script (add_psi_multi_agent_workflow.sh) has completed its operations. <<<"
echo "-----------------------------------------------------------------------"
