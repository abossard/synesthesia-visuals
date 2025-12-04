#!/usr/bin/env python3
"""
Tests for MIDI Router

Run with: python -m pytest test_midi_router.py -v
Or simply: python test_midi_router.py
"""

import sys
import unittest
import tempfile
import json
from pathlib import Path

# Test imports
from midi_domain import (
    MidiMessage, ToggleConfig, DeviceConfig, RouterConfig,
    MidiMessageType, parse_midi_message, create_midi_bytes,
    should_enhance_message, process_toggle, create_state_sync_messages,
    config_to_dict, config_from_dict
)


class TestMidiMessage(unittest.TestCase):
    """Tests for MidiMessage dataclass."""
    
    def test_note_on_detection(self):
        """is_note_on should detect note on messages."""
        msg = MidiMessage(
            message_type=MidiMessageType.NOTE_ON,
            channel=0,
            note_or_cc=60,
            velocity_or_value=100
        )
        self.assertTrue(msg.is_note_on)
        self.assertFalse(msg.is_note_off)
    
    def test_note_on_zero_velocity(self):
        """Note on with velocity 0 is treated as note off."""
        msg = MidiMessage(
            message_type=MidiMessageType.NOTE_ON,
            channel=0,
            note_or_cc=60,
            velocity_or_value=0
        )
        self.assertFalse(msg.is_note_on)
        self.assertTrue(msg.is_note_off)
    
    def test_note_off_detection(self):
        """is_note_off should detect note off messages."""
        msg = MidiMessage(
            message_type=MidiMessageType.NOTE_OFF,
            channel=0,
            note_or_cc=60,
            velocity_or_value=0
        )
        self.assertTrue(msg.is_note_off)
        self.assertFalse(msg.is_note_on)
    
    def test_control_change_detection(self):
        """is_control_change should detect CC messages."""
        msg = MidiMessage(
            message_type=MidiMessageType.CONTROL_CHANGE,
            channel=0,
            note_or_cc=7,
            velocity_or_value=64
        )
        self.assertTrue(msg.is_control_change)
        self.assertFalse(msg.is_note_on)
        self.assertFalse(msg.is_note_off)
    
    def test_string_representation(self):
        """__str__ should provide human-readable output."""
        msg = MidiMessage(
            message_type=MidiMessageType.NOTE_ON,
            channel=1,
            note_or_cc=60,
            velocity_or_value=100
        )
        s = str(msg)
        self.assertIn("Note On", s)
        self.assertIn("ch1", s)
        self.assertIn("60", s)
        self.assertIn("100", s)


class TestToggleConfig(unittest.TestCase):
    """Tests for ToggleConfig dataclass."""
    
    def test_with_state(self):
        """with_state should create new instance with updated state."""
        toggle = ToggleConfig(note_or_cc=40, name="Test", state=False)
        new_toggle = toggle.with_state(True)
        
        # Original unchanged
        self.assertFalse(toggle.state)
        # New instance updated
        self.assertTrue(new_toggle.state)
        # Other fields preserved
        self.assertEqual(new_toggle.note_or_cc, 40)
        self.assertEqual(new_toggle.name, "Test")
    
    def test_toggle(self):
        """toggle should flip state."""
        toggle = ToggleConfig(note_or_cc=40, name="Test", state=False)
        
        new_toggle = toggle.toggle()
        self.assertTrue(new_toggle.state)
        
        newer_toggle = new_toggle.toggle()
        self.assertFalse(newer_toggle.state)
    
    def test_key_property(self):
        """key should return unique identifier."""
        toggle = ToggleConfig(note_or_cc=40, name="Test", message_type='note')
        self.assertEqual(toggle.key, "note_40")
        
        toggle_cc = ToggleConfig(note_or_cc=7, name="Test", message_type='cc')
        self.assertEqual(toggle_cc.key, "cc_7")
    
    def test_current_led_velocity(self):
        """current_led_velocity should return velocity for current state."""
        toggle = ToggleConfig(
            note_or_cc=40,
            name="Test",
            state=False,
            led_on_velocity=127,
            led_off_velocity=0
        )
        
        self.assertEqual(toggle.current_led_velocity, 0)
        
        toggle_on = toggle.with_state(True)
        self.assertEqual(toggle_on.current_led_velocity, 127)
    
    def test_current_output_velocity(self):
        """current_output_velocity should return velocity for output."""
        toggle = ToggleConfig(
            note_or_cc=40,
            name="Test",
            state=False,
            output_on_velocity=127,
            output_off_velocity=0
        )
        
        self.assertEqual(toggle.current_output_velocity, 0)
        
        toggle_on = toggle.with_state(True)
        self.assertEqual(toggle_on.current_output_velocity, 127)


