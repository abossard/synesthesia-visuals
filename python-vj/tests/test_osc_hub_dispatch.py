import pytest

try:
    import pyliblo3 as liblo
except ImportError:
    liblo = None

if liblo is None:
    pytest.skip("pyliblo3 not installed", allow_module_level=True)

from osc.hub import (
    OSCHub,
    _classify_pattern,
    _MATCH_ANY,
    _MATCH_EXACT,
    _MATCH_PREFIX,
)


def _build_hub(listeners):
    hub = OSCHub()
    with hub._listeners_lock:
        hub._listeners = listeners
        hub._refresh_listeners_snapshot()
    return hub


@pytest.mark.parametrize(
    "pattern,expected_type,expected_value",
    [
        (None, _MATCH_ANY, None),
        ("", _MATCH_ANY, None),
        ("/", _MATCH_ANY, None),
        ("*", _MATCH_ANY, None),
        ("/foo", _MATCH_EXACT, "/foo"),
        ("foo", _MATCH_EXACT, "foo"),
        ("/foo/*", _MATCH_PREFIX, "/foo/"),
        ("/foo*", _MATCH_PREFIX, "/foo"),
        ("/*", _MATCH_PREFIX, "/"),
    ],
)
def test_classify_pattern(pattern, expected_type, expected_value):
    match_type, match_value = _classify_pattern(pattern)
    assert match_type == expected_type
    assert match_value == expected_value


def test_dispatch_matches_any_exact_and_prefix():
    calls = []

    def handler(tag):
        def _handler(path, args):
            calls.append(tag)
        return _handler

    listeners = {
        "/foo/*": [handler("foo")],
        "/foo/bar/*": [handler("foobar")],
        "/foo/bar/baz": [handler("exact")],
        "/*": [handler("root_prefix")],
        "*": [handler("any")],
        "/baz/*": [handler("baz")],
    }

    hub = _build_hub(listeners)
    hub._dispatch("/foo/bar/baz", [1])

    expected = {"foo", "foobar", "exact", "root_prefix", "any"}
    assert set(calls) == expected
    assert len(calls) == len(expected)


@pytest.mark.parametrize(
    "args,expect_same_object",
    [
        (["a", 1], True),
        (("a", 1), False),
    ],
)
def test_dispatch_reuses_args_list(args, expect_same_object):
    seen_ids = []
    seen_args = []

    def handler_one(path, msg_args):
        seen_ids.append(id(msg_args))
        seen_args.append(msg_args)

    def handler_two(path, msg_args):
        seen_ids.append(id(msg_args))
        seen_args.append(msg_args)

    hub = _build_hub({"/foo": [handler_one, handler_two]})
    hub._dispatch("/foo", args)

    assert len(seen_ids) == 2
    assert len(set(seen_ids)) == 1
    assert isinstance(seen_args[0], list)
    if expect_same_object:
        assert seen_args[0] is args
    else:
        assert seen_args[0] is not args
