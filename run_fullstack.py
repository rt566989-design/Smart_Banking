"""
=============================================================================
APEXBANK PL/SQL FULL-STACK LAUNCHER
Runs the Flask REST API Backend + Serves Modern Frontend UI on http://127.0.0.1:5000
Click the ▶ Play button in Antigravity IDE to launch!
=============================================================================
"""
import sys
import os
import io
import webbrowser
import threading
import time

# Ensure clean UTF-8 output on Windows console
if sys.stdout.encoding != 'utf-8':
    sys.stdout = io.TextIOWrapper(sys.stdout.buffer, encoding='utf-8')


# Ensure project root is in python path
PROJECT_ROOT = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, PROJECT_ROOT)

from backend.app import app

def open_browser():
    time.sleep(1.2)
    print("[LAUNCHER] Opening Web Dashboard in default browser: http://127.0.0.1:5000")
    webbrowser.open("http://127.0.0.1:5000")

if __name__ == "__main__":
    print("=" * 70)
    print("      🚀 APEXBANK PL/SQL FULL-STACK WEB APPLICATION")
    print("      ➜ Backend: Flask REST API + SQLite Engine (ACID & Triggers)")
    print("      ➜ Frontend: Modern Glassmorphic SPA (Dashboard, Cards, Terminal)")
    print("      ➜ Access URL: http://127.0.0.1:5000")
    print("=" * 70)

    # Launch browser automatically
    threading.Thread(target=open_browser, daemon=True).start()

    # Start Flask server
    app.run(host="0.0.0.0", port=5000, debug=False)