class TestRouterConfig(unittest.TestCase):
    """Tests for RouterConfig dataclass."""
    
    def test_with_toggle(self):
        """with_toggle should add/update toggle."""
        config = RouterConfig(
            controller=DeviceConfig(name_pattern="Test"),
            virtual_output=DeviceConfig(name_pattern="Virtual"),
            toggles={}
        )
        
        toggle = ToggleConfig(note_or_cc=40, name="Test")
        new_config = config.with_toggle(toggle)
        
        self.assertEqual(len(new_config.toggles), 1)
        self.assertIn(40, new_config.toggles)
    
    def test_get_toggle(self):
        """get_toggle should retrieve toggle by note."""
        toggle = ToggleConfig(note_or_cc=40, name="Test")
        config = RouterConfig(
            controller=DeviceConfig(name_pattern="Test"),
            virtual_output=DeviceConfig(name_pattern="Virtual"),
            toggles={40: toggle}
        )
        
        retrieved = config.get_toggle(40)
        self.assertEqual(retrieved, toggle)
        
        self.assertIsNone(config.get_toggle(99))
    
    def test_has_toggle(self):
        """has_toggle should check toggle existence."""
        toggle = ToggleConfig(note_or_cc=40, name="Test")
        config = RouterConfig(
            controller=DeviceConfig(name_pattern="Test"),
            virtual_output=DeviceConfig(name_pattern="Virtual"),
            toggles={40: toggle}
        )
        
        self.assertTrue(config.has_toggle(40))
        self.assertFalse(config.has_toggle(99))


class TestMidiParsing(unittest.TestCase):
    """Tests for MIDI message parsing."""
    
    def test_parse_note_on(self):
        """parse_midi_message should parse note on."""
        msg = parse_midi_message(0x90, 60, 100)  # Note on, ch 0, note 60, vel 100
        
        self.assertEqual(msg.message_type, MidiMessageType.NOTE_ON)
        self.assertEqual(msg.channel, 0)
        self.assertEqual(msg.note_or_cc, 60)
        self.assertEqual(msg.velocity_or_value, 100)
    
    def test_parse_note_off(self):
        """parse_midi_message should parse note off."""
        msg = parse_midi_message(0x80, 60, 0)  # Note off, ch 0, note 60
        
        self.assertEqual(msg.message_type, MidiMessageType.NOTE_OFF)
        self.assertEqual(msg.channel, 0)
        self.assertEqual(msg.note_or_cc, 60)
    
    def test_parse_control_change(self):
        """parse_midi_message should parse CC."""
        msg = parse_midi_message(0xB0, 7, 64)  # CC, ch 0, CC 7, value 64
        
        self.assertEqual(msg.message_type, MidiMessageType.CONTROL_CHANGE)
        self.assertEqual(msg.channel, 0)
        self.assertEqual(msg.note_or_cc, 7)
        self.assertEqual(msg.velocity_or_value, 64)
    
    def test_parse_with_channel(self):
        """parse_midi_message should extract channel."""
        msg = parse_midi_message(0x93, 60, 100)  # Note on, ch 3
        
        self.assertEqual(msg.message_type, MidiMessageType.NOTE_ON)
        self.assertEqual(msg.channel, 3)
    
    def test_create_midi_bytes(self):
        """create_midi_bytes should convert back to bytes."""
        msg = MidiMessage(
            message_type=MidiMessageType.NOTE_ON,
            channel=3,
            note_or_cc=60,
            velocity_or_value=100
        )
        
        status, data1, data2 = create_midi_bytes(msg)
        
        self.assertEqual(status, 0x93)  # NOTE_ON | channel 3
        self.assertEqual(data1, 60)
        self.assertEqual(data2, 100)
    
    def test_roundtrip(self):
        """Parse and create should roundtrip."""
        original = parse_midi_message(0x93, 60, 100)
        status, data1, data2 = create_midi_bytes(original)
        roundtrip = parse_midi_message(status, data1, data2)
        
        self.assertEqual(original, roundtrip)


