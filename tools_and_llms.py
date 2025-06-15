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
            "name": "document_analysis",
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
