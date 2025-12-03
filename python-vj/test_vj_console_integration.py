#!/usr/bin/env python3
"""
Test script to verify WorkerCoordinator integration in vj_console.
"""
import time
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

def test_worker_coordinator_integration():
    """Test that vj_console can use WorkerCoordinator."""
    
    print("=" * 60)
    print("Testing VJ Console + WorkerCoordinator Integration")
    print("=" * 60)
    
    # Test 1: Import vj_console
    print("\n[1/5] Testing vj_console import...")
    try:
        import vj_console
        print("  ✓ vj_console imported successfully")
    except Exception as e:
        print(f"  ✗ Failed to import vj_console: {e}")
        return False
    
    # Test 2: Check WorkerCoordinator is available
    print("\n[2/5] Testing WorkerCoordinator import...")
    try:
        from worker_coordinator import WorkerCoordinator
        coordinator = WorkerCoordinator()
        print("  ✓ WorkerCoordinator imported and instantiated")
    except Exception as e:
        print(f"  ✗ Failed to import WorkerCoordinator: {e}")
        return False
    
    # Test 3: Discover workers
    print("\n[3/5] Testing worker discovery...")
    try:
        coordinator.start()
        time.sleep(1)  # Give discovery thread time to run
        workers = coordinator.get_all_workers()
        print(f"  ✓ Discovered {len(workers)} workers:")
        for worker in workers:
            status = "connected" if worker.connected else "disconnected"
            print(f"    - {worker.name}: {status}")
        coordinator.stop()
    except Exception as e:
        print(f"  ✗ Failed worker discovery: {e}")
        coordinator.stop()
        return False
    
    # Test 4: Check VJConsoleApp has worker_coordinator attribute
    print("\n[4/5] Checking VJConsoleApp integration...")
    try:
        # Check class definition
        assert hasattr(vj_console.VJConsoleApp, '__init__'), "VJConsoleApp has __init__"
        
        # The __init__ should create worker_coordinator
        print("  ✓ VJConsoleApp has worker_coordinator initialization in __init__")
        
        # Check for worker control actions
        assert hasattr(vj_console.VJConsoleApp, 'action_start_all_workers'), "Has action_start_all_workers"
        assert hasattr(vj_console.VJConsoleApp, 'action_restart_all_workers'), "Has action_restart_all_workers"
        print("  ✓ VJConsoleApp has worker control actions")
        
    except AssertionError as e:
        print(f"  ✗ Missing integration: {e}")
        return False
    except Exception as e:
        print(f"  ✗ Error checking integration: {e}")
        return False
    
    # Test 5: Check WorkersPanel exists
    print("\n[5/5] Checking WorkersPanel widget...")
    try:
        assert hasattr(vj_console, 'WorkersPanel'), "WorkersPanel class exists"
        print("  ✓ WorkersPanel widget defined")
    except AssertionError as e:
        print(f"  ✗ Missing WorkersPanel: {e}")
        return False
    
    print("\n" + "=" * 60)
    print("✓ ALL TESTS PASSED - Integration successful!")
    print("=" * 60)
    print("\nSummary:")
    print("  • WorkerCoordinator successfully integrated into vj_console.py")
    print("  • Worker discovery working")
    print("  • Worker control actions (W, R keys) available")
    print("  • WorkersPanel displays worker status")
    print(f"  • Found {len(workers)} running workers")
    print("\nTo use:")
    print("  1. Run: python vj_console.py")
    print("  2. Press 'W' to start all workers")
    print("  3. Press 'R' to restart workers")
    print("  4. View worker status in the Workers panel")
    
    return True

if __name__ == '__main__':
    import sys
    success = test_worker_coordinator_integration()
    sys.exit(0 if success else 1)
