#!/bin/bash
set -e # Exit immediately if a command exits with a non-zero status.

echo "========================================================="
echo "        PSI PWA Linux Backend Setup Script"
echo "========================================================="
echo ""
echo "This script will set up the foundational backend for PSI PWA on Linux."
echo "It requires Python 3 and python3-venv to be available."
echo ""
read -p "Press Enter to begin, or Ctrl+C to cancel..."

echo ""
echo "--- Step 1: Update System Packages ---"
sudo apt update
echo ""

echo "--- Step 2: Install Python 3 and python3-venv ---"
sudo apt install -y python3 python3-venv
echo ""

echo "--- Step 3: Create Project Directories ---"
mkdir -p ~/psi_pwa_linux_new/backend
cd ~/psi_pwa_linux_new/backend
echo "Working directory: $(pwd)"
echo ""

echo "--- Step 4: Set up Python Virtual Environment ---"
python3 -m venv venv
source venv/bin/activate
echo "Virtual environment activated: (venv)"
echo ""

echo "--- Step 5: Install Flask and Gunicorn ---"
pip install Flask gunicorn
echo ""

echo "--- Step 6: Create app.py and requirements.txt ---"
cat << EOF > app.py
from flask import Flask

app = Flask(__name__)

@app.route('/')
def hello_world():
    return 'Hello from PSI Backend!'

if __name__ == '__main__':
    app.run(host='0.0.0.0', port=5000, debug=True)
EOF

cat << EOF > requirements.txt
Flask
gunicorn
EOF
echo "app.py and requirements.txt created."
echo ""

echo "========================================================="
echo "        PSI PWA Linux Backend Setup Complete!"
echo "========================================================="
echo ""
echo "To run your Flask backend:"
echo "1. Navigate to the backend directory: cd ~/psi_pwa_linux_new/backend"
echo "2. Activate the virtual environment: source venv/bin/activate"
echo "3. Run the Flask development server: python app.py"
echo "   (Access it in your browser at http://127.0.0.1:5000)"
echo "4. To run with Gunicorn (production server): gunicorn -w 4 app:app -b 0.0.0.0:5000"
echo ""
read -p "Press Enter to finish and exit script..."
