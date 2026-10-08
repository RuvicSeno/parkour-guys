using System;
using System.Collections.Generic;
using UnityEngine;

namespace GameNetworking.Lab7
{
    /// <summary>
    /// Lightweight serializable data structure to store player input state
    /// alongside a sequential sequence number, timestamp, and frame delta time.
    /// Used for client-side prediction, command transmission, and server reconciliation.
    /// </summary>
    [Serializable]
    public struct InputCommand
    {
        public uint sequenceNumber;
        public float timestamp;
        public float horizontal;
        public float vertical;
        public bool jump;
        public float deltaTime;

        public InputCommand(uint sequenceNumber, float timestamp, float horizontal, float vertical, bool jump, float deltaTime)
        {
            this.sequenceNumber = sequenceNumber;
            this.timestamp = timestamp;
            this.horizontal = horizontal;
            this.vertical = vertical;
            this.jump = jump;
            this.deltaTime = deltaTime;
        }

        /// <summary>
        /// Returns a normalized 2D/3D horizontal movement direction vector.
        /// </summary>
        public Vector3 GetMovementDirection()
        {
            Vector3 dir = new Vector3(horizontal, 0f, vertical);
            if (dir.sqrMagnitude > 1f)
            {
                dir.Normalize();
            }
            return dir;
        }

        public bool HasMovement()
        {
            return Mathf.Abs(horizontal) > 0.001f || Mathf.Abs(vertical) > 0.001f || jump;
        }

        public override string ToString()
        {
            return $"[Seq: {sequenceNumber}, Time: {timestamp:F3}, Input: ({horizontal:F2}, {vertical:F2}), Jump: {jump}]";
        }
    }

    /// <summary>
    /// Thread-safe / memory-efficient buffer queue to store unacknowledged local input commands.
    /// Automatically discards commands that have been processed and confirmed by the server.
    /// </summary>
    public class InputHistoryBuffer
    {
        private readonly List<InputCommand> _buffer;
        private readonly int _maxBufferSize;

        public InputHistoryBuffer(int maxBufferSize = 256)
        {
            _maxBufferSize = maxBufferSize;
            _buffer = new List<InputCommand>(maxBufferSize);
        }

        public int Count => _buffer.Count;

        /// <summary>
        /// Appends a newly predicted input command to the tail of the buffer.
        /// </summary>
        public void Enqueue(InputCommand command)
        {
            if (_buffer.Count >= _maxBufferSize)
            {
                // Prune oldest if safety capacity is reached
                _buffer.RemoveAt(0);
            }
            _buffer.Add(command);
        }

        /// <summary>
        /// Removes all commands with a sequence number less than or equal to the server's
        /// acknowledged sequence number (Step 5.3: Drop all older inputs up to that sequence number).
        /// </summary>
        public void RemoveAcknowledged(uint lastProcessedSequenceNumber)
        {
            _buffer.RemoveAll(cmd => cmd.sequenceNumber <= lastProcessedSequenceNumber);
        }

        /// <summary>
        /// Returns all remaining unacknowledged inputs in the buffer to be replayed during reconciliation.
        /// </summary>
        public IReadOnlyList<InputCommand> GetPendingCommands()
        {
            return _buffer;
        }

        /// <summary>
        /// Clears all stored commands (e.g. on respawn or hard teleport).
        /// </summary>
        public void Clear()
        {
            _buffer.Clear();
        }
    }

    /// <summary>
    /// Component responsible for capturing local player inputs and packaging them into InputCommands.
    /// Maintains sequence numbering and the local input history buffer queue.
    /// </summary>
    public class PlayerInput : MonoBehaviour
    {
        [Header("Buffer Configuration")]
        [SerializeField] private int maxBufferSize = 256;

        private uint _nextSequenceNumber = 1;
        private InputHistoryBuffer _inputBuffer;

        public InputHistoryBuffer Buffer => _inputBuffer;

        private void Awake()
        {
            _inputBuffer = new InputHistoryBuffer(maxBufferSize);
        }

        /// <summary>
        /// Captures current hardware input axes and packages them into a timestamped InputCommand.
        /// </summary>
        public InputCommand CaptureCurrentInput(float deltaTime)
        {
            float horizontal = Input.GetAxisRaw("Horizontal");
            float vertical = Input.GetAxisRaw("Vertical");
            bool jump = Input.GetButton("Jump");

            InputCommand command = new InputCommand(
                _nextSequenceNumber++,
                Time.time,
                horizontal,
                vertical,
                jump,
                deltaTime
            );

            return command;
        }

        /// <summary>
        /// Resets sequence counter and purges input buffer (e.g., round restart).
        /// </summary>
        public void ResetInputState()
        {
            _nextSequenceNumber = 1;
            _inputBuffer?.Clear();
        }
    }
}
