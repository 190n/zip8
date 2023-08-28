function zip8FallibleCall(exports, errPtr, result) {
	if (result != 0) {
		const err = new DataView(exports.memory.buffer).getUint16(errPtr, true);
		const stringPointer = exports.zip8GetErrorName(err);
		throw new Error(decodeNullTerminatedString(exports.memory, stringPointer));
	}
}

function decodeNullTerminatedString(memory, start) {
	const view = new Uint8Array(memory.buffer);
	let length = 0;
	while (view[start + length] != 0) {
		length += 1;
	}
	return new TextDecoder('utf-8').decode(memory.buffer.slice(start, start + length));
}

export default class CPU {
	static wasmModule = null;

	constructor(program, seed) {
		this.program = program;
		this.seed = seed;
	}

	call(name, ...args) {
		zip8FallibleCall(this.instance.exports, this.errPtr, this.instance.exports[name](this.errPtr, ...args));
	}

	async init() {
		if (CPU.wasmModule == null) {
			CPU.wasmModule = await WebAssembly.compileStreaming(fetch('../zig-out/lib/zip8.wasm'));
		}
		this.instance = await WebAssembly.instantiate(CPU.wasmModule, {
			env: {
				zip8Log: (pointer, size) => {
					const string = new TextDecoder('utf-8').decode(this.instance.exports.memory.buffer.slice(pointer, pointer + size));
					console.log(string);
				},
			},
		});
		this.errPtr = this.instance.exports.wasmAlloc(2);
		this.cpu = this.instance.exports.zip8CpuAlloc();
		const programBuf = this.instance.exports.wasmAlloc(this.program.byteLength);
		new Uint8Array(this.instance.exports.memory.buffer).set(new Uint8Array(this.program), programBuf);

		this.call('zip8CpuInit', this.cpu, programBuf, this.program.byteLength, BigInt(this.seed));
	}

	cycle() {
		this.call('zip8CpuCycle', this.cpu);
	}

	timerTick() {
		this.instance.exports.zip8CpuTimerTick(this.cpu);
	}

	getDisplay() {
		const displayPtr = this.instance.exports.zip8CpuGetDisplay(this.cpu);
		return new Uint8Array(this.instance.exports.memory.buffer.slice(displayPtr, displayPtr + 2048));
	}

	setKeys(keys) {
		let keysNum = 0;
		for (let i = 0; i < 16; i++) {
			if (keys[i]) {
				keysNum |= (1 << i);
			}
		}
		this.instance.exports.zip8CpuSetKeys(this.cpu, keysNum);
	}

	isWaitingForKey() {
		return this.instance.exports.zip8CpuIsWaitingForKey(this.cpu);
	}

	displayIsDirty() {
		return this.instance.exports.zip8CpuDisplayIsDirty(this.cpu);
	}

	setDisplayNotDirty() {
		this.instance.exports.zip8CpuSetDisplayNotDirty(this.cpu);
	}

	getInstruction() {
		return this.instance.exports.zip8CpuGetInstruction(this.cpu);
	}

	getProgramCounter() {
		return this.instance.exports.zip8CpuGetProgramCounter(this.cpu);
	}
}
