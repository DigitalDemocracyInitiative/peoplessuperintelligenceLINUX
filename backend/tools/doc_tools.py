import time
import json # Added for schema definition

def document_processing_tool(text_content: str):
    """Performs basic text analysis (word and character count)."""
    # Simulating some processing time
    # print(f"DEBUG: Document processing tool called with text: '{text_content[:50]}...'") # Commented out for cleaner output unless debugging
    time.sleep(0.5) # Reduced sleep time for faster execution

    word_count = len(text_content.split())
    char_count = len(text_content)

    return {
        "tool_name": "document_processing_tool", # Ensure this matches the function name for clarity
        "success": True,
        "result": f"Text analyzed: {word_count} words, {char_count} characters.",
        "word_count": word_count,
        "char_count": char_count
    }

# Schema for document_processing_tool
document_processing_tool.tool_schema = {
    "name": "document_processing_tool", # Function name matches
    "description": "Analyzes a given block of text, providing statistics like word count and character count. Useful for summarizing or understanding text length.",
    "parameters": {
        "type": "object",
        "properties": {
            "text_content": {
                "type": "string",
                "description": "The text content to analyze."
            }
        },
        "required": ["text_content"]
    }
}

if __name__ == '__main__':
    test_text = "This is a sample document for testing the document processing tool. It has several words and characters."
    analysis_result = document_processing_tool(test_text)
    print(f"Analysis Result: {analysis_result}")

    # print("\nSchema:")
    # print(json.dumps(document_processing_tool.tool_schema, indent=2))
