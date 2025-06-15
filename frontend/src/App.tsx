import React, { useState, FormEvent, ChangeEvent, useEffect } from 'react';
import axios from 'axios';
import './App.css'; // Assuming create-react-app made this

interface Message {
  id?: number; // Optional, as it might not be present for new messages
  text: string;
  sender: 'user' | 'ai' | 'system-info'; // Added 'system-info'
  timestamp?: string; // Optional, for messages from history
}

// Helper function to parse agent_action for system messages
const getOrchestrationStepMessage = (agentAction?: string): string | null => {
  if (!agentAction || typeof agentAction !== 'string') {
    return null;
  }

  if (agentAction.startsWith('orchestrator_tool_')) {
    const toolName = agentAction.replace('orchestrator_tool_', '').split('_')[0];
    return `Agent selected tool: ${toolName}.`;
  }
  if (agentAction.startsWith('orchestrator_llm_')) {
    const llmName = agentAction.replace('orchestrator_llm_', '').split('_')[0];
    return `Agent selected LLM: ${llmName}.`;
  }
  // Could add more specific messages based on tool success/failure if needed,
  // e.g., "tool_read_file_success" -> "Agent successfully read file."
  // For now, focusing on orchestrator selection.
  return null;
};


function App() {
  const [messages, setMessages] = useState<Message[]>([]);
  const [input, setInput] = useState<string>('');
  const [loading, setLoading] = useState<boolean>(false);

  useEffect(() => {
    const fetchHistory = async () => {
      console.log("Fetching chat history...");
      setLoading(true);
      try {
        // Assuming the backend is running on port 5001 as per docker-compose
        const response = await axios.get<Message[]>('http://localhost:5001/api/history');
        // Assuming backend returns messages in chronological order (timestamp asc)
        setMessages(response.data);
      } catch (error) {
        console.error('Error fetching chat history:', error);
        const historyErrorMsg: Message = {
          text: 'Failed to load chat history. Previous messages may not be available.',
          sender: 'system-info'
        };
        setMessages(prev => [...prev, historyErrorMsg]);
      } finally {
        setLoading(false);
      }
    };

    fetchHistory();
  }, []);

  const handleSendMessage = async (e: FormEvent) => {
    e.preventDefault();
    if (input.trim() === '') return;

    const userMessage: Message = { text: input, sender: 'user' };
    // Add user message first
    setMessages((prevMessages) => [...prevMessages, userMessage]);

    // Add "Agent is reasoning" message
    const reasoningMessage: Message = { text: "Agent is reasoning about your request...", sender: 'system-info' };
    setMessages((prevMessages) => [...prevMessages, reasoningMessage]);

    const currentInput = input;
    setInput('');
    setLoading(true); // Keep this to show "AI: Thinking..." or disable input

    try {
      // Assuming the backend is running on port 5001
      const response = await axios.post('http://localhost:5001/api/chat', {
        message: currentInput,
        // Potentially send chat_id if you implement multi-chat sessions
        // chat_id: currentChatId
      });

      const agentAction = response.data.agent_action; // e.g., "orchestrator_tool_read_file", "llm_deepseek-coder_success"
      const aiResponseText = response.data.ai_response_text; // Main response text
      // const toolDetails = response.data.tool_details; // Available if needed

      // Add "Agent selected..." message if applicable, based on agent_action
      const orchestrationStepMsgText = getOrchestrationStepMessage(agentAction);
      if (orchestrationStepMsgText) {
        const systemSelectionMessage: Message = { text: orchestrationStepMsgText, sender: 'system-info' };
        setMessages((prevMessages) => [...prevMessages, systemSelectionMessage]);
      }

      // Add the main AI response
      const aiMessage: Message = {
        text: aiResponseText, // This is the primary text from the AI/tool
        sender: 'ai'
      };

      // The previous logic to prepend "[File Tool]" can be removed if the
      // ai_response_text from the backend already includes sufficient detail.
      // Or, it can be refined based on `agent_action` or `tool_details`.
      // For example:
      if (agentAction && typeof agentAction === 'string') {
        if (agentAction.startsWith('tool_read_file_success')) {
          // aiMessage.text = `[File Read] ${aiResponseText}`; // Example modification
        } else if (agentAction.startsWith('tool_') && agentAction.endsWith('_failed')) {
          // aiMessage.text = `[Tool Error] ${aiResponseText}`;
        }
      }

      setMessages((prevMessages) => [...prevMessages, aiMessage]);

    } catch (error) {
      console.error('Error sending message to backend:', error);
      let errorMessageText = 'Error: Could not get response from AI. Check backend (http://localhost:5001) and Ollama (http://localhost:11434).';
      if (axios.isAxiosError(error) && error.response) {
        errorMessageText = error.response.data.error || error.response.data.ai_response_text || errorMessageText;
      } else if (axios.isAxiosError(error) && error.request) {
        errorMessageText = 'Error: Cannot connect to backend. Please ensure it is running at http://localhost:5001.';
      }
      const errorMessage: Message = {
        text: errorMessageText,
        sender: 'ai', // Displaying as 'ai' for consistency, but it's an error message
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
        <h1>PSI AI Chat</h1>
      </header>
      <div className="chat-container">
        <div className="messages-display">
          {messages.map((msg, index) => (
            <div key={msg.id || index} className={`message ${msg.sender}`}>
              <strong>{msg.sender === 'user' ? 'You' : msg.sender === 'ai' ? 'AI' : 'System'}:</strong> {msg.text}
              {msg.timestamp && <span className="timestamp">{new Date(msg.timestamp).toLocaleTimeString()}</span>}
            </div>
          ))}
          {/* "Thinking..." message is displayed based on loading state when messages.length > 0 */}
          {loading && messages.length > 0 && messages[messages.length -1].sender !== 'ai' && <div className="message system-info"><strong>System:</strong> Processing...</div>}
        </div>
        <form onSubmit={handleSendMessage} className="message-input-form">
          <input
            type="text"
            value={input}
            onChange={handleInputChange}
            placeholder="Type your message..."
            disabled={loading} // Simplified loading condition
          />
          <button type="submit" disabled={loading}>Send</button>
        </form>
      </div>
    </div>
  );
}

export default App;