class TestToggleLogic(unittest.TestCase):
    """Tests for toggle processing logic."""
    
    def test_should_enhance_message_note_on(self):
        """should_enhance_message should detect toggle note on."""
        toggle = ToggleConfig(note_or_cc=40, name="Test")
        config = RouterConfig(
            controller=DeviceConfig(name_pattern="Test"),
            virtual_output=DeviceConfig(name_pattern="Virtual"),
            toggles={40: toggle}
        )
        
        msg = MidiMessage(
            message_type=MidiMessageType.NOTE_ON,
            channel=0,
            note_or_cc=40,
            velocity_or_value=100
        )
        
        self.assertTrue(should_enhance_message(msg, config))
    
    def test_should_enhance_message_note_off(self):
        """should_enhance_message should ignore note off."""
        toggle = ToggleConfig(note_or_cc=40, name="Test")
        config = RouterConfig(
            controller=DeviceConfig(name_pattern="Test"),
            virtual_output=DeviceConfig(name_pattern="Virtual"),
            toggles={40: toggle}
        )
        
        msg = MidiMessage(
            message_type=MidiMessageType.NOTE_OFF,
            channel=0,
            note_or_cc=40,
            velocity_or_value=0
        )
        
        self.assertFalse(should_enhance_message(msg, config))
    
    def test_should_enhance_message_unknown_note(self):
        """should_enhance_message should ignore unconfigured notes."""
        toggle = ToggleConfig(note_or_cc=40, name="Test")
        config = RouterConfig(
            controller=DeviceConfig(name_pattern="Test"),
            virtual_output=DeviceConfig(name_pattern="Virtual"),
            toggles={40: toggle}
        )
        
        msg = MidiMessage(
            message_type=MidiMessageType.NOTE_ON,
            channel=0,
            note_or_cc=99,
            velocity_or_value=100
        )
        
        self.assertFalse(should_enhance_message(msg, config))
    
    def test_process_toggle_off_to_on(self):
        """process_toggle should flip state OFF -> ON."""
        toggle = ToggleConfig(
            note_or_cc=40,
            name="Test",
            state=False,
            led_on_velocity=127,
            led_off_velocity=0,
            output_on_velocity=127,
            output_off_velocity=0
        )
        config = RouterConfig(
            controller=DeviceConfig(name_pattern="Test"),
            virtual_output=DeviceConfig(name_pattern="Virtual"),
            toggles={40: toggle}
        )
        
        msg = MidiMessage(
            message_type=MidiMessageType.NOTE_ON,
            channel=0,
            note_or_cc=40,
            velocity_or_value=100
        )
        
        new_config, led_msg, output_msg = process_toggle(msg, config)
        
        # Config updated
        new_toggle = new_config.get_toggle(40)
        self.assertTrue(new_toggle.state)
        
        # LED message has ON velocity
        self.assertEqual(led_msg.velocity_or_value, 127)
        
        # Output message has ON velocity
        self.assertEqual(output_msg.velocity_or_value, 127)
    
    def test_process_toggle_on_to_off(self):
        """process_toggle should flip state ON -> OFF."""
        toggle = ToggleConfig(
            note_or_cc=40,
            name="Test",
            state=True,
            led_on_velocity=127,
            led_off_velocity=0,
            output_on_velocity=127,
            output_off_velocity=0
        )
        config = RouterConfig(
            controller=DeviceConfig(name_pattern="Test"),
            virtual_output=DeviceConfig(name_pattern="Virtual"),
            toggles={40: toggle}
        )
        
        msg = MidiMessage(
            message_type=MidiMessageType.NOTE_ON,
            channel=0,
            note_or_cc=40,
            velocity_or_value=100
        )
        
        new_config, led_msg, output_msg = process_toggle(msg, config)
        
        # Config updated
        new_toggle = new_config.get_toggle(40)
        self.assertFalse(new_toggle.state)
        
        # LED message has OFF velocity
        self.assertEqual(led_msg.velocity_or_value, 0)
        
        # Output message has OFF velocity
        self.assertEqual(output_msg.velocity_or_value, 0)
    
    def test_process_toggle_immutable(self):
        """process_toggle should not mutate original config."""
        toggle = ToggleConfig(note_or_cc=40, name="Test", state=False)
        config = RouterConfig(
            controller=DeviceConfig(name_pattern="Test"),
            virtual_output=DeviceConfig(name_pattern="Virtual"),
            toggles={40: toggle}
        )
        
        msg = MidiMessage(
            message_type=MidiMessageType.NOTE_ON,
            channel=0,
            note_or_cc=40,
            velocity_or_value=100
        )
        
        new_config, _, _ = process_toggle(msg, config)
        
        # Original config unchanged
        original_toggle = config.get_toggle(40)
        self.assertFalse(original_toggle.state)
        
        # New config updated
        new_toggle = new_config.get_toggle(40)
        self.assertTrue(new_toggle.state)


