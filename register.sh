#!/bin/bash
# RustChain Agent Registration Tool - Milestone 1 (Refactored)
# Built by DoctorBot-x402

# --- CONFIGURATION & DEFAULTS ---
AGENT_NAME="doctorbot"
WORK_DIR="."
HFP_FILE="hardware_dna.txt"

# --- ARGUMENT PARSING ---
usage() {
    echo "Usage: $0 [--name <agent_name>] [--hfp <hfp_file>] [--workdir <directory>]"
    echo "Example: $0 --name myagent --hfp ./hardware.txt --workdir ./output"
    exit 1
}

while [[ "$#" -gt 0 ]]; do
    case $1 in
        --name) AGENT_NAME="$2"; shift ;;
        --hfp) HFP_FILE="$2"; shift ;;
        --workdir) WORK_DIR="$2"; shift ;;
        -h|--help) usage ;;
        *) echo "Unknown parameter: $1"; usage ;;
    esac
    shift
done

# Ensure WORK_DIR exists
mkdir -p "$WORK_DIR"

# Resolve HFP_FILE (check relative to workdir if not found in current dir)
if [[ ! -f "$HFP_FILE" && -f "$WORK_DIR/$HFP_FILE" ]]; then
    HFP_FILE="$WORK_DIR/$HFP_FILE"
fi

if [[ ! -f "$HFP_FILE" ]]; then
    echo "❌ Error: HFP file not found: $HFP_FILE"
    echo "Please provide a valid hardware_dna.txt or use --hfp."
    exit 1
fi

HFP=$(cat "$HFP_FILE")

echo "⚕️ RustChain Agent Identity Forge"
echo "--------------------------------"
echo "Agent: $AGENT_NAME"
echo "HFP: $HFP"
echo "Work Dir: $WORK_DIR"

# 1. Normalize name and generate deterministic seed
# Lowercasing name to avoid duplicates and improve determinism (per reviewer suggestion)
AGENT_NAME_LOWER="${AGENT_NAME,,}"
SEED=$(echo -n "${AGENT_NAME_LOWER}${HFP}" | sha256sum | cut -d' ' -f1)
echo "Seed derived: ${SEED:0:16}..."

# 2. Generate Ed25519 Keypair
# NOTE: To be purely deterministic from SEED, we'd need 'cryptography' or 'nacl'.
# We check for these dependencies first.
PRIVATE_KEY="$WORK_DIR/agent_private.pem"
PUBLIC_KEY="$WORK_DIR/agent_public.pem"

PYTHON_DERIVE=$(cat <<EOF
import sys
try:
    from cryptography.hazmat.primitives.asymmetric import ed25519
    from cryptography.hazmat.primitives import serialization
    seed_bytes = bytes.fromhex("$SEED")
    private_key = ed25519.Ed25519PrivateKey.from_private_bytes(seed_bytes[:32])
    
    # Export keys
    with open("$PRIVATE_KEY", "wb") as f:
        f.write(private_key.private_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PrivateFormat.OpenSSH,
            encryption_algorithm=serialization.NoEncryption()
        ))
    with open("$PUBLIC_KEY", "wb") as f:
        f.write(private_key.public_key().public_bytes(
            encoding=serialization.Encoding.PEM,
            format=serialization.PublicFormat.SubjectPublicKeyInfo
        ))
    print("SUCCESS")
except Exception:
    sys.exit(1)
EOF
)

if python3 -c "$PYTHON_DERIVE" 2>/dev/null | grep -q "SUCCESS"; then
    echo "✅ Keys generated deterministically from seed via Python."
else
    echo "⚠️ Warning: 'cryptography' not available. Falling back to fresh OpenSSL keypair."
    echo "   (Note: Identity will not be reproducible without the PEM files)"
    openssl genpkey -algorithm ed25519 -out "$PRIVATE_KEY"
    openssl pkey -in "$PRIVATE_KEY" -pubout -out "$PUBLIC_KEY"
fi

# 3. Derive RTC Vanity Address
# Format: RTC-<name>-<last 8 of pubkey hash>
# Increased suffix length to 8 chars (~32 bits) to reduce collision risk (per reviewer suggestion)
PUB_HASH=$(openssl pkey -in "$PUBLIC_KEY" -pubin -outform DER | sha256sum | cut -d' ' -f1)
VANITY_HASH=${PUB_HASH:0:8}
RTC_ADDRESS="RTC-${AGENT_NAME_LOWER}-${VANITY_HASH}"

echo "--------------------------------"
echo "✅ Identity Created Successfully"
echo "Wallet Address: $RTC_ADDRESS"
echo "Public Key saved to: $PUBLIC_KEY"
echo "--------------------------------"

# Save registration metadata
echo "{\"agent\":\"$AGENT_NAME_LOWER\", \"hfp\":\"$HFP\", \"address\":\"$RTC_ADDRESS\", \"seed\":\"$SEED\", \"status\":\"ready_for_milestone_2\"}" > "$WORK_DIR/registration.json"
