// Compiles a dart2wasm-generated main module from `source` which can then
// be instantiated via the `instantiate` method.
//
// `source` needs to be a `Response` object (or promise thereof) e.g. created
// via the `fetch()` JS API.
export async function compileStreaming(source) {
  const builtins = {builtins: ['js-string']};
  return new CompiledApp(
      await WebAssembly.compileStreaming(source, builtins), builtins);
}

// Compiles a dart2wasm-generated wasm module from `bytes` which is then
// instantiable via the `instantiate` method.
export async function compile(bytes) {
  const builtins = {builtins: ['js-string']};
  return new CompiledApp(await WebAssembly.compile(bytes, builtins), builtins);
}

class CompiledApp {
  constructor(module, builtins) {
    this.module = module;
    this.builtins = builtins;
  }

  // The second argument is an options object containing:
  // `loadDeferredModules` is a JS function that takes an array of module names
  //   matching wasm files produced by the dart2wasm compiler. It also takes a
  //   callback that should be invoked for each loaded module with 2 arguments:
  //   (1) the module name, (2) the loaded module in a format supported by
  //   `WebAssembly.compile` or `WebAssembly.compileStreaming`. The callback
  //   returns a Promise that resolves when the module is instantiated.
  //   loadDeferredModules should return a Promise that resolves when all the
  //   modules have been loaded and the callback promises have resolved.
  // `loadDeferredId` is a JS function that takes load ID produced by the
  //   compiler when the `use-load-ids` option is passed. Each load ID maps to
  //   one or more wasm files as specified in the emitted JSON file. It also
  //   takes a callback that should be invoked for each loaded module with 2
  //   arguments: (1) the module name, (2) the loaded module in a format
  //   supported by `WebAssembly.compile` or `WebAssembly.compileStreaming`.
  //   The callback returns a Promise that resolves when the module is
  //   instantiated.
  //   loadDeferredId should return a Promise that resolves when all the
  //   modules have been loaded and the callback promises have resolved.
  async instantiate(additionalImports, {loadDeferredModules, loadDeferredId} = {}) {
    let dartInstance;

    // Prints to the console
    function printToConsole(value) {
      if (typeof dartPrint == "function") {
        dartPrint(value);
        return;
      }
      if (typeof console == "object" && typeof console.log != "undefined") {
        console.log(value);
        return;
      }
      if (typeof print == "function") {
        print(value);
        return;
      }

      throw "Unable to print message: " + value;
    }

    // A special symbol attached to functions that wrap Dart functions.
    const jsWrappedDartFunctionSymbol = Symbol("JSWrappedDartFunction");

    function finalizeWrapper(dartFunction, wrapped) {
      wrapped.dartFunction = dartFunction;
      wrapped[jsWrappedDartFunctionSymbol] = true;
      return wrapped;
    }

    // Imports
    const dart2wasm = {
            AB: x0 => new Int16Array(x0),
      AC: (o, start, length) => new Uint8ClampedArray(o.buffer, o.byteOffset + start, length),
      AD: x0 => x0.screen,
      AE: x0 => new ResizeObserver(x0),
      AF: x0 => x0.key,
      AG: Function.prototype.call.bind(DataView.prototype.setBigInt64),
      AH: (x0,x1) => { x0.method = x1 },
      AI: x0 => x0.getReader(),
      AJ: (ms, c) =>
      setInterval(() => dartInstance.exports.$invokeCallback(c), ms),
      AK: x0 => x0.displayWidth,
      AL: (x0,x1) => { x0.width = x1 },
      B: s => printToConsole(s),
      BB: x0 => new Uint16Array(x0),
      BC: (o, start, length) => new Uint8Array(o.buffer, o.byteOffset + start, length),
      BD: o => {
        if (o === null || o === undefined) return 0;
        if (typeof(o) === 'string') return 1;
        return 2;
      },
      BE: (x0,x1) => x0.getPropertyValue(x1),
      BF: x0 => x0.identifier,
      BG: Function.prototype.call.bind(DataView.prototype.getBigInt64),
      BH: (x0,x1) => { x0.noValidate = x1 },
      BI: x0 => x0.read(),
      BJ: () => Date.now(),
      BK: x0 => x0.duration,
      BL: x0 => x0.height,
      C: Function.prototype.call.bind(Number.prototype.toString),
      CB: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmI16ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      CC: (o, start, length) => new Int8Array(o.buffer, o.byteOffset + start, length),
      CD: x0 => x0.tabIndex,
      CE: x0 => globalThis.parseFloat(x0),
      CF: x0 => x0.touches,
      CG: (o, start, length) => new BigInt64Array(o.buffer, o.byteOffset + start, length),
      CH: (x0,x1) => x0.removeAttribute(x1),
      CI: x0 => x0.value,
      CJ: (a, i) => a.splice(i, 1),
      CK: x0 => x0.image,
      CL: x0 => x0.width,
      D: Function.prototype.call.bind(BigInt.prototype.toString),
      DB: x0 => new Int32Array(x0),
      DC: (x0,x1) => x0.querySelector(x1),
      DD: (x0,x1) => x0.contains(x1),
      DE: (x0,x1) => x0.getComputedStyle(x1),
      DF: x0 => x0.pressure,
      DG: (x0,x1,x2,x3) => x0.pushState(x1,x2,x3),
      DH: x0 => x0.isConnected,
      DI: x0 => x0.done,
      DJ: a => a.pop(),
      DK: () => globalThis.window.ImageDecoder,
      DL: x0 => x0.rasterEndMilliseconds,
      E: (exn) => {
        let stackString = exn.toString();
        let frames = stackString.split('\n');
        let drop = 4;
        if (frames[0].startsWith('Error')) {
            drop += 1;
        }
        return frames.slice(drop).join('\n');
      },
      EB: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmI32ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      EC: (x0,x1) => x0.item(x1),
      ED: x0 => x0.activeElement,
      EE: x0 => x0.documentElement,
      EF: x0 => x0.tiltY,
      EG: x0 => x0.history,
      EH: x0 => x0.click(),
      EI: x0 => x0.cancel(),
      EJ: (x0,x1) => new Notification(x0,x1),
      EK: x0 => x0.status,
      EL: x0 => x0.rasterStartMilliseconds,
      F: () => new Error().stack,
      FB: x0 => new Uint32Array(x0),
      FC: x0 => x0.length,
      FD: x0 => x0.parentNode,
      FE: x0 => x0.computedStyleMap(),
      FF: x0 => x0.tiltX,
      FG: x0 => x0.search,
      FH: (x0,x1) => x0.getElementsByClassName(x1),
      FI: x0 => x0.body,
      FJ: (x0,x1) => x0.query(x1),
      FK: x0 => x0.response,
      FL: x0 => x0.imageBitmaps,
      G: s => JSON.stringify(s),
      GB: x0 => new Float32Array(x0),
      GC: (x0,x1) => x0.querySelectorAll(x1),
      GD: x0 => x0.tagName,
      GE: (x0,x1) => x0.get(x1),
      GF: x0 => x0.pointerType,
      GG: x0 => x0.location,
      GH: (x0,x1) => x0.dispatchEvent(x1),
      GI: x0 => x0.headers,
      GJ: () => globalThis.Notification.permission,
      GK: (x0,x1,x2) => x0.setRequestHeader(x1,x2),
      GL: x0 => x0.canvasKitMaximumSurfaces,
      H: Function.prototype.call.bind(Number.prototype.toString),
      HB: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmF32ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      HC: (x0,x1) => x0.getAttribute(x1),
      HD: x0 => x0.target,
      HE: (o, p) => p in o,
      HF: x0 => x0.pointerId,
      HG: x0 => x0.pathname,
      HH: (x0,x1) => x0.createEvent(x1),
      HI: x0 => x0.signal,
      HJ: () => globalThis.navigator.permissions,
      HK: (x0,x1) => { x0.responseType = x1 },
      HL: x0 => x0.nextSibling,
      I: Function.prototype.call.bind(String.prototype.indexOf),
      IB: x0 => new Float64Array(x0),
      IC: x0 => x0.remove(),
      ID: x0 => x0.clientY,
      IE: (x0,x1) => { x0.textContent = x1 },
      IF: x0 => x0.getCoalescedEvents(),
      IG: (x0,x1,x2,x3) => x0.replaceState(x1,x2,x3),
      IH: (x0,x1,x2,x3) => x0.initEvent(x1,x2,x3),
      II: () => {
        return typeof process != "undefined" &&
               Object.prototype.toString.call(process) == "[object process]" &&
               process.platform == "win32"
      },
      IJ: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      IK: () => new XMLHttpRequest(),
      IL: (x0,x1) => x0.debug(x1),
      J: (s, p, i) => s.lastIndexOf(p, i),
      JB: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmF64ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      JC: (x0,x1) => x0.appendChild(x1),
      JD: x0 => x0.clientX,
      JE: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      JF: (x0,x1) => x0.getModifierState(x1),
      JG: o => {
        const proto = Object.getPrototypeOf(o);
        return proto === Object.prototype || proto === null;
      },
      JH: x0 => x0.readText(),
      JI: () => {
        // On browsers return `globalThis.location.href`
        if (globalThis.location != null) {
          return globalThis.location.href;
        }
        return null;
      },
      JJ: (x0,x1) => { x0.onmessage = x1 },
      JK: x0 => x0.naturalHeight,
      JL: x0 => x0.hostElement,
      K: o => String(o),
      KB: x0 => new ArrayBuffer(x0),
      KC: (x0,x1) => x0.append(x1),
      KD: (x0,x1,x2) => x0.setAttribute(x1,x2),
      KE: x0 => x0.matches,
      KF: s => s.trimLeft(),
      KG: o => Object.keys(o),
      KH: x0 => x0.clipboard,
      KI: (x0,x1) => x0.key(x1),
      KJ: x0 => x0.terminate(),
      KK: x0 => x0.naturalWidth,
      KL: x0 => x0.location,
      L: (exn) => {
        if (exn instanceof Error) {
          return exn.stack;
        } else {
          return null;
        }
      },
      LB: (x0,x1,x2) => new Uint8Array(x0,x1,x2),
      LC: (x0,x1,x2,x3) => x0.setProperty(x1,x2,x3),
      LD: x0 => x0.getBoundingClientRect(),
      LE: (x0,x1) => x0.matchMedia(x1),
      LF: s => s.toUpperCase(),
      LG: x0 => x0.state,
      LH: (x0,x1) => x0.writeText(x1),
      LI: x0 => x0.length,
      LJ: x0 => x0.data,
      LK: (x0,x1) => x0.append(x1),
      LL: (x0,x1) => x0.getModifierState(x1),
      M: o => o === undefined,
      MB: (x0,x1,x2) => new DataView(x0,x1,x2),
      MC: x0 => x0.style,
      MD: (ms, c) =>
      setTimeout(() => dartInstance.exports.$invokeCallback(c),ms),
      ME: x0 => x0.matches,
      MF: (x0,x1) => x0[x1],
      MG: x0 => x0.hash,
      MH: x0 => x0.unlock(),
      MI: () => globalThis.localStorage,
      MJ: (x0,x1) => x0.postMessage(x1),
      MK: (x0,x1,x2) => x0.insertRule(x1,x2),
      ML: x0 => x0.metaKey,
      N: (c) =>
      queueMicrotask(() => dartInstance.exports.$invokeCallback(c)),
      NB: (o, p) => o[p],
      NC: x0 => x0.debugShowSemanticsNodes,
      ND: s => new Date(s * 1000).getTimezoneOffset() * 60,
      NE: o => typeof o === 'function' && o[jsWrappedDartFunctionSymbol] === true,
      NF: x0 => x0.index,
      NG: x0 => x0.state,
      NH: (x0,x1) => x0.lock(x1),
      NI: (x0,x1) => x0.removeItem(x1),
      NJ: x0 => new Worker(x0),
      NK: (x0,x1) => x0.add(x1),
      NL: x0 => x0.altKey,
      O: (x0,x1) => x0.didCreateEngineInitializer(x1),
      OB: (o) => new DataView(o.buffer, o.byteOffset, o.byteLength),
      OC: o => o,
      OD: Date.now,
      OE: f => f.dartFunction,
      OF: x0 => x0.pop(),
      OG: (x0,x1) => x0.go(x1),
      OH: x0 => x0.orientation,
      OI: (x0,x1,x2) => x0.setItem(x1,x2),
      OJ: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      OK: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      OL: x0 => x0.ctrlKey,
      P: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      PB: Function.prototype.call.bind(Object.getOwnPropertyDescriptor(DataView.prototype, 'byteLength').get),
      PC: o => {
        if (o === undefined || o === null) return 0;
        if (typeof o === 'boolean') return 1;
        return 2;
      },
      PD: (handle) => clearTimeout(handle),
      PE: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      PF: x0 => x0.flags,
      PG: x0 => x0.parentElement,
      PH: (x0,x1) => x0.querySelector(x1),
      PI: (x0,x1) => x0.getItem(x1),
      PJ: (x0,x1) => { x0.onmessage = x1 },
      PK: x0 => x0.preventDefault(),
      PL: x0 => x0.isComposing,
      Q: (wasmFunction,f) => finalizeWrapper(f, function() { return wasmFunction(f,arguments.length) }),
      QB: o => o.byteOffset,
      QC: (x0,x1) => x0.warn(x1),
      QD: (x0,x1) => x0.closest(x1),
      QE: (wasmFunction,f) => finalizeWrapper(f, function(x0,x1) { return wasmFunction(f,arguments.length,x0,x1) }),
      QF: (a, s) => a.join(s),
      QG: (x0,x1) => x0.querySelectorAll(x1),
      QH: (x0,x1) => { x0.title = x1 },
      QI: x0 => x0.persist(),
      QJ: (x0,x1) => x0.postMessage(x1),
      QK: x0 => x0.createRange(),
      QL: x0 => x0.code,
      R: (x0,x1) => ({initializeEngine: x0,autoStart: x1}),
      RB: o => o.buffer,
      RC: x0 => x0.console,
      RD: x0 => x0.bottom,
      RE: (p, s, f) => p.then(s, (e) => f(e, e === undefined)),
      RF: (x0,x1) => x0.error(x1),
      RG: (d, digits) => d.toFixed(digits),
      RH: (x0,x1) => x0.vibrate(x1),
      RI: () => globalThis.navigator.storage,
      RJ: x0 => x0.close(),
      RK: (x0,x1) => x0.selectNode(x1),
      RL: x0 => x0.repeat,
      S: (wasmFunction,f) => finalizeWrapper(f, function(x0,x1) { return wasmFunction(f,arguments.length,x0,x1) }),
      SB: Function.prototype.call.bind(DataView.prototype.getUint8),
      SC: () => globalThis.window,
      SD: x0 => x0.top,
      SE: (o, i) => o[i],
      SF: () => globalThis.console,
      SG: x0 => x0.maxHeight,
      SH: x0 => x0.arrayBuffer(),
      SI: (x0,x1) => globalThis.crypto.subtle.digest(x0,x1),
      SJ: x0 => x0.input,
      SK: x0 => x0.getSelection(),
      SL: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      T: x0 => new Promise(x0),
      TB: (b, o) => new DataView(b, o),
      TC: (o, c) => o instanceof c,
      TD: x0 => x0.right,
      TE: o => o.length,
      TF: s => s.trimRight(),
      TG: x0 => x0.maxWidth,
      TH: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof ArrayBuffer) return 1;
        if (globalThis.SharedArrayBuffer !== undefined &&
            o instanceof SharedArrayBuffer) {
          return 2;
        }
        return 3;
      },
      TI: (x0,x1,x2,x3) => globalThis.crypto.subtle.verify(x0,x1,x2,x3),
      TJ: x0 => x0.decode(),
      TK: x0 => x0.removeAllRanges(),
      TL: x0 => x0.userAgent,
      U: (x0,x1,x2) => x0.call(x1,x2),
      UB: (b, o, l) => new DataView(b, o, l),
      UC: (x0,x1) => x0.exec(x1),
      UD: x0 => x0.left,
      UE: o => {
        if (o === undefined) return 1;
        var type = typeof o;
        if (type === 'boolean') return 2;
        if (type === 'number') return 3;
        if (type === 'string') return 4;
        if (o instanceof Array) return 5;
        if (ArrayBuffer.isView(o)) {
          if (o instanceof Int8Array) return 6;
          if (o instanceof Uint8Array) return 7;
          if (o instanceof Uint8ClampedArray) return 8;
          if (o instanceof Int16Array) return 9;
          if (o instanceof Uint16Array) return 10;
          if (o instanceof Int32Array) return 11;
          if (o instanceof Uint32Array) return 12;
          if (o instanceof Float32Array) return 13;
          if (o instanceof Float64Array) return 14;
          if (o instanceof DataView) return 15;
        }
        if (o instanceof ArrayBuffer) return 16;
        // Feature check for `SharedArrayBuffer` before doing a type-check.
        if (globalThis.SharedArrayBuffer !== undefined &&
            o instanceof SharedArrayBuffer) {
            return 17;
        }
        if (o instanceof Promise) return 18;
        return 19;
      },
      UF: (x0,x1) => x0.requestAnimationFrame(x1),
      UG: x0 => x0.minHeight,
      UH: x0 => x0.status,
      UI: (x0,x1,x2,x3,x4) => globalThis.crypto.subtle.importKey(x0,x1,x2,x3,x4),
      UJ: (x0,x1) => { x0.src = x1 },
      UK: (x0,x1) => x0.addRange(x1),
      UL: x0 => x0.navigator,
      V: (constructor, args) => {
        const factoryFunction = constructor.bind.apply(
            constructor, [null, ...args]);
        return new factoryFunction();
      },
      VB: Function.prototype.call.bind(DataView.prototype.getFloat64),
      VC: x0 => x0.length,
      VD: x0 => x0.clientY,
      VE: x0 => x0.language,
      VF: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      VG: x0 => x0.minWidth,
      VH: (x0,x1) => x0.fetch(x1),
      VI: x0 => ({name: x0}),
      VJ: (x0,x1) => x0.createElement(x1),
      VK: () => globalThis.window,
      VL: (x0,x1,x2,x3) => x0.open(x1,x2,x3),
      W: x0 => new Array(x0),
      WB: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Float64Array) return 1;
        return 2;
      },
      WC: (x0,x1) => { x0.lastIndex = x1 },
      WD: x0 => x0.clientX,
      WE: (x0,x1,x2,x3) => x0.register(x1,x2,x3),
      WF: x0 => x0.now(),
      WG: (x0,x1) => x0.removeProperty(x1),
      WH: x0 => x0.content,
      WI: () => globalThis.window.isSecureContext,
      WJ: () => globalThis.document,
      WK: (x0,x1) => { x0.innerText = x1 },
      WL: () => globalThis.window,
      X: o => [o],
      XB: Function.prototype.call.bind(DataView.prototype.setFloat64),
      XC: (s, m) => {
        try {
          return new RegExp(s, m);
        } catch (e) {
          return String(e);
        }
      },
      XD: x0 => x0.changedTouches,
      XE: () => globalThis.window.FinalizationRegistry,
      XF: x0 => x0.performance,
      XG: (x0,x1) => x0.add(x1),
      XH: x0 => x0.document,
      XI: () => globalThis.crypto.subtle,
      XJ: (x0,x1,x2,x3) => x0.open(x1,x2,x3),
      XK: x0 => x0.offsetY,
      XL: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      Y: (o0, o1) => [o0, o1],
      YB: (t, s) => t.set(s),
      YC: o => o instanceof RegExp,
      YD: x0 => x0.offsetY,
      YE: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      YF: (o, offsetInBytes, lengthInBytes) => {
        var dst = new ArrayBuffer(lengthInBytes);
        new Uint8Array(dst).set(new Uint8Array(o, offsetInBytes, lengthInBytes));
        return new DataView(dst);
      },
      YG: x0 => x0.data,
      YH: x0 => x0.prompt(),
      YI: x0 => x0.debugSkipFontRetryDelay,
      YJ: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      YK: x0 => x0.offsetX,
      YL: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      Z: (o0, o1, o2) => [o0, o1, o2],
      ZB: Function.prototype.call.bind(DataView.prototype.setFloat32),
      ZC: (string, times) => string.repeat(times),
      ZD: x0 => x0.offsetX,
      ZE: x0 => new window.FinalizationRegistry(x0),
      ZF: (a, s, e) => a.slice(s, e),
      ZG: (x0,x1) => { x0.scrollTop = x1 },
      ZH: x0 => x0.outcome,
      ZI: x0 => new Uint8Array(x0),
      ZJ: (x0,x1,x2) => x0.addEventListener(x1,x2),
      ZK: x0 => x0.button,
      ZL: (x0,x1,x2) => x0.getCurrentPosition(x1,x2),
      a: (o0, o1, o2, o3) => [o0, o1, o2, o3],
      aB: Function.prototype.call.bind(DataView.prototype.getFloat32),
      aC: x0 => x0.dotAll,
      aD: x0 => x0.type,
      aE: (x0,x1) => x0.unregister(x1),
      aF: x0 => x0.blur(),
      aG: (x0,x1,x2) => x0.setSelectionRange(x1,x2),
      aH: (map, o) => map.get(o),
      aI: (x0,x1,x2) => x0.set(x1,x2),
      aJ: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      aK: x0 => x0.classList,
      aL: () => globalThis.Notification.requestPermission(),
      b: (x0,x1,x2) => { x0[x1] = x2 },
      bB: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Float32Array) return 1;
        return 2;
      },
      bC: x0 => x0.unicode,
      bD: x0 => x0.maxTouchPoints,
      bE: (x0,x1) => x0.contains(x1),
      bF: x0 => x0.button,
      bG: (x0,x1) => { x0.value = x1 },
      bH: x0 => new WeakRef(x0),
      bI: x0 => x0.buffer,
      bJ: x0 => x0.send(),
      bK: (x0,x1) => { x0.height = x1 },
      bL: x0 => ({video: x0}),
      c: o => o,
      cB: Function.prototype.call.bind(DataView.prototype.getUint32),
      cC: x0 => x0.ignoreCase,
      cD: x0 => x0.platform,
      cE: (s) => +s,
      cF: x0 => x0.innerHeight,
      cG: (x0,x1,x2) => x0.setSelectionRange(x1,x2),
      cH: x0 => x0.deref(),
      cI: x0 => x0.wasmMemory,
      cJ: (x0,x1) => x0.revokeObjectURL(x1),
      cK: (x0,x1) => { x0.width = x1 },
      cL: (x0,x1) => x0.getUserMedia(x1),
      d: (o, p) => o[p],
      dB: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Uint32Array) return 1;
        return 2;
      },
      dC: x0 => x0.multiline,
      dD: x0 => x0.body,
      dE: s => {
        if (!/^\s*[+-]?(?:Infinity|NaN|(?:\.\d+|\d+(?:\.\d*)?)(?:[eE][+-]?\d+)?)\s*$/.test(s)) {
          return NaN;
        }
        return parseFloat(s);
      },
      dF: x0 => x0.innerWidth,
      dG: (x0,x1) => { x0.value = x1 },
      dH: () => globalThis.WeakRef,
      dI: () => globalThis.window._flutter_skwasmInstance,
      dJ: (x0,x1) => { x0.src = x1 },
      dK: x0 => x0.style,
      dL: x0 => x0.getVideoTracks(),
      e: () => globalThis,
      eB: Function.prototype.call.bind(DataView.prototype.getInt32),
      eC: (string, token) => string.split(token),
      eD: () => globalThis.document,
      eE: s => s.trim(),
      eF: x0 => x0.height,
      eG: s => {
        if (/[[\]{}()*+?.\\^$|]/.test(s)) {
            s = s.replace(/[[\]{}()*+?.\\^$|]/g, '\\$&');
        }
        return s;
      },
      eH: x0 => x0.userAgent,
      eI: x0 => x0.fontFallbackBaseUrl,
      eJ: (x0,x1,x2,x3,x4) => globalThis.createImageBitmap(x0,x1,x2,x3,x4),
      eK: x0 => x0.sheet,
      eL: x0 => x0.stop(),
      f: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      fB: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Int32Array) return 1;
        return 2;
      },
      fC: o => o instanceof Array,
      fD: (x0,x1,x2) => x0.addEventListener(x1,x2),
      fE: x0 => x0.classList,
      fF: x0 => x0.width,
      fG: x0 => x0.value,
      fH: x0 => x0.navigator,
      fI: (x0,x1,x2) => x0.slice(x1,x2),
      fJ: x0 => x0.naturalHeight,
      fK: x0 => x0.head,
      fL: x0 => x0.active,
      g: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      gB: o => o instanceof Uint16Array,
      gC: (a, i) => a[i],
      gD: x0 => x0.hasFocus(),
      gE: x0 => x0.preventDefault(),
      gF: x0 => x0.clientHeight,
      gG: x0 => x0.selectionDirection,
      gH: () => globalThis.window,
      gI: (x0,x1) => x0.decode(x1),
      gJ: x0 => x0.naturalWidth,
      gK: (x0,x1) => { x0.pointerEvents = x1 },
      gL: x0 => ({audio: x0}),
      h: (x0,x1) => ({addView: x0,removeView: x1}),
      hB: Function.prototype.call.bind(DataView.prototype.getUint16),
      hC: a => a.length,
      hD: x0 => x0.relatedTarget,
      hE: x0 => x0.parent,
      hF: x0 => x0.clientWidth,
      hG: x0 => x0.selectionStart,
      hH: (x0,x1) => x0.matchMedia(x1),
      hI: (x0,x1) => x0.adoptText(x1),
      hJ: x0 => x0.decode(),
      hK: x0 => x0.src,
      hL: x0 => x0.getAudioTracks(),
      i: (l, r) => l === r,
      iB: o => o instanceof Int16Array,
      iC: (x0,x1) => x0.test(x1),
      iD: x0 => x0.shiftKey,
      iE: x0 => x0.timeStamp,
      iF: (x0,x1) => { x0.content = x1 },
      iG: x0 => x0.selectionEnd,
      iH: x0 => x0.standalone,
      iI: x0 => x0.first(),
      iJ: (x0,x1) => { x0.decoding = x1 },
      iK: (o, p) => p in o,
      iL: x0 => ({name: x0}),
      j: x0 => x0.random(),
      jB: Function.prototype.call.bind(DataView.prototype.getInt16),
      jC: x0 => x0.userAgent,
      jD: (decoder, codeUnits) => decoder.decode(codeUnits),
      jE: (x0,x1) => x0.hasAttribute(x1),
      jF: (x0,x1) => { x0.name = x1 },
      jG: x0 => x0.value,
      jH: x0 => x0.matches,
      jI: x0 => x0.next(),
      jJ: (x0,x1) => { x0.crossOrigin = x1 },
      jK: x0 => x0.groups,
      jL: (x0,x1) => x0.query(x1),
      k: o => o,
      kB: o => o instanceof Uint8ClampedArray,
      kC: x0 => x0.navigator,
      kD: () => new TextDecoder("utf-8", {fatal: true}),
      kE: x0 => x0.buttons,
      kF: x0 => x0.head,
      kG: x0 => x0.selectionDirection,
      kH: (x0,x1) => x0.matchMedia(x1),
      kI: x0 => x0.current(),
      kJ: (x0,x1) => x0.createObjectURL(x1),
      kK: () => globalThis.window.navigator.userAgent,
      kL: x0 => x0.state,
      l: o => {
        if (o === undefined || o === null) return 0;
        if (typeof o === 'number') return 1;
        return 2;
      },
      lB: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Uint8Array) return 1;
        return 2;
      },
      lC: Function.prototype.call.bind(String.prototype.toLowerCase),
      lD: () => new TextDecoder("utf-8", {fatal: false}),
      lE: x0 => x0.ctrlKey,
      lF: (x0,x1) => x0.removeChild(x1),
      lG: x0 => x0.selectionStart,
      lH: x0 => x0.matches,
      lI: (x0,x1) => new Intl.v8BreakIterator(x0,x1),
      lJ: x0 => x0.URL,
      lK: (x0,x1,x2) => x0.insertBefore(x1,x2),
      lL: x0 => x0.permissions,
      m: () => globalThis.Math,
      mB: Function.prototype.call.bind(DataView.prototype.setInt32),
      mC: Object.is,
      mD: (a, i, v) => a[i] = v,
      mE: x0 => x0.y,
      mF: x0 => x0.firstChild,
      mG: x0 => x0.selectionEnd,
      mH: () => globalThis.window,
      mI: x0 => x0.v8BreakIterator,
      mJ: x0 => new Blob(x0),
      mK: x0 => x0.id,
      mL: x0 => x0.geolocation,
      n: (x0,x1) => x0.prepend(x1),
      nB: Function.prototype.call.bind(DataView.prototype.setUint32),
      nC: x0 => x0.vendor,
      nD: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmI8ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      nE: x0 => x0.x,
      nF: x0 => x0.viewConstraints,
      nG: x0 => x0.keyCode,
      nH: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      nI: () => globalThis.Intl,
      nJ: (x0,x1,x2,x3,x4) => ({type: x0,data: x1,premultiplyAlpha: x2,colorSpaceConversion: x3,preferAnimation: x4}),
      nK: x0 => x0.offsetHeight,
      nL: x0 => x0.mediaDevices,
      o: (x0,x1,x2,x3) => x0.addEventListener(x1,x2,x3),
      oB: Function.prototype.call.bind(DataView.prototype.setInt16),
      oC: (x0,x1) => x0.createTextNode(x1),
      oD: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmI16ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      oE: x0 => x0.scrollTop,
      oF: x0 => x0.hostElement,
      oG: (x0,x1) => x0.scrollIntoView(x1),
      oH: (x0,x1,x2) => x0.addEventListener(x1,x2),
      oI: (x0,x1) => x0.segment(x1),
      oJ: x0 => new window.ImageDecoder(x0),
      oK: x0 => x0.offsetWidth,
      oL: x0 => x0.length,
      p: b => !!b,
      pB: Function.prototype.call.bind(DataView.prototype.setUint16),
      pC: (x0,x1) => { x0.id = x1 },
      pD: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmI32ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      pE: x0 => x0.offsetTop,
      pF: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      pG: x0 => x0.multiViewEnabled,
      pH: x0 => x0.preventDefault(),
      pI: x0 => x0.index,
      pJ: x0 => x0.name,
      pK: x0 => x0.stopPropagation(),
      pL: x0 => x0.getReader(),
      q: (wasmFunction,f) => finalizeWrapper(f, function(x0) { return wasmFunction(f,arguments.length,x0) }),
      qB: Function.prototype.call.bind(DataView.prototype.setUint8),
      qC: (x0,x1) => { x0.nonce = x1 },
      qD: x0 => x0.visibilityState,
      qE: x0 => x0.scrollLeft,
      qF: x0 => ({runApp: x0}),
      qG: (x0,x1) => x0.replaceWith(x1),
      qH: () => new AbortController(),
      qI: x0 => x0.next(),
      qJ: x0 => x0.repetitionCount,
      qK: x0 => x0.disabled,
      qL: x0 => x0.value,
      r: (x0,x1) => x0.focus(x1),
      rB: Function.prototype.call.bind(DataView.prototype.setInt8),
      rC: x0 => x0.nonce,
      rD: (x0,x1,x2) => x0.removeEventListener(x1,x2),
      rE: x0 => x0.offsetLeft,
      rF: (x0,x1) => x0.log(x1),
      rG: (x0,x1) => { x0.type = x1 },
      rH: (x0,x1,x2,x3,x4,x5) => ({method: x0,headers: x1,body: x2,credentials: x3,redirect: x4,signal: x5}),
      rI: x0 => x0.value,
      rJ: x0 => x0.frameCount,
      rK: (x0,x1) => { x0.min = x1 },
      rL: x0 => x0.done,
      s: () => ({}),
      sB: Function.prototype.call.bind(DataView.prototype.getInt8),
      sC: () => globalThis.window.flutterConfiguration,
      sD: x0 => x0.disconnect(),
      sE: x0 => x0.offsetParent,
      sF: () => globalThis.console,
      sG: (x0,x1) => { x0.className = x1 },
      sH: (x0,x1) => globalThis.fetch(x0,x1),
      sI: x0 => x0.done,
      sJ: x0 => x0.selectedTrack,
      sK: (x0,x1) => { x0.max = x1 },
      sL: x0 => x0.read(),
      t: (o, p, v) => o[p] = v,
      tB: o => {
        if (o === null || o === undefined) return 0;
        if (o instanceof Int8Array) return 1;
        return 2;
      },
      tC: (x0,x1) => x0.attachShadow(x1),
      tD: x0 => new Intl.Locale(x0),
      tE: (o, p, r) => o.replace(p, () => r),
      tF: () => typeof dartUseDateNowForTicks !== "undefined",
      tG: (x0,x1) => { x0.tabIndex = x1 },
      tH: (x0,x1) => x0.get(x1),
      tI: (o, m, a) => o[m].apply(o, a),
      tJ: x0 => x0.completed,
      tK: (x0,x1) => { x0.disabled = x1 },
      tL: x0 => x0.body,
      u: () => [],
      uB: (o, start, length) => new Float64Array(o.buffer, o.byteOffset + start, length),
      uC: (x0,x1) => x0.createElement(x1),
      uD: x0 => x0.region,
      uE: (o, p, r) => o.replaceAll(p, () => r),
      uF: () => Date.now(),
      uG: (x0,x1) => { x0.name = x1 },
      uH: (wasmFunction,f) => finalizeWrapper(f, function(x0,x1,x2) { return wasmFunction(f,arguments.length,x0,x1,x2) }),
      uI: x0 => x0.iterator,
      uJ: x0 => x0.ready,
      uK: (x0,x1) => { x0.scrollLeft = x1 },
      uL: (x0,x1) => new OffscreenCanvas(x0,x1),
      v: (a, i) => a.push(i),
      vB: (o, start, length) => new Float32Array(o.buffer, o.byteOffset + start, length),
      vC: x0 => x0.scale,
      vD: x0 => x0.script,
      vE: x0 => x0.deltaMode,
      vF: () => 1000 * performance.now(),
      vG: (x0,x1) => { x0.placeholder = x1 },
      vH: (x0,x1) => x0.forEach(x1),
      vI: () => globalThis.Symbol,
      vJ: x0 => x0.tracks,
      vK: (x0,x1) => { x0.spellcheck = x1 },
      vL: x0 => x0.assetBase,
      w: x0 => new Int8Array(x0),
      wB: (o, start, length) => new Uint32Array(o.buffer, o.byteOffset + start, length),
      wC: x0 => x0.visualViewport,
      wD: x0 => x0.language,
      wE: x0 => x0.deltaY,
      wF: (map, o, v) => map.set(o, v),
      wG: (x0,x1) => { x0.autocomplete = x1 },
      wH: x0 => x0.name,
      wI: (x0,x1) => new Intl.Segmenter(x0,x1),
      wJ: x0 => x0.close(),
      wK: (x0,x1) => { x0.disabled = x1 },
      wL: x0 => x0.loader,
      x: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const getValue = dartInstance.exports.$wasmI8ArrayGet;
        for (let i = 0; i < length; i++) {
          jsArray[jsArrayOffset + i] = getValue(wasmArray, wasmArrayOffset + i);
        }
      },
      xB: (o, start, length) => new Int32Array(o.buffer, o.byteOffset + start, length),
      xC: x0 => x0.devicePixelRatio,
      xD: x0 => x0.languages,
      xE: x0 => x0.deltaX,
      xF: () => new WeakMap(),
      xG: (x0,x1) => { x0.name = x1 },
      xH: x0 => x0.statusText,
      xI: x0 => x0.Segmenter,
      xJ: (x0,x1) => ({frameIndex: x0,completeFramesOnly: x1}),
      xK: (x0,x1) => x0.transferFromImageBitmap(x1),
      xL: () => globalThis._flutter,
      y: x0 => new Uint8Array(x0),
      yB: (o, start, length) => new Uint16Array(o.buffer, o.byteOffset + start, length),
      yC: x0 => x0.height,
      yD: (x0,x1) => x0.observe(x1),
      yE: x0 => x0.wheelDeltaY,
      yF: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmF32ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      yG: (x0,x1) => { x0.placeholder = x1 },
      yH: x0 => x0.url,
      yI: () => new TextDecoder(),
      yJ: (x0,x1) => x0.decode(x1),
      yK: (x0,x1) => x0.getContext(x1),
      z: x0 => new Uint8ClampedArray(x0),
      zB: (o, start, length) => new Int16Array(o.buffer, o.byteOffset + start, length),
      zC: x0 => x0.width,
      zD: (wasmFunction,f) => finalizeWrapper(f, function(x0,x1) { return wasmFunction(f,arguments.length,x0,x1) }),
      zE: x0 => x0.wheelDeltaX,
      zF: (jsArray, jsArrayOffset, wasmArray, wasmArrayOffset, length) => {
        const setValue = dartInstance.exports.$wasmF64ArraySet;
        for (let i = 0; i < length; i++) {
          setValue(wasmArray, wasmArrayOffset + i, jsArray[jsArrayOffset + i]);
        }
      },
      zG: (x0,x1) => { x0.action = x1 },
      zH: x0 => x0.status,
      zI: (handle) => clearInterval(handle),
      zJ: x0 => x0.displayHeight,
      zK: (x0,x1) => { x0.height = x1 },

    };

    const baseImports = {
      _: dart2wasm,
      Math: Math,
      Date: Date,
      Object: Object,
      Array: Array,
      Reflect: Reflect,
      WebAssembly: {
        JSTag: WebAssembly.JSTag,
      },
      "": new Proxy({}, { get(_, prop) { return prop; } }),

    };

    const jsStringPolyfill = {
      "charCodeAt": (s, i) => s.charCodeAt(i),
      "compare": (s1, s2) => {
        if (s1 < s2) return -1;
        if (s1 > s2) return 1;
        return 0;
      },
      "concat": (s1, s2) => s1 + s2,
      "equals": (s1, s2) => s1 === s2,
      "fromCharCode": (i) => String.fromCharCode(i),
      "length": (s) => s.length,
      "substring": (s, a, b) => s.substring(a, b),
      "fromCharCodeArray": (a, start, end) => {
        if (end <= start) return '';

        const read = dartInstance.exports.$wasmI16ArrayGet;
        let result = '';
        let index = start;
        const chunkLength = Math.min(end - index, 500);
        let array = new Array(chunkLength);
        while (index < end) {
          const newChunkLength = Math.min(end - index, 500);
          for (let i = 0; i < newChunkLength; i++) {
            array[i] = read(a, index++);
          }
          if (newChunkLength < chunkLength) {
            array = array.slice(0, newChunkLength);
          }
          result += String.fromCharCode(...array);
        }
        return result;
      },
      "intoCharCodeArray": (s, a, start) => {
        if (s === '') return 0;

        const write = dartInstance.exports.$wasmI16ArraySet;
        for (var i = 0; i < s.length; ++i) {
          write(a, start++, s.charCodeAt(i));
        }
        return s.length;
      },
      "test": (s) => typeof s == "string",
    };


    

    dartInstance = await WebAssembly.instantiate(this.module, {
      ...baseImports,
      ...additionalImports,
      
      "wasm:js-string": jsStringPolyfill,
    });

    return new InstantiatedApp(this, dartInstance);
  }
}

class InstantiatedApp {
  constructor(compiledApp, instantiatedModule) {
    this.compiledApp = compiledApp;
    this.instantiatedModule = instantiatedModule;
  }

  // Call the main function with the given arguments.
  invokeMain(...args) {
    this.instantiatedModule.exports.$invokeMain(args);
  }
}
