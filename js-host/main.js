import CPU from './cpu.js';

const canvas = document.getElementById('canvas');
const ctx = canvas.getContext('2d');

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

(async () => {
	const program = await (await fetch('flappybird.ch8')).arrayBuffer();
	const cpu = new CPU(program, Math.floor(Math.random() * 1000000));
	await cpu.init();

	const instructionsPerTick = 200;

	setTimeout(function tick() {
		setTimeout(tick, 1000 / 60);
		cpu.setKeys(keys);
		
		// if (!cpu.isWaitingForKey()) {
			for (let i = 0; i < instructionsPerTick; i++) {
				cpu.cycle();
			}
			
			cpu.timerTick();
			if (cpu.displayIsDirty()) {
				const display = cpu.getDisplay();
				drawScreen(display);
				cpu.setDisplayNotDirty();
			}
		// }
	}, 1000 / 60);

})();
