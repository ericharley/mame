'use strict';

const $ = id => document.getElementById(id);
const status = text => {
  $('status').textContent = text;
};

let socket = null;
let chunks = [];
let offset = 0;
let queued = 0;
let outgoing = [];
let started = false;
let inputPaused = false;

$('endpoint').value =
  `${location.protocol === 'https:' ? 'wss:' : 'ws:'}//${location.host}/serial`;

function disconnect(message) {
  if (socket) {
    socket.close();
  }
  socket = null;
  chunks = [];
  offset = 0;
  queued = 0;
  outgoing = [];
  inputPaused = false;
  if (message) {
    status(message);
  }
}

$('disconnect').onclick = () => disconnect('Serial disconnected');
$('connect').onclick = () => {
  disconnect();
  try {
    const connection = new WebSocket($('endpoint').value, 'binary');
    socket = connection;
    connection.binaryType = 'arraybuffer';
    connection.onopen = () => status('Serial connected');
    connection.onmessage = event => {
      if (socket !== connection || !(event.data instanceof ArrayBuffer)) {
        return;
      }
      const bytes = new Uint8Array(event.data);
      if (queued + bytes.length > 4 * 1024 * 1024) {
        disconnect('Serial receive queue exceeded; disconnected');
        return;
      }
      chunks.push(bytes);
      queued += bytes.length;
    };
    connection.onerror = () => status('Serial connection failed');
    connection.onclose = () => {
      if (socket === connection) {
        disconnect('Serial disconnected');
      }
    };
  } catch (error) {
    status(error.message);
  }
};

setInterval(() => {
  if (socket?.readyState === WebSocket.OPEN && outgoing.length) {
    socket.send(new Uint8Array(outgoing));
    outgoing = [];
  }
}, 10);

// Emscripten consumes this global when vt340web.js loads.
var Module = {
  noInitialRun: true,
  canvas: $('canvas'),
  print: text => {
    $('log').textContent = ($('log').textContent + text + '\n').slice(-8000);
  },
  printErr: text => Module.print(text),
  setStatus: text => {
    if (text) {
      status(text);
    }
  },
  serialOutput: byte => {
    if (byte === 0x13) {
      inputPaused = true;
    } else if (byte === 0x11) {
      inputPaused = false;
    }
    if (socket?.readyState === WebSocket.OPEN && outgoing.length < 65536) {
      outgoing.push(byte);
    }
  },
  serialInput: (pointer, length) => {
    if (inputPaused) {
      return 0;
    }
    let copied = 0;
    while (copied < length && chunks.length) {
      const chunk = chunks[0];
      const count = Math.min(length - copied, chunk.length - offset);
      HEAPU8.set(chunk.subarray(offset, offset + count), pointer + copied);
      copied += count;
      offset += count;
      queued -= count;
      if (offset === chunk.length) {
        chunks.shift();
        offset = 0;
      }
    }
    return copied;
  },
  preRun: [() => {
    addRunDependency('vt340-assets');
    (async () => {
      const directories = [
        '/roms',
        '/roms/vt340',
        '/persist',
        '/persist/nvram',
        '/persist/cfg',
      ];
      for (const directory of directories) {
        FS.mkdirTree(directory);
      }
      FS.mount(IDBFS, {}, '/persist');
      await new Promise((resolve, reject) => {
        FS.syncfs(true, error => error ? reject(error) : resolve());
      });

      const manifestResponse = await fetch('assets/manifest.json');
      if (!manifestResponse.ok) {
        throw new Error('Missing assets/manifest.json');
      }
      const manifest = await manifestResponse.json();
      for (const entry of manifest) {
        if (entry.seed && FS.analyzePath(entry.path).exists) {
          continue;
        }
        const response = await fetch(`assets/${entry.file}`);
        if (!response.ok) {
          throw new Error(`Missing ${entry.file}`);
        }
        FS.mkdirTree(entry.path.slice(0, entry.path.lastIndexOf('/')));
        FS.writeFile(entry.path, new Uint8Array(await response.arrayBuffer()));
      }
      FS.writeFile('/browser-serial', new Uint8Array());
      removeRunDependency('vt340-assets');
    })().catch(error => status(`Startup failed: ${error.message}`));
  }],
  onRuntimeInitialized: () => {
    $('start').disabled = false;
    status('Ready');
  },
  onEmulatorStopped: () => {
    saveSettings().catch(() => {});
  },
};

async function saveSettings() {
  // MAME flushes its in-memory EEPROM on exit; syncing alone cannot flush it.
  return new Promise((resolve, reject) => {
    FS.syncfs(false, error => {
      if (error) {
        status(`Saving failed: ${error.message}`);
        reject(error);
      } else {
        status('Settings saved in this browser');
        resolve();
      }
    });
  });
}

$('start').onclick = () => {
  if (started) {
    return;
  }
  started = true;
  $('start').disabled = true;
  $('save').disabled = false;
  const args = [
    'vt340',
    '-rompath', '/roms',
    '-nvram_directory', '/persist/nvram',
    '-cfg_directory', '/persist/cfg',
    '-comm1', 'null_modem',
    '-bitb', '/browser-serial',
    '-video', 'soft',
    '-window',
    '-cheat',
    '-ui_active',
    '-skip_gameinfo',
    '-scalemode', $('smooth').checked ? 'hwblit' : 'none',
    '-prescale', $('scale').value,
    $('smooth').checked ? '-filter' : '-nofilter',
  ];
  status('Terminal running — connect when startup completes');
  Module.callMain(args);
  $('canvas').focus({preventScroll: true});
};

$('smooth').onchange = () => {
  $('canvas').style.imageRendering = $('smooth').checked ? 'auto' : 'pixelated';
};

$('save').onclick = () => {
  status('Stopping terminal to save NVRAM…');
  $('save').disabled = true;
  Module.cwrap('_ZN15running_machine15emscripten_exitEv', null, [])();
};

fetch('session')
  .then(response => response.ok ? response.json() : null)
  .then(session => {
    if (session) {
      const protocol = location.protocol === 'https:' ? 'wss:' : 'ws:';
      $('endpoint').value = `${protocol}//${location.host}${session.endpoint}`;
    }
  })
  .catch(() => {});
