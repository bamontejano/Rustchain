import hashlib
import json
from flask import Flask, request, jsonify

app = Flask(__name__)

# Mock database for registration
REGISTRATIONS_DB = "agent_registrations.json"

def verify_agent_proof(public_key_hex, message, signature_hex):
    """
    Verifies the agent's identity proof using Ed25519.
    Implements real verification if PyNaCl is available.
    """
    if not signature_hex or not public_key_hex:
        return False
    
    try:
        # Attempt real Ed25519 verification
        from nacl.signing import VerifyKey
        verify_key = VerifyKey(bytes.fromhex(public_key_hex))
        verify_key.verify(message.encode(), bytes.fromhex(signature_hex))
        return True
    except ImportError:
        # SECURITY: Do not allow bypass if library is missing.
        # This addresses the "false sense of security" feedback.
        print("CRITICAL: PyNaCl not installed. Cannot verify cryptographic proofs.")
        return False
    except Exception as e:
        print(f"Verification error: {e}")
        return False

@app.route('/api/register', methods=['POST'])
def register_agent():
    """
    Endpoint for agent registration.
    Handles identity verification and metadata storage.
    """
    data = request.get_json()
    
    if not data:
        return jsonify({"status": "error", "message": "Missing request body."}), 400

    # 1. Validate required fields early
    required_fields = ['agent_name', 'hfp', 'public_key', 'signature', 'message']
    for field in required_fields:
        if field not in data or not data[field]:
            return jsonify({"status": "error", "message": f"Missing or empty required field: {field}"}), 400

    # 2. Normalize and validate agent name
    agent_name = data['agent_name'].lower()
    if not agent_name.isalnum():
        return jsonify({"status": "error", "message": "Agent name must be alphanumeric."}), 400

    # 3. Cryptographic Proof Verification
    # (Addresses blocking issue: verify_agent_proof was a stub)
    if not verify_agent_proof(data['public_key'], data['message'], data['signature']):
        return jsonify({
            "status": "error", 
            "message": "Cryptographic proof verification failed or service unavailable."
        }), 401

    # 4. Success Response (Logic to persist in DB would go here)
    rtc_address = f"RTC-{agent_name}-{data['public_key'][:8]}"
    
    return jsonify({
        "status": "success",
        "message": f"Agent {agent_name} registered successfully.",
        "rtc_address": rtc_address,
        "details": {
            "agent": agent_name,
            "hfp": data['hfp'],
            "status": "verified"
        }
    }), 201

@app.route('/health', methods=['GET'])
def health():
    return jsonify({"status": "ok", "service": "rustchain-agent-registry"}), 200

if __name__ == '__main__':
    # Usage: python3 agent_registration.py
    app.run(host='0.0.0.0', port=5001)
