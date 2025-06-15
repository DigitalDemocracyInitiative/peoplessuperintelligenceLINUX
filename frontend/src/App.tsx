// frontend/src/App.tsx
import React, { useState, useEffect, useRef } from 'react';
import ChatInput from './components/ChatInput';
import ChatHistory from './components/ChatHistory';
import ModelSelector from './components/ModelSelector';
import AgentProfileSettings from './components/AgentProfileSettings'; // Assuming this component exists
import './App.css';

interface Message {
  id: string;
  role: 'user' | 'assistant' | 'system' | 'tool';
  content: string;
  tool_calls?: ToolCall[];
  tool_call_id?: string; // For tool responses
  // agentAction?: 'thinking' | 'calling_tool' | 'responding' | 'error' | null; // Older version
  agentAction?: 'thinking' | 'calling_tool' | 'tool_response' | 'responding' | 'error' | null; // Updated
}

interface ToolCall {
  id: string;
  type: 'function';
  function: {
    name: string;
    arguments: string; // JSON string
  };
}

interface AgentProfile {
  name: string;
  persona: string;
  tools: any[]; // Define more specifically if possible
  state: Record<string, any>;
}

// New interface for BackgroundTask
interface BackgroundTask {
  id: number;
  name: string;
  status: 'pending' | 'in_progress' | 'completed' | 'failed';
  result?: string;
  created_at: string;
  updated_at?: string;
}

// New interface for UI Configuration
interface UIConfig {
  appTitle: string;
  defaultWelcomeMessage: string;
  uiSections: {
    profileSelector: boolean;
    chatContainer: boolean;
    backgroundTasks: boolean;
    availableTools: boolean;
    agentSettings: boolean;
  };
  availableModels: string[];
}

