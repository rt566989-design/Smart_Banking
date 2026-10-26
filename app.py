"""
Root Entry Point for Smart Banking & ADBMS Full-Stack System
Delegates to backend.app for complete ADBMS and PL/SQL functionality.
"""
from backend.app import app

if __name__ == "__main__":
    print("\n=======================================================")
    print("  🚀 ApexBank PL/SQL & ADBMS Full-Stack Web Application")
    print("  ➜ Access URL: http://127.0.0.1:5000")
    print("=======================================================\n")
    app.run(host="0.0.0.0", port=5000, debug=False)
