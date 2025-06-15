
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
