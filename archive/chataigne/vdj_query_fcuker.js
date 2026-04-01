

// VirtualDJ Bundle Handler - UDP to OSC Loopback
// Forwards valid OSC to local OSC module, handles broken bundles

// Configurable parameters
var oscLoopbackPortParam = script.addIntParameter("VDJ_OSC Loopback Port", "VDJ_OSC module local receive port", 9001, 1, 65535);
var logForwardParam = script.addBoolParameter("Log Forwarding", "Toggle forwarding logs", true);

// Lifecycle
function init() {
	script.log("VDJ Bundle Handler initialized");
	logForward("Forwarding valid OSC to localhost:" + oscLoopbackPortParam.get());
}

// Entry point for streaming modules (UDP/Serial). data is bytes; ipAddress/port provided by UDP module.
function dataReceived(data, ipAddress, port) {
	if (!data || data.length == 0) {
		script.log("ERROR: dataReceived got empty/null data");
		return;
	}
	logForward("dataReceived len=" + data.length + (ipAddress ? " from " + ipAddress + (port ? ":" + port : "") : ""));
	logBytes("data", data);

	if (isBundle(data)) {
		logForward("Detected OSC Bundle");
		handleBundle(data);
	} else {
		logForward("Detected OSC Message");
		forwardToOSC(data);
	}
}

// ------------------------ Calculations ------------------------
function isBundle(data) {
	return data.length >= 8 && data[0] == 0x23 && data[1] == 0x62 &&
	       data[2] == 0x75 && data[3] == 0x6E && data[4] == 0x64 &&
	       data[5] == 0x6C && data[6] == 0x65 && data[7] == 0x00; // "#bundle\0"
}

// ------------------------ Actions ------------------------
function handleBundle(data) {
	// skip #bundle(8) + timetag(8)
	var pos = 16;
	logForward("Parsing bundle contents... len=" + data.length);
	logBytes("bundle", data);
	while (pos + 4 <= data.length) {
		var size = readInt32BE(data, pos);
		pos += 4;
		logForward("Bundle elem size=" + size + " at pos=" + (pos - 4));
		if (size <= 0 || pos + size > data.length) {
			script.log("ERROR: Bundle element invalid size=" + size + " pos=" + pos + " dataLen=" + data.length);
			break;
		}

		var address = extractAddress(data, pos, size);
		if (!address) {
			script.log("ERROR: Failed to extract address at pos=" + pos);
		} else {
			logForward("Extracted address=" + address);
			sendQuery(address);
		}

		pos += size;
	}
}

function extractAddress(data, start, length) {
	if (data[start] != 0x2F) {
		script.log("ERROR: extractAddress byte at start=" + start + " is not '/' (0x2F), got " + data[start]);
		return null;
	}
	var address = "";
	for (var i = 0; i < length && (start + i) < data.length; i++) {
		var c = data[start + i];
		if (c == 0) break;
		address += String.fromCharCode(c);
	}
	if (address.length == 0) {
		script.log("ERROR: extractAddress got empty string");
		return null;
	}
	return address;
}

function sendQuery(address) {
	var message = buildOscMessageNoArgs(address);
	local.send(message);
	logForward("sendQuery address=" + address + " bytes=" + message.length);
	logBytes("query", message);
}

function forwardToOSC(data) {
	local.send(data);
	logForward("forwardToOSC bytes=" + data.length);
	logBytes("forward", data);
}

// ------------------------ Helpers ------------------------
function readInt32BE(buf, offset) {
	return ((buf[offset] & 0xFF) << 24) | ((buf[offset + 1] & 0xFF) << 16) |
	       ((buf[offset + 2] & 0xFF) << 8) | (buf[offset + 3] & 0xFF);
}

function buildOscMessageNoArgs(address) {
	var addressBytes = stringToOSCBytes(address);
	// append type tag ",\0\0\0" (no args)
	addressBytes[addressBytes.length] = 0x2C;
	addressBytes[addressBytes.length] = 0x00;
	addressBytes[addressBytes.length] = 0x00;
	addressBytes[addressBytes.length] = 0x00;
	return addressBytes;
}

function stringToOSCBytes(str) {
	var bytes = [];
	for (var i = 0; i < str.length; i++) {
		bytes[bytes.length] = str.charCodeAt(i);
	}
	bytes[bytes.length] = 0;
	while (bytes.length % 4 != 0) {
		bytes[bytes.length] = 0;
	}
	return bytes;
}

function logForward(msg) {
	if (logForwardParam.get()) script.log(msg);
}

function logBytes(label, bytes) {
	if (!logForwardParam.get()) return;
	if (!bytes) return;
	logForward(label + " len=" + bytes.length);
}
