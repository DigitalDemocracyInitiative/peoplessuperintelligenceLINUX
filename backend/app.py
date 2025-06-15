from flask import Flask, request, jsonify
from flask_cors import CORS
import requests
import json # For handling potential json.JSONDecodeError

app = Flask(__name__)
CORS(app) # Enable CORS for all routes

@app.route('/')
def hello_world():
    return 'Hello from PSI Backend!'

@app.route('/api/chat', methods=['POST'])
def chat():
    data = request.get_json()
    user_message = data.get('message')

    if not user_message:
        return jsonify({"error": "No message provided"}), 400

    ollama_url = "http://localhost:11434/api/generate"
    try:
        ollama_payload = {
            "model": "mistral",
            "prompt": user_message,
            "stream": False
        }
        # Increased timeout to 120 seconds for potentially long LLM responses
        response = requests.post(ollama_url, json=ollama_payload, timeout=120)
        response.raise_for_status()  # Raises an HTTPError for bad responses (4XX or 5XX)
        ollama_response = response.json()
        ai_message = ollama_response.get('response', 'No response from AI.')
        return jsonify({"response": ai_message}), 200
    except requests.exceptions.Timeout:
        print("Error: Timeout while communicating with Ollama.")
        return jsonify({"error": "Failed to connect to Ollama: Timeout"}), 500
    except requests.exceptions.ConnectionError:
        print("Error: Connection error while communicating with Ollama.")
        return jsonify({"error": "Failed to connect to Ollama: Connection Error"}), 500
    except requests.exceptions.RequestException as e:
        print(f"Error communicating with Ollama: {e}")
        return jsonify({"error": f"Failed to communicate with Ollama: {e}"}), 500
    except json.JSONDecodeError:
        print("Error decoding JSON from Ollama response.")
        return jsonify({"error": "Invalid JSON response from Ollama"}), 500
    except Exception as e:
        print(f"An unexpected error occurred: {e}")
        return jsonify({"error": f"An unexpected error occurred: {str(e)}"}), 500

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)
