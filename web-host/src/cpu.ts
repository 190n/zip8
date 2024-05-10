import wasmUrl from '../../zig-out/lib/zip8.wasm?url';

interface Zip8Exports {
	memory: WebAssembly.Memory;
	ZIP8_ERR_ILLEGAL_OPCODE: WebAssembly.Global;
	ZIP8_ERR_STACK_OVERFLOW: WebAssembly.Global;
	ZIP8_ERR_BAD_RETURN: WebAssembly.Global;
	ZIP8_ERR_PROGRAM_TOO_LONG: WebAssembly.Global;
	ZIP8_ERR_FLAG_OVERFLOW: WebAssembly.Global;

	zip8GetErrorName(err: number): number;
	zip8CpuGetSize(): number;
	zip8CpuInit(
		errPtr: number,
		cpuPtr: number,
		programBuf: number,
		programLen: number,
		seed: bigint,
		flags: bigint
	): number;
	zip8CpuCycle(errPtr: number, cpuPtr: number): number;
	zip8CpuSetKeys(cpuPtr: number, keys: number): void;
	zip8CpuIsWaitingForKey(cpuPtr: number): boolean;
	zip8CpuTimerTick(cpuPtr: number): void;
	zip8CpuDisplayIsDirty(cpuPtr: number): boolean;
	zip8CpuSetDisplayNotDirty(cpuPtr: number): void;
	zip8CpuGetDisplay(cpuPtr: number): number;
	zip8CpuGetInstruction(cpuPtr: number): number;
	zip8CpuGetProgramCounter(cpuPtr: number): number;
	zip8CpuGetFlags(cpuPtr: number): bigint;
	zip8CpuFlagsAreDirty(cpuPtr: number): boolean;
	zip8CpuSetFlagsNotDirty(cpuPtr: number): void;
	zip8CpuAlloc(): number;
	zip8CpuGetDrawBytes(cpuPtr: number): number;
	zip8CpuResetDrawBytes(cpuPtr: number): void;
	wasmAlloc(size: number): number;
}

function decodeNullTerminatedString(memory: WebAssembly.Memory, start: number) {
	const view = new Uint8Array(memory.buffer);
	let length = 0;
	while (view[start + length] != 0) {
		length += 1;
	}
	return new TextDecoder('utf-8').decode(
		memory.buffer.slice(start, start + length)
	);
}

export default class CPU {
	static wasmModule: WebAssembly.Module | null = null;

	private exports: Zip8Exports = {} as any;
	private errPtr: number = 0;
	private cpuPtr: number = 0;
	private display: Uint8Array = new Uint8Array();

	private constructor() {}

	private logCallback(pointer: number, size: number) {
		const string = new TextDecoder('utf-8').decode(
			this.exports.memory.buffer.slice(pointer, pointer + size)
		);
		console.log(string);
	}

	private fallibleCall(result: number) {
		if (result != 0) {
			const err = new DataView(this.exports.memory.buffer).getUint16(
				this.errPtr,
				true
			);
			const stringPointer = this.exports.zip8GetErrorName(err);
			throw new Error(
				decodeNullTerminatedString(this.exports.memory, stringPointer)
			);
		}
	}

	static async init(
		program: ArrayBuffer,
		seed: bigint,
		initialFlags: number[]
	): Promise<CPU> {
		const cpu = new CPU();

		if (CPU.wasmModule == null) {
			CPU.wasmModule = await WebAssembly.compileStreaming(fetch(wasmUrl));
		}
		cpu.exports = (
			await WebAssembly.instantiate(CPU.wasmModule, {
				env: {
					zip8Log: cpu.logCallback.bind(cpu),
				},
			})
		).exports as unknown as Zip8Exports;
		cpu.errPtr = cpu.exports.wasmAlloc(2);
		cpu.cpuPtr = cpu.exports.zip8CpuAlloc();
		const programBuf = cpu.exports.wasmAlloc(program.byteLength);
		new Uint8Array(cpu.exports.memory.buffer).set(
			new Uint8Array(program),
			programBuf
		);

		let flagsNum = 0n;
		for (let i = 0; i < 8; i++) {
			flagsNum |= BigInt(initialFlags[i]) << BigInt(8 * i);
		}
		cpu.fallibleCall(
			cpu.exports.zip8CpuInit(
				cpu.errPtr,
				cpu.cpuPtr,
				programBuf,
				program.byteLength,
				seed,
				flagsNum
			)
		);

		const displayPtr = cpu.exports.zip8CpuGetDisplay(cpu.cpuPtr);
		cpu.display = new Uint8Array(
			cpu.exports.memory.buffer,
			displayPtr,
			(64 * 32) / 8
		);
		return cpu;
	}

	cycle() {
		this.fallibleCall(this.exports.zip8CpuCycle(this.errPtr, this.cpuPtr));
	}

	timerTick() {
		this.exports.zip8CpuTimerTick(this.cpuPtr);
	}

	getPixel(x: number, y: number): boolean {
		const index = 64 * y + x;
		const byteIndex = Math.floor(index / 8);
		const bitIndex = index % 8;
		return Boolean((this.display[byteIndex] >> bitIndex) & 1);
	}

	renderDisplay(out: ImageData) {
		for (let y = 0; y < 32; y += 1) {
			for (let x = 0; x < 64; x += 1) {
				let rgb;
				if (window.location.hash == '#pony') {
					rgb = this.getPixel(x, y) ? [0x5f, 0x52, 0x2b] : [0x91, 0x41, 0x2a];
				} else {
					rgb = this.getPixel(x, y) ? [0xff, 0xff, 0xff] : [0x00, 0x00, 0x00];
				}
				out.data[(y * 64 + x) * 4 + 0] = rgb[0];
				out.data[(y * 64 + x) * 4 + 1] = rgb[1];
				out.data[(y * 64 + x) * 4 + 2] = rgb[2];
				out.data[(y * 64 + x) * 4 + 3] = 255;
			}
		}
	}

	setKeys(keys: boolean[]) {
		let keysNum = 0;
		for (let i = 0; i < 16; i++) {
			if (keys[i]) {
				keysNum |= 1 << i;
			}
		}
		this.exports.zip8CpuSetKeys(this.cpuPtr, keysNum);
	}

	isWaitingForKey(): boolean {
		return this.exports.zip8CpuIsWaitingForKey(this.cpuPtr);
	}

	displayIsDirty(): boolean {
		return this.exports.zip8CpuDisplayIsDirty(this.cpuPtr);
	}

	setDisplayNotDirty() {
		this.exports.zip8CpuSetDisplayNotDirty(this.cpuPtr);
	}

	getInstruction(): number {
		return this.exports.zip8CpuGetInstruction(this.cpuPtr);
	}

	getProgramCounter(): number {
		return this.exports.zip8CpuGetProgramCounter(this.cpuPtr);
	}

	flagsAreDirty(): boolean {
		return this.exports.zip8CpuFlagsAreDirty(this.cpuPtr);
	}

	setFlagsNotDirty() {
		this.exports.zip8CpuSetFlagsNotDirty(this.cpuPtr);
	}

	getFlags(): number[] {
		const flags = Array(8).fill(0);
		const flagsNum = this.exports.zip8CpuGetFlags(this.cpuPtr);
		for (let i = 0; i < 8; i++) {
			flags[i] = Number(flagsNum >> BigInt(8 * i)) & 0xff;
		}
		return flags;
	}

	getDrawBytes(): number {
		return this.exports.zip8CpuGetDrawBytes(this.cpuPtr);
	}

	resetDrawBytes() {
		this.exports.zip8CpuResetDrawBytes(this.cpuPtr);
	}
}
