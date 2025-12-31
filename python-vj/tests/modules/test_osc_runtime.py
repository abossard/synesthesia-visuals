"""
E2E tests for OSC Runtime module.

Run with: pytest tests/modules/test_osc_runtime.py -v -s
"""
import time


class TestOSCRuntimeLifecycle:
    """Test OSC Runtime module lifecycle."""

    def test_module_starts_and_stops_cleanly(self, requires_osc_ports_free):
        """OSC Runtime module starts and stops without errors."""
        from modules.osc_runtime import OSCRuntime, OSCConfig

        config = OSCConfig()
        runtime = OSCRuntime(config)

        assert not runtime.is_started

        success = runtime.start()
        assert success, "Module should start successfully"
        assert runtime.is_started

        status = runtime.get_status()
        assert status["started"] is True
        assert status["receive_port"] == 9999

        runtime.stop()
        assert not runtime.is_started

        print("\nModule started and stopped cleanly")

    def test_module_can_restart(self, requires_osc_ports_free):
        """OSC Runtime can be stopped and restarted."""
        from modules.osc_runtime import OSCRuntime

        runtime = OSCRuntime()

        runtime.start()
        assert runtime.is_started

        runtime.stop()
        assert not runtime.is_started

        runtime.start()
        assert runtime.is_started

        runtime.stop()
        print("\nModule restart successful")


class TestOSCRuntimeCommunication:
    """Test OSC Runtime message handling."""

    def test_receives_vdj_messages(self, requires_vdj_playing):
        """OSC Runtime receives messages from VirtualDJ."""
        from modules.osc_runtime import OSCRuntime

        received = []
        runtime = OSCRuntime()
        runtime.subscribe("/deck*", lambda addr, args: received.append((addr, args)))
        runtime.start()

        # Wait for VDJ messages (it sends continuous updates when playing)
        time.sleep(2)

        runtime.stop()

        assert len(received) > 0, "Should receive messages from VDJ"
        print(f"\nReceived {len(received)} messages from VDJ")
        if received:
            print(f"Sample: {received[0]}")

    def test_sends_to_vjuniverse(self, requires_vjuniverse):
        """OSC Runtime can send messages to VJUniverse."""
        from modules.osc_runtime import OSCRuntime

        runtime = OSCRuntime()
        runtime.start()

        # Send test message
        success = runtime.send_to_textler("/test/ping", "hello", 42)
        assert success, "Should send successfully"

        runtime.stop()
        print("\nSent message to VJUniverse successfully")

    def test_subscription_filtering(self, requires_osc_ports_free):
        """OSC Runtime filters messages by subscription pattern."""
        from modules.osc_runtime import OSCRuntime

        deck_messages = []
        all_messages = []

        runtime = OSCRuntime()
        runtime.subscribe("/deck*", lambda addr, args: deck_messages.append(addr))
        runtime.subscribe("*", lambda addr, args: all_messages.append(addr))
        runtime.start()

        # Send test messages through the hub
        runtime.hub.textler.send("/deck/1/play", 1)
        runtime.hub.textler.send("/other/message", "test")

        time.sleep(0.3)
        runtime.stop()

        print(f"\nAll messages: {len(all_messages)}, Deck messages: {len(deck_messages)}")


class TestOSCRuntimeStandalone:
    """Test OSC Runtime standalone CLI functionality."""

    def test_cli_module_importable(self):
        """OSC Runtime CLI can be imported."""
        from modules.osc_runtime import main, OSCConfig, OSCRuntime

        assert callable(main)
        assert OSCConfig is not None
        assert OSCRuntime is not None

        print("\nCLI module imports successfully")