class TestStateSyncMessages(unittest.TestCase):
    """Tests for state sync message generation."""
    
    def test_create_state_sync_messages_empty(self):
        """create_state_sync_messages should handle empty toggles."""
        config = RouterConfig(
            controller=DeviceConfig(name_pattern="Test"),
            virtual_output=DeviceConfig(name_pattern="Virtual"),
            toggles={}
        )
        
        messages = create_state_sync_messages(config)
        self.assertEqual(len(messages), 0)
    
    def test_create_state_sync_messages_single(self):
        """create_state_sync_messages should create message pair."""
        toggle = ToggleConfig(
            note_or_cc=40,
            name="Test",
            state=True,
            led_on_velocity=127,
            output_on_velocity=127
        )
        config = RouterConfig(
            controller=DeviceConfig(name_pattern="Test"),
            virtual_output=DeviceConfig(name_pattern="Virtual"),
            toggles={40: toggle}
        )
        
        messages = create_state_sync_messages(config)
        
        self.assertEqual(len(messages), 1)
        led_msg, output_msg = messages[0]
        
        # LED message
        self.assertEqual(led_msg.note_or_cc, 40)
        self.assertEqual(led_msg.velocity_or_value, 127)
        
        # Output message
        self.assertEqual(output_msg.note_or_cc, 40)
        self.assertEqual(output_msg.velocity_or_value, 127)
    
    def test_create_state_sync_messages_multiple(self):
        """create_state_sync_messages should handle multiple toggles."""
        config = RouterConfig(
            controller=DeviceConfig(name_pattern="Test"),
            virtual_output=DeviceConfig(name_pattern="Virtual"),
            toggles={
                40: ToggleConfig(note_or_cc=40, name="T1", state=False),
                41: ToggleConfig(note_or_cc=41, name="T2", state=True),
                42: ToggleConfig(note_or_cc=42, name="T3", state=False),
            }
        )
        
        messages = create_state_sync_messages(config)
        
        self.assertEqual(len(messages), 3)


