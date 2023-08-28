import CPU from './cpu.js';

const canvas = document.getElementById('canvas');
const ctx = canvas.getContext('2d');
const output = document.getElementById('output');

const imageData = ctx.createImageData(64, 32);

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

const keys = Array(16).fill(false);

const keyBindings = {
	'1': 0x1,
	'2': 0x2,
	'3': 0x3,
	'4': 0xc,
	'q': 0x4,
	'w': 0x5,
	'e': 0x6,
	'r': 0xd,
	'a': 0x7,
	's': 0x8,
	'd': 0x9,
	'f': 0xe,
	'z': 0xa,
	'x': 0x0,
	'c': 0xb,
	'v': 0xf,
};

window.onkeydown = e => {
	if (e.key in keyBindings) {
		keys[keyBindings[e.key]] = true;
	}
};

window.onkeyup = e => {
	if (e.key in keyBindings) {
		keys[keyBindings[e.key]] = false;
	}
};

window.ontouchstart = e => {
	if (e.target.tagName == 'A') return true;
	e.preventDefault();
	keys.fill(true);
};

window.ontouchend = e => {
	if (e.target.tagName == 'A') return true;
	e.preventDefault();
	keys.fill(false);
}

let timeout = null;

async function run(rom) {
	if (timeout !== null) clearTimeout(timeout);

	const key = 'zip8Flags';
	const initialFlags = localStorage.getItem(key) === null ? Array(8).fill(0) : JSON.parse(localStorage.getItem(key));

	output.innerHTML = '';

	const cpu = new CPU(rom, Math.floor(Math.random() * 1000000), initialFlags);
	await cpu.init();

	const instructionsPerTick = 200;

	let halt = false;

	function tick() {
		if (halt) return;
		timeout = setTimeout(tick, 1000 / 60);
		cpu.setKeys(keys);
		
		if (!cpu.isWaitingForKey()) {
			for (let i = 0; i < instructionsPerTick && !halt; i++) {
				try {
					cpu.cycle();
				} catch (e) {
					halt = true;
					output.innerHTML = `Error: ${e.message}<br>
						at 0x${cpu.getProgramCounter().toString(16).padStart(3, '0')},
						instruction 0x${cpu.getInstruction().toString(16).padStart(4, '0')}`;
				}
			}
			
			cpu.timerTick();
			if (cpu.displayIsDirty()) {
				const display = cpu.getDisplay();
				drawScreen(display);
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

async function loadRom() {
	const url = this.dataset.romUrl;
	run(await (await fetch(url)).arrayBuffer());
}

for (const e of document.getElementsByClassName('rom-loader')) {
	e.onclick = loadRom;
}

document.getElementById('upload').onchange = e => {
	const file = e.target.files[0];
	const reader = new FileReader();
	reader.onload = () => {
		run(reader.result);
	};
	reader.readAsArrayBuffer(file);
}

(async () => {
	run(await (await fetch('flappybird.ch8')).arrayBuffer());
})();
