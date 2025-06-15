import os
import time
import json # Added for schema definition

AGENT_WORKSPACE_DIR = os.path.expanduser('~/psi_pwa_linux_new/agent_workspace')

def _resolve_filepath(filename: str):
    """Safely resolves a filename to be within the agent workspace."""
    if not filename:
        return None, "Filename cannot be empty."

    # Remove leading slashes to ensure join behaves as expected for relative paths
    safe_filename = filename.lstrip('/')

    # Prevent path traversal attempts like '../../etc/passwd'
    if '..' in safe_filename.split(os.path.sep):
        return None, f"Invalid filename: path traversal detected in '{filename}'."

    filepath = os.path.join(AGENT_WORKSPACE_DIR, safe_filename)

    # Final check to ensure the path is within the workspace
    if not os.path.abspath(filepath).startswith(os.path.abspath(AGENT_WORKSPACE_DIR)):
        return None, f"Attempted to access file outside workspace: {filename}"
    return filepath, None

def read_file_tool(filename: str):
    """Reads content from a file within the agent workspace."""
    filepath, error = _resolve_filepath(filename)
    if error:
        return {"tool_name": "read_file", "success": False, "error": error, "filename": filename}

    try:
        if not os.path.exists(filepath):
            return {"tool_name": "read_file", "success": False, "error": f"File not found: {filename}", "filename": filename}
        if not os.path.isfile(filepath): # Ensure it's a file, not a directory
            return {"tool_name": "read_file", "success": False, "error": f"Path is not a file: {filename}", "filename": filename}

        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()
        return {"tool_name": "read_file", "success": True, "filename": filename, "content": content}
    except Exception as e:
        return {"tool_name": "read_file", "success": False, "filename": filename, "error": str(e)}

# Schema for read_file_tool
read_file_tool.tool_schema = {
    "name": "read_file_tool", # Function name matches
    "description": "Reads content from a specified file in the agent's workspace. Useful for reviewing existing notes, code, or data.",
    "parameters": {
        "type": "object",
        "properties": {
            "filename": {
                "type": "string",
                "description": "The name of the file to read (e.g., 'notes.txt', 'script.py'). Must be relative to the agent_workspace."
            }
        },
        "required": ["filename"]
    }
}

def write_file_tool(filename: str, content: str):
    """Writes content to a file within the agent workspace."""
    filepath, error = _resolve_filepath(filename)
    if error:
        return {"tool_name": "write_file", "success": False, "error": error, "filename": filename}

    try:
        # Create parent directories if they don't exist
        os.makedirs(os.path.dirname(filepath), exist_ok=True)
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(content)
        return {"tool_name": "write_file", "success": True, "filename": filename, "message": f"Content written to {filename}"}
    except Exception as e:
        return {"tool_name": "write_file", "success": False, "filename": filename, "error": str(e)}

# Schema for write_file_tool
write_file_tool.tool_schema = {
    "name": "write_file_tool", # Function name matches
    "description": "Writes content to a specified file in the agent's workspace. Use to save information, create scripts, or store data.",
    "parameters": {
        "type": "object",
        "properties": {
            "filename": {
                "type": "string",
                "description": "The name of the file to write to (e.g., 'output.txt', 'new_script.py'). Must be relative to the agent_workspace."
            },
            "content": {
                "type": "string",
                "description": "The content to write into the file."
            }
        },
        "required": ["filename", "content"]
    }
}

# For testing purposes if run directly
if __name__ == '__main__':
    # Create workspace if it doesn't exist
    if not os.path.exists(AGENT_WORKSPACE_DIR):
        os.makedirs(AGENT_WORKSPACE_DIR)

    print(f"Agent Workspace: {AGENT_WORKSPACE_DIR}")

    # Test write_file_tool
    write_result = write_file_tool("test_file.txt", "Hello from file_tools!")
    print(f"Write Result: {write_result}")

    if write_result["success"]:
        # Test read_file_tool
        read_result = read_file_tool("test_file.txt")
        print(f"Read Result: {read_result}")

        # Test reading a non-existent file
        read_non_existent_result = read_file_tool("non_existent_file.txt")
        print(f"Read Non-Existent Result: {read_non_existent_result}")

    # Test path traversal prevention in _resolve_filepath
    print(_resolve_filepath("../../../etc/passwd"))
    print(_resolve_filepath("/etc/passwd"))
    print(_resolve_filepath("valid_subfolder/file.txt"))

    # Clean up test file
    if os.path.exists(os.path.join(AGENT_WORKSPACE_DIR, "test_file.txt")):
        os.remove(os.path.join(AGENT_WORKSPACE_DIR, "test_file.txt"))

    # print("Schemas:")
    # print("read_file_tool schema:", json.dumps(read_file_tool.tool_schema, indent=2))
    # print("write_file_tool schema:", json.dumps(write_file_tool.tool_schema, indent=2))
