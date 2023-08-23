const canvas = document.getElementById('canvas');
const ctx = canvas.getContext('2d');

const imageData = ctx.createImageData(64, 32);

function decodeNullTerminatedString(memory, start) {
	const view = new Uint8Array(memory.buffer);
	let length = 0;
	while (view[start + length] != 0) {
		length += 1;
	}
	return new TextDecoder('utf-8').decode(memory.buffer.slice(start, start + length));
}

function zip8FallibleCall(exports, errPtr, result) {
	if (result != 0) {
		const err = new DataView(exports.memory.buffer).getUint16(errPtr, true);
		const stringPointer = exports.zip8GetErrorName(err);
		throw new Error(decodeNullTerminatedString(exports.memory, stringPointer));
	}
}

function drawScreen(display) {
	for (let y = 0; y < 32; y += 1) {
		for (let x = 0; x < 64; x += 1) {
			const pixel = display[y * 64 + x] * 255;
			imageData.data[(y * 64 + x) * 4 + 0] = pixel;
			imageData.data[(y * 64 + x) * 4 + 1] = pixel;
			imageData.data[(y * 64 + x) * 4 + 2] = pixel;
			imageData.data[(y * 64 + x) * 4 + 3] = 255;
		}
	}

	ctx.putImageData(imageData, 0, 0);

}

WebAssembly.compileStreaming(fetch('../zig-out/lib/zip8.wasm')).then(async mod => {
	const { exports } = await WebAssembly.instantiate(mod, {
		env: {
			zip8Log(pointer, size) {
				const string = new TextDecoder('utf-8').decode(exports.memory.buffer.slice(pointer, pointer + size));
				console.log(string);
			}
		}
	});
	
	const cpu = exports.zip8CpuAlloc();
	const errPtr = exports.wasmAlloc(2);

	const program = await (await fetch('zig2.ch8')).arrayBuffer();
	const programBuf = exports.wasmAlloc(program.byteLength);
	new Uint8Array(exports.memory.buffer).set(new Uint8Array(program), programBuf);

	zip8FallibleCall(exports, errPtr, exports.zip8CpuInit(errPtr, cpu, programBuf, program.byteLength, BigInt(Math.floor(Math.random() * 1000))));

	const displayPtr = exports.zip8CpuGetDisplay(cpu);
	
	const instructionsPerTick = 200;
	
	requestAnimationFrame(function tick() {
		requestAnimationFrame(tick);
		
		for (let i = 0; i < instructionsPerTick; i++) {
			zip8FallibleCall(exports, errPtr, exports.zip8CpuCycle(errPtr, cpu));
		}
		
		exports.zip8CpuTimerTick(cpu);
		const display = new Uint8Array(exports.memory.buffer.slice(displayPtr, displayPtr + 64 * 32));
		drawScreen(display);
	});
});
