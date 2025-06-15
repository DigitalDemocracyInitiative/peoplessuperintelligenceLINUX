import os
import sys
import importlib
import inspect
import json
import logging

# Configure basic logging
logging.basicConfig(level=logging.INFO)

def discover_tools(tools_dir):
    """
    Discovers tools (functions and their JSON schemas) from Python files
    in the specified directory.

    Args:
        tools_dir (str): The path to the directory containing tool modules.

    Returns:
        tuple: A tuple containing:
            - dict: A dictionary mapping tool function names to the functions themselves.
            - dict: A dictionary mapping tool function names to their JSON schemas.
    """
    tool_functions = {}
    tool_schemas = {}
    abs_tools_dir = os.path.abspath(tools_dir)

    if not os.path.isdir(abs_tools_dir):
        logging.warning(f"Tools directory '{abs_tools_dir}' not found.")
        return tool_functions, tool_schemas

    # Ensure the tools directory is in sys.path to allow direct module imports
    if abs_tools_dir not in sys.path:
        sys.path.insert(0, abs_tools_dir)
        logging.info(f"Added '{abs_tools_dir}' to sys.path for tool discovery.")

    for filename in os.listdir(abs_tools_dir):
        if filename.endswith(".py") and not filename.startswith("_"):
            module_name = filename[:-3]
            try:
                # Import the module directly by its name, as it's now in sys.path
                module = importlib.import_module(module_name)
                logging.info(f"Successfully imported module: {module_name}")

                for name, func in inspect.getmembers(module, inspect.isfunction):
                    if hasattr(func, 'tool_schema'):
                        logging.info(f"Found tool function: {name} in {module_name}")
                        tool_functions[name] = func
                        # Ensure schema is a dictionary if it's a JSON string
                        schema = func.tool_schema
                        if isinstance(schema, str):
                            try:
                                tool_schemas[name] = json.loads(schema)
                            except json.JSONDecodeError as e:
                                logging.error(f"Failed to parse JSON schema for tool {name} in {module_name}: {e}")
                                tool_schemas[name] = {"error": "Invalid JSON schema"}
                        elif isinstance(schema, dict):
                            tool_schemas[name] = schema
                        else:
                            logging.error(f"Tool schema for {name} in {module_name} is neither a string nor a dict.")
                            tool_schemas[name] = {"error": "Schema is not in a recognizable format"}

            except ImportError as e:
                logging.error(f"Failed to import module {module_name}: {e}")
            except Exception as e:
                logging.error(f"An unexpected error occurred while processing {module_name}: {e}")

    # Clean up sys.path if added by this function, to avoid long-term pollution
    # However, for a running application, it might be intended to keep it for the app's lifetime.
    # If this function is called only once at startup, removing it might be okay.
    # For simplicity here, we'll leave it, assuming app.py might rely on it.
    # if abs_tools_dir == sys.path[0]:
    #     sys.path.pop(0)
    #     logging.info(f"Removed '{abs_tools_dir}' from sys.path after discovery.")

    return tool_functions, tool_schemas

if __name__ == '__main__':
    # Example usage:
    # Create a dummy tools directory and a tool file for testing
    current_dir = os.path.dirname(__file__)
    dummy_tools_dir = os.path.join(current_dir, "tools") # Assumes tools are in backend/tools

    if not os.path.exists(dummy_tools_dir):
        os.makedirs(dummy_tools_dir)

    tool_code_example = """
import json

def example_tool_function(param1: str, param2: int) -> str:
    '''
    This is an example tool function.
    It takes a string and an integer, and returns a string.
    '''
    return f"Called with {param1} and {param2}"

example_tool_function.tool_schema = json.dumps({
    "name": "example_tool_function",
    "description": "An example tool that processes a string and an integer.",
    "parameters": {
        "type": "object",
        "properties": {
            "param1": {"type": "string", "description": "The first parameter."},
            "param2": {"type": "integer", "description": "The second parameter."}
        },
        "required": ["param1", "param2"]
    }
})

def another_tool(query: str) -> dict:
    '''Searches for something based on a query.'''
    return {"result": f"Search result for {query}"}

another_tool.tool_schema = { # Schema can also be a dict directly
    "name": "another_tool",
    "description": "Another example tool that takes a query string.",
    "parameters": {
        "type": "object",
        "properties": {
            "query": {"type": "string", "description": "The search query."}
        },
        "required": ["query"]
    }
}
"""
    with open(os.path.join(dummy_tools_dir, "my_example_tool.py"), "w") as f:
        f.write(tool_code_example)

    # Test discovery (assuming this script is in backend/ and tools are in backend/tools/)
    # For this test to run directly, agent_core.py would need to be in the parent of 'tools'
    # or tools_dir needs to be specified carefully.
    # If agent_core.py is in backend/ and tools are in backend/tools/, then tools_dir="tools" is correct.

    # Adjust tools_dir for direct execution if agent_core.py is in backend/
    # and the dummy_tools_dir is backend/tools/
    script_location_dir = os.path.dirname(__file__) # Should be backend/
    tools_relative_path = "tools" # Relative to backend/

    logging.info(f"Attempting to discover tools from: {os.path.join(script_location_dir, tools_relative_path)}")

    functions, schemas = discover_tools(tools_relative_path) # Pass relative path from backend/

    logging.info("\\nDiscovered Functions:")
    for name, func in functions.items():
        logging.info(f"  {name}: {func}")

    logging.info("\\nDiscovered Schemas:")
    for name, schema in schemas.items():
        logging.info(f"  {name}: {json.dumps(schema, indent=2)}")

    # Clean up dummy files
    # os.remove(os.path.join(dummy_tools_dir, "my_example_tool.py"))
    # if not os.listdir(dummy_tools_dir): # Only remove if empty
    #     os.rmdir(dummy_tools_dir)
    # else:
    #     # Check for __pycache__ and remove if it's the only thing left
    #     pycache_dir = os.path.join(dummy_tools_dir, "__pycache__")
    #     if os.path.exists(pycache_dir) and all(item == "__pycache__" for item in os.listdir(dummy_tools_dir)):
    #         import shutil
    #         shutil.rmtree(pycache_dir)
    #         if not os.listdir(dummy_tools_dir):
    #              os.rmdir(dummy_tools_dir)


    logging.info("\\nNote: If running this test directly, ensure 'tools' directory exists relative to this script,")
    logging.info("and contains Python tool files. The example creates 'tools/my_example_tool.py'.")
    logging.info("The cleanup of dummy files is commented out to allow inspection.")

"""
A note on the dummy tool creation and sys.path for the __main__ block:
If `agent_core.py` is in `backend/`, and the tools are in `backend/tools/`,
then when `discover_tools("tools")` is called from `agent_core.py`,
`abs_tools_dir` becomes `/path/to/backend/tools`.
`sys.path.insert(0, '/path/to/backend/tools')` is correct.
Then `importlib.import_module("my_example_tool")` will correctly import `/path/to/backend/tools/my_example_tool.py`.
The example usage in `__main__` should work as intended with `tools_dir="tools"` if this script itself is in `backend/`.
"""
