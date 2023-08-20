function decodeNullTerminatedString(memory, start) {
	const view = new Uint8Array(memory.buffer);
	let length = 0;
	while (view[start + length] != 0) {
		length += 1;
	}
	return new TextDecoder('utf-8').decode(memory.buffer.slice(start, start + length));
}

function chip8FallibleCall(exports, errPtr, result) {
	if (result != 0) {
		const err = new DataView(exports.memory.buffer).getUint16(errPtr, true);
		const stringPointer = exports.chip8GetErrorName(err);
		throw new Error(decodeNullTerminatedString(exports.memory, stringPointer));
	}
}

WebAssembly.compileStreaming(fetch('/zig-out/lib/zip8.wasm')).then(async mod => {
	const { exports } = await WebAssembly.instantiate(mod, {});
	
	const cpu = exports.chip8CpuAlloc();
	const errPtr = exports.wasmAlloc(2);

	const program = [
		0xA2, 0x04,
		0xD0, 0x01,
		0x99,
	];
	const programBuf = exports.wasmAlloc(program.length);
	new Uint8Array(exports.memory.buffer).set(program, programBuf);

	chip8FallibleCall(exports, errPtr, exports.chip8CpuInit(errPtr, cpu, programBuf, program.length, BigInt(0)));

	// execute 2 instructions
	for (let i = 0; i < 2; i++) {
		chip8FallibleCall(exports, errPtr, exports.chip8CpuCycle(errPtr, cpu));
	}

	const displayPtr = exports.chip8CpuGetDisplay(cpu);
	const display = new Uint8Array(exports.memory.buffer.slice(displayPtr, displayPtr + 64 * 32));
	console.log(display);
});