class TestConfigSerialization(unittest.TestCase):
    """Tests for config serialization."""
    
    def test_config_to_dict(self):
        """config_to_dict should create serializable dict."""
        toggle = ToggleConfig(
            note_or_cc=40,
            name="TwisterOn",
            state=True,
            message_type='note',
            led_on_velocity=127,
            led_off_velocity=0,
            output_on_velocity=127,
            output_off_velocity=0
        )
        config = RouterConfig(
            controller=DeviceConfig(name_pattern="Launchpad"),
            virtual_output=DeviceConfig(name_pattern="MagicBus"),
            toggles={40: toggle}
        )
        
        data = config_to_dict(config)
        
        self.assertIn('controller', data)
        self.assertIn('virtual_output', data)
        self.assertIn('toggles', data)
        self.assertEqual(data['controller']['name_pattern'], "Launchpad")
        self.assertIn('40', data['toggles'])
        self.assertEqual(data['toggles']['40']['name'], "TwisterOn")
        self.assertTrue(data['toggles']['40']['state'])
    
    def test_config_from_dict(self):
        """config_from_dict should recreate config."""
        data = {
            "controller": {
                "name_pattern": "Launchpad",
                "input_port": None,
                "output_port": None
            },
            "virtual_output": {
                "name_pattern": "MagicBus",
                "input_port": None,
                "output_port": None
            },
            "toggles": {
                "40": {
                    "name": "TwisterOn",
                    "state": True,
                    "message_type": "note",
                    "led_on_velocity": 127,
                    "led_off_velocity": 0,
                    "output_on_velocity": 127,
                    "output_off_velocity": 0
                }
            }
        }
        
        config = config_from_dict(data)
        
        self.assertEqual(config.controller.name_pattern, "Launchpad")
        self.assertEqual(config.virtual_output.name_pattern, "MagicBus")
        self.assertEqual(len(config.toggles), 1)
        
        toggle = config.get_toggle(40)
        self.assertIsNotNone(toggle)
        self.assertEqual(toggle.name, "TwisterOn")
        self.assertTrue(toggle.state)
    
    def test_roundtrip_serialization(self):
        """Config should roundtrip through dict."""
        original = RouterConfig(
            controller=DeviceConfig(name_pattern="Launchpad"),
            virtual_output=DeviceConfig(name_pattern="MagicBus"),
            toggles={
                40: ToggleConfig(note_or_cc=40, name="T1", state=False),
                41: ToggleConfig(note_or_cc=41, name="T2", state=True),
            }
        )
        
        data = config_to_dict(original)
        roundtrip = config_from_dict(data)
        
        self.assertEqual(roundtrip.controller.name_pattern, original.controller.name_pattern)
        self.assertEqual(len(roundtrip.toggles), len(original.toggles))
        
        for note in original.toggles:
            orig_toggle = original.get_toggle(note)
            new_toggle = roundtrip.get_toggle(note)
            self.assertEqual(orig_toggle.name, new_toggle.name)
            self.assertEqual(orig_toggle.state, new_toggle.state)


class TestConfigManager(unittest.TestCase):
    """Tests for ConfigManager class."""
    
    def test_save_and_load(self):
        """ConfigManager should save and load config."""
        from midi_router import ConfigManager
        
        with tempfile.TemporaryDirectory() as tmpdir:
            config_path = Path(tmpdir) / "test_config.json"
            manager = ConfigManager(config_path)
            
            # Create config
            config = RouterConfig(
                controller=DeviceConfig(name_pattern="Launchpad"),
                virtual_output=DeviceConfig(name_pattern="MagicBus"),
                toggles={
                    40: ToggleConfig(note_or_cc=40, name="Test", state=True)
                }
            )
            
            # Save
            manager.save(config)
            
            # Load
            loaded = manager.load()
            
            self.assertIsNotNone(loaded)
            self.assertEqual(loaded.controller.name_pattern, "Launchpad")
            self.assertEqual(len(loaded.toggles), 1)
            
            toggle = loaded.get_toggle(40)
            self.assertEqual(toggle.name, "Test")
            self.assertTrue(toggle.state)
    
    def test_load_nonexistent(self):
        """ConfigManager.load should return None for nonexistent file."""
        from midi_router import ConfigManager
        
        with tempfile.TemporaryDirectory() as tmpdir:
            config_path = Path(tmpdir) / "nonexistent.json"
            manager = ConfigManager(config_path)
            
            loaded = manager.load()
            self.assertIsNone(loaded)


