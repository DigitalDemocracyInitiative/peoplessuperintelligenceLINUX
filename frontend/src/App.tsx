import React, { useState, FormEvent, ChangeEvent, useEffect } from 'react';
import axios from 'axios';
import './App.css'; // Assuming create-react-app made this

interface Message {
  id?: number; // Optional, as it might not be present for new messages
  text: string;
  sender: 'user' | 'ai' | 'system-info'; // Added 'system-info'
  timestamp?: string; // Optional, for messages from history
}

function App() {
  const [messages, setMessages] = useState<Message[]>([]);
  const [input, setInput] = useState<string>('');
  const [loading, setLoading] = useState<boolean>(false);

  useEffect(() => {
    const fetchHistory = async () => {
      console.log("Fetching chat history...");
      setLoading(true);
      try {
        const response = await axios.get<Message[]>('http://localhost:5000/api/history');
        // Assuming backend returns messages in chronological order (timestamp asc)
        setMessages(response.data);
      } catch (error) {
        console.error('Error fetching chat history:', error);
        // Add a system message to the chat indicating failure
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
  }, []); // Empty dependency array ensures this runs only once on mount

  const handleSendMessage = async (e: FormEvent) => {
    e.preventDefault();
    if (input.trim() === '') return;

    const userMessage: Message = { text: input, sender: 'user' };
    setMessages((prevMessages) => [...prevMessages, userMessage]);
    const currentInput = input; // Capture current input before clearing
    setInput('');
    setLoading(true);

    try {
      const response = await axios.post('http://localhost:5000/api/chat', {
        message: currentInput, // Use captured input
      });

      const agentAction = response.data.agent_action;
      const responseText = response.data.response;

      const aiMessage: Message = {
        text: responseText,
        sender: 'ai'
      };

      if (agentAction && typeof agentAction === 'string' && agentAction.startsWith('file_')) {
        aiMessage.text = `[File Tool] ${responseText}`;
      }

      setMessages((prevMessages) => [...prevMessages, aiMessage]);
    } catch (error) {
      console.error('Error sending message to backend:', error);
      let errorMessageText = 'Error: Could not get response from AI. Check backend (http://localhost:5000) and Ollama (http://localhost:11434).';
      if (axios.isAxiosError(error) && error.response) {
        // If backend provides a specific error message, prefer that.
        errorMessageText = error.response.data.error || errorMessageText;
      } else if (axios.isAxiosError(error) && error.request) {
        // Network error or backend not reachable
         errorMessageText = 'Error: Cannot connect to backend. Please ensure it is running.';
      }
      const errorMessage: Message = {
        text: errorMessageText,
        sender: 'ai',
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
          {loading && messages.length === 0 && <div className="message system-info"><strong>System:</strong> Loading history...</div>}
          {loading && messages.length > 0 && <div className="message ai"><strong>AI:</strong> Thinking...</div>}
        </div>
        <form onSubmit={handleSendMessage} className="message-input-form">
          <input
            type="text"
            value={input}
            onChange={handleInputChange}
            placeholder="Type your message..."
            disabled={loading && messages.length > 0}
          />
          <button type="submit" disabled={loading && messages.length > 0}>Send</button>
        </form>
      </div>
    </div>
  );
}

export default App;
