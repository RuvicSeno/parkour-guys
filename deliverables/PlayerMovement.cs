using System.Collections.Generic;
using UnityEngine;

namespace GameNetworking.Lab7
{
    /// <summary>
    /// Server-to-Client authoritative state packet.
    /// Broadcast by the server after processing client input commands.
    /// </summary>
    [System.Serializable]
    public struct ServerStateSnapshot
    {
        public uint lastProcessedSequenceNumber;
        public Vector3 position;
        public Vector3 velocity;
        public float timestamp;

        public ServerStateSnapshot(uint lastProcessedSequenceNumber, Vector3 position, Vector3 velocity, float timestamp)
        {
            this.lastProcessedSequenceNumber = lastProcessedSequenceNumber;
            this.position = position;
            this.velocity = velocity;
            this.timestamp = timestamp;
        }
    }

    /// <summary>
    /// PlayerMovement Controller implementing:
    /// 1. Toggleable Client-Side Prediction (Mode On/Off)
    /// 2. Immediate local movement prediction on client frames
    /// 3. Remote input command transmission to the authoritative server
    /// 4. Authoritative server physics processing
    /// 5. Client-side reconciliation with error replay and smooth drift correction (lerping)
    /// </summary>
    [RequireComponent(typeof(PlayerInput))]
    public class PlayerMovement : MonoBehaviour
    {
        [Header("Networking Mode")]
        [Tooltip("Toggle between Client-Predicted movement (instant response) and Standard Server-Authoritative (delayed response)")]
        [SerializeField] private bool isPredictionEnabled = true;

        [Header("Player Role")]
        public bool isLocalPlayer = true;
        public bool isServer = false;

        [Header("Movement Settings")]
        [SerializeField] private float moveSpeed = 5.5f;
        [SerializeField] private float jumpVelocity = 6.0f;
        [SerializeField] private float gravity = 9.81f;
        [SerializeField] private CharacterController characterController;

        [Header("Reconciliation Settings")]
        [Tooltip("Speed at which position error discrepancies are smoothly corrected to avoid snap jitter.")]
        [SerializeField] private float reconciliationSpeed = 15f;
        [Tooltip("Threshold error in meters before initiating smooth reconciliation.")]
        [SerializeField] private float reconciliationThreshold = 0.05f;
        [Tooltip("Teleport threshold: if drift exceeds this distance (e.g. wall teleport), snap immediately.")]
        [SerializeField] private float hardSnapThreshold = 5.0f;

        // References & State Tracking
        private PlayerInput _playerInput;
        private Vector3 _verticalVelocity = Vector3.ZERO;
        private Vector3 _correctedServerPosition;
        private bool _isReconciling = false;

        // Server authoritative state
        private uint _serverLastProcessedSequence = 0;
        private Vector3 _serverAuthoritativePosition;

        // Metrics for Lab Report
        public float LastCorrectionErrorMagnitude { get; private set; } = 0f;
        public int TotalReconciliationsPerformed { get; private set; } = 0;

        public bool IsPredictionEnabled => isPredictionEnabled;

        private void Awake()
        {
            _playerInput = GetComponent<PlayerInput>();
            if (characterController == null)
            {
                characterController = GetComponent<CharacterController>();
            }
            _correctedServerPosition = transform.position;
            _serverAuthoritativePosition = transform.position;
        }

        /// <summary>
        /// Toggles Client Prediction Mode for testing and performance comparative analysis (Deliverable 2).
        /// </summary>
        public void TogglePrediction(bool enable)
        {
            isPredictionEnabled = enable;
            _playerInput.Buffer.Clear();
            _isReconciling = false;
            Debug.Log($"[Client Prediction] Prediction Mode is now {(isPredictionEnabled ? "ENABLED (Instant Feedback)" : "DISABLED (Server Echo / Input Lag)")}");
        }

        private void Update()
        {
            // Keyboard shortcut for quick testing in play mode
            if (Input.GetKeyDown(KeyCode.F1) || Input.GetKeyDown(KeyCode.P))
            {
                TogglePrediction(!isPredictionEnabled);
            }

            if (!isLocalPlayer) return;

            // Step 3: Capture local inputs and assign sequential sequenceNumber
            float dt = Time.deltaTime;
            InputCommand command = _playerInput.CaptureCurrentInput(dt);

            if (isPredictionEnabled)
            {
                // =================================================================
                // CLIENT PREDICTION ENABLED:
                // Immediately apply movement locally without waiting for server RTT.
                // =================================================================
                ApplyLocalMovement(command);

                // Buffer the pending unacknowledged command
                _playerInput.Buffer.Enqueue(command);

                // Transmit command to server
                SendCommandToServer(command);
            }
            else
            {
                // =================================================================
                // CLIENT PREDICTION DISABLED (Standard Server-Authoritative baseline):
                // Do NOT move locally! Transmit input to server and wait for the echo.
                // This produces the 150-250ms input delay baseline described in Lab 7.
                // =================================================================
                SendCommandToServer(command);
            }

            // Step 5.4: Smoothly interpolate (lerp) to correct minor drift without harsh visual snapping
            if (_isReconciling)
            {
                transform.position = Vector3.Lerp(
                    transform.position,
                    _correctedServerPosition,
                    Time.deltaTime * reconciliationSpeed
                );

                if (Vector3.Distance(transform.position, _correctedServerPosition) < 0.01f)
                {
                    transform.position = _correctedServerPosition;
                    _isReconciling = false;
                }
            }
        }

