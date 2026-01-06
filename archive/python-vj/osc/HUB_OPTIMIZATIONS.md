# OSC Hub Optimization Ideas (Not Implemented)

- Decouple the liblo receive callback from forwarding/dispatch via a bounded queue to smooth bursts and avoid blocking the receive thread.
- Add rate-limited logging for forward/handler errors to prevent log storms if a target goes down or a handler throws repeatedly.
- Batch multiple incoming messages into a single bundle per tick/window when traffic is high to reduce per-send overhead.
- Track overload metrics (queue depth, drop counts) to help tune backpressure policies.