const App: React.FC = () => {
  const [messages, setMessages] = useState<Message[]>([]);
  const [chatHistory, setChatHistory] = useState<Message[]>([]);
  const [selectedModel, setSelectedModel] = useState<string>(''); // Will be populated from config
  const [agentProfile, setAgentProfile] = useState<AgentProfile | null>(null);
  const [isLoading, setIsLoading] = useState<boolean>(false);
  const [error, setError] = useState<string | null>(null);

  // New state variables
  const [backgroundTasks, setBackgroundTasks] = useState<BackgroundTask[]>([]);
  const [uiConfig, setUiConfig] = useState<UIConfig | null>(null); // Initialize as null

  const messagesEndRef = useRef<HTMLDivElement>(null);

  const scrollToBottom = () => {
    messagesEndRef.current?.scrollIntoView({ behavior: "smooth" });
  };

  useEffect(scrollToBottom, [messages]);

  // Fallback UI Config if API fails
  const fallbackUiConfig: UIConfig = {
    appTitle: "Monarch Agent",
    defaultWelcomeMessage: "Welcome! How can I assist you today?",
    uiSections: {
      profileSelector: true,
      chatContainer: true,
      backgroundTasks: true,
      availableTools: true,
      agentSettings: true,
    },
    availableModels: ["llama3 (default)"],
  };

  // Fetch initial data: Agent Profile, UI Config, and Background Tasks
  useEffect(() => {
    const fetchInitialData = async () => {
      setIsLoading(true);
      try {
        // Fetch UI Config
        const configResponse = await fetch('/api/config');
        if (configResponse.ok) {
          const configData = await configResponse.json();
          setUiConfig(configData);
          setSelectedModel(configData.available_models[0] || 'llama3'); // Set first model as default
           if (configData.defaultWelcomeMessage) {
            setMessages([{ id: 'initial-welcome', role: 'system', content: configData.defaultWelcomeMessage }]);
          }
        } else {
          console.error("Failed to fetch UI config, using fallback.");
          setUiConfig(fallbackUiConfig);
          setSelectedModel(fallbackUiConfig.available_models[0]);
          setMessages([{ id: 'initial-welcome', role: 'system', content: fallbackUiConfig.defaultWelcomeMessage }]);
        }

        // Fetch Agent Profile
        const profileResponse = await fetch('/api/agent/profile');
        if (profileResponse.ok) {
          const profileData = await profileResponse.json();
          setAgentProfile(profileData);
        } else {
          setError("Failed to fetch agent profile.");
          console.error("Failed to fetch agent profile.");
        }

        // Fetch Background Tasks
        await fetchTasks();

      } catch (err) {
        setError("Error fetching initial data.");
        console.error("Error fetching initial data:", err);
        setUiConfig(fallbackUiConfig); // Use fallback on any catch
        setSelectedModel(fallbackUiConfig.available_models[0]);
        setMessages([{ id: 'initial-welcome', role: 'system', content: fallbackUiConfig.defaultWelcomeMessage }]);
      } finally {
        setIsLoading(false);
      }
    };
    fetchInitialData();
  }, []);


  // Function to fetch tasks
  const fetchTasks = async () => {
    try {
      const tasksResponse = await fetch('/api/tasks');
      if (tasksResponse.ok) {
        const tasksData = await tasksResponse.json();
        setBackgroundTasks(tasksData);
      } else {
        console.error("Failed to fetch tasks.");
      }
    } catch (err) {
      console.error("Error fetching tasks:", err);
    }
  };

  // Poll for tasks periodically
  useEffect(() => {
    const intervalId = setInterval(() => {
      if (uiConfig?.uiSections.backgroundTasks) { // Only poll if section is visible
         fetchTasks();
      }
    }, 5000); // Poll every 5 seconds

    return () => clearInterval(intervalId); // Cleanup on unmount
  }, [uiConfig]); // Re-run if uiConfig changes (e.g., section becomes visible)


  const handleSendMessage = async (userInput: string) => {
    if (!userInput.trim()) return;

    const newUserMessage: Message = { id: Date.now().toString(), role: 'user', content: userInput };
    setMessages(prevMessages => [...prevMessages, newUserMessage]);
    setChatHistory(prevHistory => [...prevHistory, newUserMessage]);
    setIsLoading(true);
    setError(null);

    // Add a thinking message
    const thinkingMessageId = `assistant-thinking-${Date.now()}`;
    const thinkingMessage: Message = {
        id: thinkingMessageId,
        role: 'assistant',
        content: '...',
        agentAction: 'thinking'
    };
    setMessages(prevMessages => [...prevMessages, thinkingMessage]);


    try {
      const response = await fetch('/api/chat', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ message: userInput, history: chatHistory, model: selectedModel }),
      });

      // Remove thinking message
      setMessages(prevMessages => prevMessages.filter(msg => msg.id !== thinkingMessageId));

      if (!response.ok) {
        const errorData = await response.json().catch(() => ({ detail: "Unknown error" }));
        throw new Error(errorData.detail || `HTTP error! status: ${response.status}`);
      }

      const data = await response.json();
      const assistantMessage: Message = {
        id: Date.now().toString(), // Ensure unique ID
        role: data.role || 'assistant',
        content: data.content,
        tool_calls: data.tool_calls,
        agentAction: data.tool_calls ? 'calling_tool' : 'responding'
      };

      setMessages(prevMessages => [...prevMessages, assistantMessage]);
      setChatHistory(prevHistory => [...prevHistory, assistantMessage]);

      // If there are tool calls, the backend will handle them and send another message.
      // For now, the UI just displays the tool call request.
      // Future improvements could involve client-side display of tool execution.

    } catch (err: any) {
      console.error("Error sending message:", err);
      const errorMessage: Message = {
        id: `error-${Date.now()}`,
        role: 'assistant',
        content: `Error: ${err.message || "Failed to get response from server."}`,
        agentAction: 'error'
      };
      setMessages(prevMessages => [...prevMessages, errorMessage]);
      setError(err.message || "Failed to get response from server.");
    } finally {
      setIsLoading(false);
      fetchTasks(); // Refresh tasks after sending a message
    }
  };


  const handleProfileUpdate = (updatedProfile: AgentProfile) => {
    setAgentProfile(updatedProfile);
    // Optionally, send a system message indicating profile update
    setMessages(prev => [...prev, {
      id: `system-${Date.now()}`,
      role: 'system',
      content: `Agent profile updated. New name: ${updatedProfile.name}. Persona: ${updatedProfile.persona.substring(0,50)}...`
    }]);
  };

  // Initial "Loading..." state for the app
  if (!uiConfig) {
    return <div className="app-container">Loading configuration...</div>;
  }

  return (
    <div className="app-container">
      <header className="app-header">
        <h1>{uiConfig.appTitle}</h1>
        {uiConfig.uiSections.profileSelector && (
           <ModelSelector
            selectedModel={selectedModel}
            onModelChange={setSelectedModel}
            availableModels={uiConfig.availableModels || ['llama3']}
          />
        )}
      </header>

      <div className="main-content">
        {uiConfig.uiSections.chatContainer && (
          <div className="chat-container">
            <ChatHistory messages={messages} agentProfile={agentProfile} />
            <ChatInput onSendMessage={handleSendMessage} isLoading={isLoading} />
            <div ref={messagesEndRef} />
            {error && <p className="error-message">Error: {error}</p>}
          </div>
        )}

        {(uiConfig.uiSections.agentSettings || uiConfig.uiSections.availableTools || uiConfig.uiSections.backgroundTasks) && (
          <aside className="sidebar">
            {uiConfig.uiSections.agentSettings && agentProfile && (
              <AgentProfileSettings
                profile={agentProfile}
                onProfileUpdate={handleProfileUpdate}
              />
            )}

            {uiConfig.uiSections.availableTools && agentProfile && agentProfile.tools && (
              <div className="tools-section card">
                <h2>Available Tools</h2>
                {agentProfile.tools.length > 0 ? (
                  <ul>
                    {agentProfile.tools.map(tool => (
                      <li key={tool.function?.name || tool.type}>
                        <strong>{tool.function?.name || tool.type}</strong>: {tool.function?.description}
                      </li>
                    ))}
                  </ul>
                ) : (
                  <p>No tools configured for this agent.</p>
                )}
              </div>
            )}

            {uiConfig.uiSections.backgroundTasks && (
              <div className="tasks-section card">
                <h2>Background Tasks</h2>
                {backgroundTasks.length > 0 ? (
                  <ul>
                    {backgroundTasks.map(task => (
                      <li key={task.id} className={`task-status-${task.status.replace('_', '-')}`}>
                        <strong>{task.name} (ID: {task.id})</strong>: {task.status}
                        {task.result && <p><small>Result: {task.result.substring(0, 100)}{task.result.length > 100 ? '...' : ''}</small></p>}
                        <small>Last updated: {new Date(task.updated_at || task.created_at).toLocaleTimeString()}</small>
                      </li>
                    ))}
                  </ul>
                ) : (
                  <p>No background tasks running.</p>
                )}
              </div>
            )}
          </aside>
        )}
      </div>
    </div>
  );
};

export default App;