        /// <summary>
        /// Calculates and applies character displacement based on an input command.
        /// </summary>
        private void ApplyLocalMovement(InputCommand cmd)
        {
            Vector3 moveDirection = cmd.GetMovementDirection();
            Vector3 horizontalMove = moveDirection * (moveSpeed * cmd.deltaTime);

            // Gravity & Jump Physics Simulation
            if (characterController != null && characterController.isGrounded)
            {
                if (cmd.jump)
                {
                    _verticalVelocity.y = jumpVelocity;
                }
                else
                {
                    _verticalVelocity.y = -1.0f; // slight grounding force
                }
            }
            else
            {
                _verticalVelocity.y -= gravity * cmd.deltaTime;
            }

            Vector3 totalDisplacement = horizontalMove + _verticalVelocity * cmd.deltaTime;

            if (characterController != null)
            {
                characterController.Move(totalDisplacement);
            }
            else
            {
                transform.position += totalDisplacement;
            }
        }

        /// <summary>
        /// Sends the InputCommand to the server via RPC / network messaging (Step 3.4).
        /// </summary>
        private void SendCommandToServer(InputCommand cmd)
        {
            // In a networked project, invoke the server RPC:
            // ServerRpcReceiveInputCommand(cmd);
            
            // For local simulation or host-mode testing:
            if (isServer)
            {
                ServerProcessInputCommand(cmd);
            }
        }

        // =========================================================================
        // STEP 4: SERVER-SIDE AUTHORIZATION & STATE BROADCASTING
        // =========================================================================

        /// <summary>
        /// Server receives the client's input command, runs authoritative physics,
        /// and broadcasts the authoritative position with the last processed sequence number.
        /// </summary>
        public void ServerProcessInputCommand(InputCommand cmd)
        {
            _serverLastProcessedSequence = cmd.sequenceNumber;

            // Authoritative server physics simulation step
            Vector3 moveDirection = cmd.GetMovementDirection();
            Vector3 displacement = moveDirection * (moveSpeed * cmd.deltaTime);
            _serverAuthoritativePosition += displacement;

            // Package authoritative state
            ServerStateSnapshot snapshot = new ServerStateSnapshot(
                _serverLastProcessedSequence,
                _serverAuthoritativePosition,
                moveDirection * moveSpeed,
                Time.time
            );

            // Broadcast back to client (Step 4.3)
            OnServerStateReceived(snapshot);
        }

        // =========================================================================
        // STEP 5: CLIENT-SIDE RECONCILIATION
        // =========================================================================

        /// <summary>
        /// Client receives the authoritative server state update.
        /// Verifies prediction, drops acknowledged inputs, and replays unacknowledged inputs.
        /// </summary>
        public void OnServerStateReceived(ServerStateSnapshot snapshot)
        {
            if (!isLocalPlayer) return;

            if (!isPredictionEnabled)
            {
                // Prediction disabled: directly receive server position (shows visual latency delay)
                transform.position = snapshot.position;
                return;
            }

            // Step 5.1 & 5.2: Read authoritative position and find sequence in buffer
            uint lastAckSeq = snapshot.lastProcessedSequenceNumber;

            // Step 5.3: Drop all older inputs up to that sequence number
            _playerInput.Buffer.RemoveAcknowledged(lastAckSeq);

            // Reconciliation Logic: Re-run (replay) remaining unacknowledged inputs
            // starting from the server's authoritative position.
            Vector3 replayedPosition = snapshot.position;
            IReadOnlyList<InputCommand> pendingCommands = _playerInput.Buffer.GetPendingCommands();

            for (int i = 0; i < pendingCommands.Count; i++)
            {
                InputCommand pendingCmd = pendingCommands[i];
                Vector3 moveDir = pendingCmd.GetMovementDirection();
                replayedPosition += moveDir * (moveSpeed * pendingCmd.deltaTime);
            }

            // Check if there is an error discrepancy between predicted position and replayed truth
            float driftError = Vector3.Distance(transform.position, replayedPosition);
            LastCorrectionErrorMagnitude = driftError;

            if (driftError > hardSnapThreshold)
            {
                // Hard snap for large teleports / void falls
                transform.position = replayedPosition;
                _correctedServerPosition = replayedPosition;
                _isReconciling = false;
            }
            else if (driftError > reconciliationThreshold)
            {
                // Step 5.4: Smoothly interpolate (lerp) character to avoid harsh snapping / rubber-banding
                _correctedServerPosition = replayedPosition;
                _isReconciling = true;
                TotalReconciliationsPerformed++;
            }
            else
            {
                // Minor drift within tolerance: no jarring correction needed
                _isReconciling = false;
            }
        }
    }
}
