import CPU from './cpu.ts';

const canvas = document.getElementById('canvas')! as HTMLCanvasElement;
const ctx = canvas.getContext('2d')!;
const output = document.getElementById('output')!;

const imageData = ctx.createImageData(64, 32);

const keys = Array(16).fill(false);
let spaceHeld = false;

const keyBindings = {
	'1': 0x1,
	'2': 0x2,
	'3': 0x3,
	'4': 0xc,
	q: 0x4,
	w: 0x5,
	e: 0x6,
	r: 0xd,
	a: 0x7,
	s: 0x8,
	d: 0x9,
	f: 0xe,
	z: 0xa,
	x: 0x0,
	c: 0xb,
	v: 0xf,
};

window.onkeydown = (e) => {
	if (e.key in keyBindings) {
		keys[keyBindings[e.key as keyof typeof keyBindings]] = true;
	} else if (e.key == ' ') {
		e.preventDefault();
		spaceHeld = true;
	}
};

window.onkeyup = (e) => {
	if (e.key in keyBindings) {
		keys[keyBindings[e.key as keyof typeof keyBindings]] = false;
	} else if (e.key == ' ') {
		e.preventDefault();
		spaceHeld = false;
	}
};

window.ontouchstart = (e: TouchEvent) => {
	const tagName = (e.target as HTMLElement).tagName;
	if (tagName == 'A' || tagName == 'BUTTON' || tagName == 'INPUT') return true;
	e.preventDefault();
	keys.fill(true);
};

window.ontouchend = (e: TouchEvent) => {
	const tagName = (e.target as HTMLElement).tagName;
	if (tagName == 'A' || tagName == 'BUTTON' || tagName == 'INPUT') return true;
	e.preventDefault();
	keys.fill(false);
};

let timeout: number | null = null;

async function run(rom: ArrayBuffer) {
	if (timeout !== null) clearTimeout(timeout);

	const key = 'zip8Flags';
	const initialFlags =
		localStorage.getItem(key) === null
			? Array(8).fill(0)
			: JSON.parse(localStorage.getItem(key)!);

	output.innerHTML = '';

	const cpu = await CPU.init(
		rom,
		BigInt(Math.floor(Math.random() * 1000000)),
		initialFlags
	);

	const instructionsPerTick = 300;

	let halt = false;

	function tick() {
		if (halt) return;
		timeout = setTimeout(tick, 1000 / 60);
		if (spaceHeld) {
			cpu.setKeys(Array(16).fill(true));
		} else {
			cpu.setKeys(keys);
		}

		if (!cpu.isWaitingForKey()) {
			for (let i = 0; i < instructionsPerTick && !halt; i++) {
				try {
					cpu.cycle();
				} catch (e) {
					halt = true;
					output.innerHTML = `Error: ${(e as Error).message}<br>
						at 0x${cpu.getProgramCounter().toString(16).padStart(3, '0')},
						instruction 0x${cpu.getInstruction().toString(16).padStart(4, '0')}`;
				}
			}

			cpu.timerTick();
			if (cpu.displayIsDirty()) {
				cpu.renderDisplay(imageData);
				ctx.putImageData(imageData, 0, 0);
				cpu.setDisplayNotDirty();
			}

			if (cpu.flagsAreDirty()) {
				const flags = cpu.getFlags();
				localStorage.setItem(key, JSON.stringify(flags));
			}
		}
	}

	tick();
}

async function loadRom(this: HTMLElement) {
	const url = this.dataset.romUrl as string;
	run(await (await fetch(url)).arrayBuffer());
}

for (const e of document.getElementsByClassName('rom-loader')) {
	e.addEventListener('click', loadRom, false);
}

document.getElementById('upload')!.onchange = (e: Event) => {
	const file = (e.target as HTMLInputElement).files![0];
	const reader = new FileReader();
	reader.onload = () => {
		run(reader.result as ArrayBuffer);
	};
	reader.readAsArrayBuffer(file);
};

(async () => {
	run(await (await fetch('flappybird.ch8')).arrayBuffer());
})();