class TestControllerDiscovery(unittest.TestCase):
    """Tests for controller discovery functions."""
    
    def test_find_port_by_pattern(self):
        """find_port_by_pattern should match case-insensitively."""
        from midi_infrastructure import find_port_by_pattern
        
        ports = ["Launchpad Mini MK3", "MIDI Mix", "IAC Driver Bus 1"]
        
        # Case-insensitive match
        self.assertEqual(find_port_by_pattern(ports, "launchpad"), "Launchpad Mini MK3")
        self.assertEqual(find_port_by_pattern(ports, "MIDI"), "MIDI Mix")
        self.assertEqual(find_port_by_pattern(ports, "iac"), "IAC Driver Bus 1")
        
        # No match
        self.assertIsNone(find_port_by_pattern(ports, "nonexistent"))
        
        # Empty list
        self.assertIsNone(find_port_by_pattern([], "test"))
    
    def test_list_controllers_no_rtmidi(self):
        """list_controllers should return empty list when rtmidi unavailable."""
        from midi_infrastructure import list_controllers
        
        # This will return empty list in test environment without rtmidi
        controllers = list_controllers()
        self.assertIsInstance(controllers, list)
    
    def test_list_virtual_ports_no_rtmidi(self):
        """list_virtual_ports should return empty list when rtmidi unavailable."""
        from midi_infrastructure import list_virtual_ports
        
        # This will return empty list in test environment without rtmidi
        virtual_ports = list_virtual_ports()
        self.assertIsInstance(virtual_ports, list)


class TestDeviceConfig(unittest.TestCase):
    """Tests for DeviceConfig with explicit ports."""
    
    def test_device_config_with_explicit_ports(self):
        """DeviceConfig should store explicit port names."""
        config = DeviceConfig(
            name_pattern="",
            input_port="Launchpad Mini MK3 MIDI 2",
            output_port="Launchpad Mini MK3 MIDI 2"
        )
        
        self.assertEqual(config.name_pattern, "")
        self.assertEqual(config.input_port, "Launchpad Mini MK3 MIDI 2")
        self.assertEqual(config.output_port, "Launchpad Mini MK3 MIDI 2")
    
    def test_device_config_pattern_only(self):
        """DeviceConfig should work with pattern only."""
        config = DeviceConfig(name_pattern="Launchpad")
        
        self.assertEqual(config.name_pattern, "Launchpad")
        self.assertIsNone(config.input_port)
        self.assertIsNone(config.output_port)


class TestConfigPersistence(unittest.TestCase):
    """Tests for config persistence with controller selection."""
    
    def test_config_saves_explicit_ports(self):
        """Config should save and load explicit port names."""
        from midi_router import ConfigManager
        
        with tempfile.TemporaryDirectory() as tmpdir:
            config_path = Path(tmpdir) / "config.json"
            manager = ConfigManager(config_path)
            
            # Create config with explicit ports
            config = RouterConfig(
                controller=DeviceConfig(
                    name_pattern="",
                    input_port="Launchpad Mini MK3 MIDI 2",
                    output_port="Launchpad Mini MK3 MIDI 2"
                ),
                virtual_output=DeviceConfig(name_pattern="MagicBus"),
                toggles={}
            )
            
            # Save
            manager.save(config)
            
            # Verify file exists and contains correct data
            self.assertTrue(config_path.exists())
            with open(config_path, 'r') as f:
                data = json.load(f)
            
            self.assertEqual(data["controller"]["input_port"], "Launchpad Mini MK3 MIDI 2")
            self.assertEqual(data["controller"]["output_port"], "Launchpad Mini MK3 MIDI 2")
            self.assertEqual(data["controller"]["name_pattern"], "")
            
            # Load
            loaded = manager.load()
            self.assertIsNotNone(loaded)
            self.assertEqual(loaded.controller.input_port, "Launchpad Mini MK3 MIDI 2")
            self.assertEqual(loaded.controller.output_port, "Launchpad Mini MK3 MIDI 2")
    
    def test_config_migration_from_pattern_to_explicit(self):
        """Config should handle migration from pattern to explicit ports."""
        from midi_router import ConfigManager
        
        with tempfile.TemporaryDirectory() as tmpdir:
            config_path = Path(tmpdir) / "config.json"
            manager = ConfigManager(config_path)
            
            # Create initial config with pattern
            old_config = RouterConfig(
                controller=DeviceConfig(name_pattern="Launchpad"),
                virtual_output=DeviceConfig(name_pattern="MagicBus"),
                toggles={
                    40: ToggleConfig(note_or_cc=40, name="Toggle1", state=True)
                }
            )
            
            manager.save(old_config)
            
            # Update to explicit port (simulating controller selection)
            new_config = RouterConfig(
                controller=DeviceConfig(
                    name_pattern="",
                    input_port="Launchpad Mini MK3 MIDI 2",
                    output_port="Launchpad Mini MK3 MIDI 2"
                ),
                virtual_output=old_config.virtual_output,
                toggles=old_config.toggles
            )
            
            manager.save(new_config)
            
            # Load and verify toggles are preserved
            loaded = manager.load()
            self.assertEqual(len(loaded.toggles), 1)
            self.assertTrue(loaded.get_toggle(40).state)
            self.assertEqual(loaded.controller.input_port, "Launchpad Mini MK3 MIDI 2")


