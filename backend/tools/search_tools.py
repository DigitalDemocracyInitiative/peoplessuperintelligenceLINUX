from datetime import datetime
import time
import json # Added for schema definition

def internet_search_tool(query: str):
    """Simulates an internet search and returns plausible results."""
    # print(f"DEBUG: Internet search tool called with query: '{query}'") # Commented out
    time.sleep(1) # Reduced sleep time

    query_lower = query.lower()

    # More robust and varied simulated results
    if "current time" in query_lower or "what time is it" in query_lower:
        result = f"The current time is {datetime.now().strftime('%Y-%m-%d %H:%M:%S')}."
    elif "weather in" in query_lower:
        location = query_lower.split("weather in")[-1].strip().title()
        if not location: location = "your current location"
        result = f"Simulated Weather Report for {location}: Sunny with a high of 75°F (24°C). Light breeze."
    elif "capital of" in query_lower:
        country = query_lower.split("capital of")[-1].strip().title()
        capitals = {"France": "Paris", "Germany": "Berlin", "Japan": "Tokyo", "United States": "Washington D.C."}
        result = capitals.get(country, f"The capital of {country} is not in my current simulated database.")
    elif "latest ai advancements" in query_lower:
        result = (
            "Simulated Search Results for 'latest AI advancements':\n"
            "1. New Multimodal Models: Models like GPT-4o and Google's Gemini are pushing boundaries in processing text, audio, images, and video simultaneously.\n"
            "2. Generative AI in Science: AI is accelerating discovery in drug development, material science, and climate modeling.\n"
            "3. Explainable AI (XAI): Significant research is ongoing to make AI decision-making processes more transparent and understandable.\n"
            "4. AI Ethics and Regulation: Increased global discussion and development of frameworks for responsible AI deployment."
        )
    elif "how to make pasta" in query_lower:
        result = (
            "Simulated Recipe for Pasta:\n"
            "1. Boil water in a large pot. Add salt.\n"
            "2. Add pasta and cook according to package directions (usually 8-12 minutes).\n"
            "3. Drain pasta and toss with your favorite sauce.\n"
            "Common sauces: Marinara, Alfredo, Pesto. Enjoy!"
        )
    else:
        result = (
            f"Simulated Search Results for '{query}':\n"
            f"1. Wikipedia: General information about {query}.\n"
            f"2. News Articles: Recent developments and discussions related to {query}.\n"
            f"3. Academic Papers: In-depth research and studies concerning {query} (if applicable)."
        )

    return {"tool_name": "internet_search_tool", "success": True, "query": query, "results": result}

# Schema for internet_search_tool
internet_search_tool.tool_schema = {
    "name": "internet_search_tool", # Function name matches
    "description": "Performs a simulated internet search to get up-to-date information, facts, definitions, or general knowledge on a wide variety of topics.",
    "parameters": {
        "type": "object",
        "properties": {
            "query": {
                "type": "string",
                "description": "The search query string (e.g., 'latest news on quantum computing', 'weather in London', 'how to bake a cake')."
            }
        },
        "required": ["query"]
    }
}

if __name__ == '__main__':
    queries = [
        "current time",
        "weather in New York",
        "capital of Japan",
        "latest AI advancements",
        "how to make pasta",
        "history of the internet"
    ]
    for q in queries:
        search_result = internet_search_tool(q)
        print(f"Query: {q}\nResult: {search_result['results']}\n---")

    # print("\nSchema:")
    # print(json.dumps(internet_search_tool.tool_schema, indent=2))