class TestRouterConfigUpdate(unittest.TestCase):
    """Tests for updating router config with controller selection."""
    
    def test_router_config_with_explicit_controller(self):
        """RouterConfig should work with explicit controller ports."""
        config = RouterConfig(
            controller=DeviceConfig(
                name_pattern="",
                input_port="Launchpad Mini MK3 MIDI 2",
                output_port="Launchpad Mini MK3 MIDI 2"
            ),
            virtual_output=DeviceConfig(name_pattern="MagicBus"),
            toggles={
                40: ToggleConfig(note_or_cc=40, name="Test", state=False)
            }
        )
        
        self.assertEqual(config.controller.input_port, "Launchpad Mini MK3 MIDI 2")
        self.assertTrue(config.has_toggle(40))
    
    def test_config_serialization_with_explicit_ports(self):
        """config_to_dict should preserve explicit port names."""
        config = RouterConfig(
            controller=DeviceConfig(
                name_pattern="",
                input_port="Launchpad Mini MK3 MIDI 2",
                output_port="Launchpad Mini MK3 MIDI 2"
            ),
            virtual_output=DeviceConfig(name_pattern="MagicBus"),
            toggles={}
        )
        
        data = config_to_dict(config)
        
        self.assertEqual(data["controller"]["name_pattern"], "")
        self.assertEqual(data["controller"]["input_port"], "Launchpad Mini MK3 MIDI 2")
        self.assertEqual(data["controller"]["output_port"], "Launchpad Mini MK3 MIDI 2")
    
    def test_config_deserialization_with_explicit_ports(self):
        """config_from_dict should restore explicit port names."""
        data = {
            "controller": {
                "name_pattern": "",
                "input_port": "Launchpad Mini MK3 MIDI 2",
                "output_port": "Launchpad Mini MK3 MIDI 2"
            },
            "virtual_output": {
                "name_pattern": "MagicBus",
                "input_port": None,
                "output_port": None
            },
            "toggles": {}
        }
        
        config = config_from_dict(data)
        
        self.assertEqual(config.controller.name_pattern, "")
        self.assertEqual(config.controller.input_port, "Launchpad Mini MK3 MIDI 2")
        self.assertEqual(config.controller.output_port, "Launchpad Mini MK3 MIDI 2")


class TestControllerSelectionIntegration(unittest.TestCase):
    """Integration tests for controller selection workflow."""
    
    def test_controller_selection_workflow(self):
        """Test complete workflow: list -> select -> save -> restart."""
        from midi_router import ConfigManager
        from midi_infrastructure import find_port_by_pattern
        
        with tempfile.TemporaryDirectory() as tmpdir:
            config_path = Path(tmpdir) / "config.json"
            manager = ConfigManager(config_path)
            
            # Step 1: Start with pattern-based config
            initial_config = RouterConfig(
                controller=DeviceConfig(name_pattern="Launchpad"),
                virtual_output=DeviceConfig(name_pattern="MagicBus"),
                toggles={}
            )
            manager.save(initial_config)
            
            # Step 2: User selects specific controller
            selected_controller = "Launchpad Mini MK3 MIDI 2"
            
            # Step 3: Update config with explicit port
            updated_config = RouterConfig(
                controller=DeviceConfig(
                    name_pattern="",
                    input_port=selected_controller,
                    output_port=selected_controller
                ),
                virtual_output=initial_config.virtual_output,
                toggles=initial_config.toggles
            )
            manager.save(updated_config)
            
            # Step 4: Reload and verify
            loaded_config = manager.load()
            self.assertEqual(loaded_config.controller.input_port, selected_controller)
            self.assertEqual(loaded_config.controller.output_port, selected_controller)
            self.assertEqual(loaded_config.controller.name_pattern, "")
    
    def test_toggles_preserved_during_controller_change(self):
        """Toggles should be preserved when changing controllers."""
        from midi_router import ConfigManager
        
        with tempfile.TemporaryDirectory() as tmpdir:
            config_path = Path(tmpdir) / "config.json"
            manager = ConfigManager(config_path)
            
            # Create config with toggles
            config_with_toggles = RouterConfig(
                controller=DeviceConfig(name_pattern="Launchpad"),
                virtual_output=DeviceConfig(name_pattern="MagicBus"),
                toggles={
                    40: ToggleConfig(note_or_cc=40, name="Toggle1", state=True),
                    41: ToggleConfig(note_or_cc=41, name="Toggle2", state=False),
                    42: ToggleConfig(note_or_cc=42, name="Toggle3", state=True),
                }
            )
            manager.save(config_with_toggles)
            
            # Change controller
            new_config = RouterConfig(
                controller=DeviceConfig(
                    name_pattern="",
                    input_port="MIDI Mix",
                    output_port="MIDI Mix"
                ),
                virtual_output=config_with_toggles.virtual_output,
                toggles=config_with_toggles.toggles
            )
            manager.save(new_config)
            
            # Verify toggles preserved
            loaded = manager.load()
            self.assertEqual(len(loaded.toggles), 3)
            self.assertEqual(loaded.get_toggle(40).name, "Toggle1")
            self.assertTrue(loaded.get_toggle(40).state)
            self.assertEqual(loaded.get_toggle(41).name, "Toggle2")
            self.assertFalse(loaded.get_toggle(41).state)
            self.assertEqual(loaded.get_toggle(42).name, "Toggle3")
            self.assertTrue(loaded.get_toggle(42).state)


class TestOSCBroadcasting(unittest.TestCase):
    """Tests for OSC broadcasting integration."""
    
    def test_osc_import_graceful_degradation(self):
        """OSC module should be optional - graceful degradation if unavailable."""
        # This test verifies that the router can run without OSC
        # The actual OSC broadcasting is tested in integration tests
        # since it requires the osc_manager module
        
        import midi_router
        
        # Check that OSC_AVAILABLE flag exists
        self.assertTrue(hasattr(midi_router, 'OSC_AVAILABLE'))
        
        # If OSC is available, osc should not be None
        if midi_router.OSC_AVAILABLE:
            self.assertIsNotNone(midi_router.osc)
        else:
            self.assertIsNone(midi_router.osc)
    
    def test_osc_addresses_documented(self):
        """Verify OSC address patterns are correctly documented."""
        # This is a documentation test to ensure consistency
        # Expected OSC addresses:
        # - /midi/toggle/{note}  [name, state]
        # - /midi/learn  [note, name]
        # - /midi/sync  [count]
        
        # These addresses are used in midi_router.py
        # Verify they match documentation expectations
        expected_patterns = [
            "/midi/toggle/",
            "/midi/learn",
            "/midi/sync"
        ]
        
        # Read midi_router.py source to verify addresses
        import midi_router as mr
        import inspect
        
        source = inspect.getsource(mr)
        
        for pattern in expected_patterns:
            self.assertIn(pattern, source, 
                         f"OSC address pattern '{pattern}' not found in source")


if __name__ == "__main__":
    # Run tests
    unittest.main(verbosity=2)
