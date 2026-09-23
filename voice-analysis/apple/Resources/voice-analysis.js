var PoiseVoice = (() => {
  var __create = Object.create;
  var __defProp = Object.defineProperty;
  var __getOwnPropDesc = Object.getOwnPropertyDescriptor;
  var __getOwnPropNames = Object.getOwnPropertyNames;
  var __getProtoOf = Object.getPrototypeOf;
  var __hasOwnProp = Object.prototype.hasOwnProperty;
  var __commonJS = (cb, mod) => function __require() {
    try {
      return mod || (0, cb[__getOwnPropNames(cb)[0]])((mod = { exports: {} }).exports, mod), mod.exports;
    } catch (e) {
      throw mod = 0, e;
    }
  };
  var __export = (target, all) => {
    for (var name in all)
      __defProp(target, name, { get: all[name], enumerable: true });
  };
  var __copyProps = (to, from, except, desc) => {
    if (from && typeof from === "object" || typeof from === "function") {
      for (let key of __getOwnPropNames(from))
        if (!__hasOwnProp.call(to, key) && key !== except)
          __defProp(to, key, { get: () => from[key], enumerable: !(desc = __getOwnPropDesc(from, key)) || desc.enumerable });
    }
    return to;
  };
  var __toESM = (mod, isNodeMode, target) => (target = mod != null ? __create(__getProtoOf(mod)) : {}, __copyProps(
    // If the importer is in node compatibility mode or this is not an ESM
    // file that has been converted to a CommonJS file using a Babel-
    // compatible transform (i.e. "__esModule" has not been set), then set
    // "default" to the CommonJS "module.exports" for node compatibility.
    isNodeMode || !mod || !mod.__esModule ? __defProp(target, "default", { value: mod, enumerable: true }) : target,
    mod
  ));
  var __toCommonJS = (mod) => __copyProps(__defProp({}, "__esModule", { value: true }), mod);

  // node_modules/fft.js/lib/fft.js
  var require_fft = __commonJS({
    "node_modules/fft.js/lib/fft.js"(exports, module) {
      "use strict";
      function FFT2(size) {
        this.size = size | 0;
        if (this.size <= 1 || (this.size & this.size - 1) !== 0)
          throw new Error("FFT size must be a power of two and bigger than 1");
        this._csize = size << 1;
        var table = new Array(this.size * 2);
        for (var i = 0; i < table.length; i += 2) {
          const angle = Math.PI * i / this.size;
          table[i] = Math.cos(angle);
          table[i + 1] = -Math.sin(angle);
        }
        this.table = table;
        var power = 0;
        for (var t = 1; this.size > t; t <<= 1)
          power++;
        this._width = power % 2 === 0 ? power - 1 : power;
        this._bitrev = new Array(1 << this._width);
        for (var j = 0; j < this._bitrev.length; j++) {
          this._bitrev[j] = 0;
          for (var shift = 0; shift < this._width; shift += 2) {
            var revShift = this._width - shift - 2;
            this._bitrev[j] |= (j >>> shift & 3) << revShift;
          }
        }
        this._out = null;
        this._data = null;
        this._inv = 0;
      }
      module.exports = FFT2;
      FFT2.prototype.fromComplexArray = function fromComplexArray(complex, storage) {
        var res = storage || new Array(complex.length >>> 1);
        for (var i = 0; i < complex.length; i += 2)
          res[i >>> 1] = complex[i];
        return res;
      };
      FFT2.prototype.createComplexArray = function createComplexArray() {
        const res = new Array(this._csize);
        for (var i = 0; i < res.length; i++)
          res[i] = 0;
        return res;
      };
      FFT2.prototype.toComplexArray = function toComplexArray(input, storage) {
        var res = storage || this.createComplexArray();
        for (var i = 0; i < res.length; i += 2) {
          res[i] = input[i >>> 1];
          res[i + 1] = 0;
        }
        return res;
      };
      FFT2.prototype.completeSpectrum = function completeSpectrum(spectrum) {
        var size = this._csize;
        var half = size >>> 1;
        for (var i = 2; i < half; i += 2) {
          spectrum[size - i] = spectrum[i];
          spectrum[size - i + 1] = -spectrum[i + 1];
        }
      };
      FFT2.prototype.transform = function transform(out, data) {
        if (out === data)
          throw new Error("Input and output buffers must be different");
        this._out = out;
        this._data = data;
        this._inv = 0;
        this._transform4();
        this._out = null;
        this._data = null;
      };
      FFT2.prototype.realTransform = function realTransform(out, data) {
        if (out === data)
          throw new Error("Input and output buffers must be different");
        this._out = out;
        this._data = data;
        this._inv = 0;
        this._realTransform4();
        this._out = null;
        this._data = null;
      };
      FFT2.prototype.inverseTransform = function inverseTransform(out, data) {
        if (out === data)
          throw new Error("Input and output buffers must be different");
        this._out = out;
        this._data = data;
        this._inv = 1;
        this._transform4();
        for (var i = 0; i < out.length; i++)
          out[i] /= this.size;
        this._out = null;
        this._data = null;
      };
      FFT2.prototype._transform4 = function _transform4() {
        var out = this._out;
        var size = this._csize;
        var width = this._width;
        var step = 1 << width;
        var len = size / step << 1;
        var outOff;
        var t;
        var bitrev = this._bitrev;
        if (len === 4) {
          for (outOff = 0, t = 0; outOff < size; outOff += len, t++) {
            const off = bitrev[t];
            this._singleTransform2(outOff, off, step);
          }
        } else {
          for (outOff = 0, t = 0; outOff < size; outOff += len, t++) {
            const off = bitrev[t];
            this._singleTransform4(outOff, off, step);
          }
        }
        var inv = this._inv ? -1 : 1;
        var table = this.table;
        for (step >>= 2; step >= 2; step >>= 2) {
          len = size / step << 1;
          var quarterLen = len >>> 2;
          for (outOff = 0; outOff < size; outOff += len) {
            var limit = outOff + quarterLen;
            for (var i = outOff, k = 0; i < limit; i += 2, k += step) {
              const A = i;
              const B = A + quarterLen;
              const C = B + quarterLen;
              const D = C + quarterLen;
              const Ar = out[A];
              const Ai = out[A + 1];
              const Br = out[B];
              const Bi = out[B + 1];
              const Cr = out[C];
              const Ci = out[C + 1];
              const Dr = out[D];
              const Di = out[D + 1];
              const MAr = Ar;
              const MAi = Ai;
              const tableBr = table[k];
              const tableBi = inv * table[k + 1];
              const MBr = Br * tableBr - Bi * tableBi;
              const MBi = Br * tableBi + Bi * tableBr;
              const tableCr = table[2 * k];
              const tableCi = inv * table[2 * k + 1];
              const MCr = Cr * tableCr - Ci * tableCi;
              const MCi = Cr * tableCi + Ci * tableCr;
              const tableDr = table[3 * k];
              const tableDi = inv * table[3 * k + 1];
              const MDr = Dr * tableDr - Di * tableDi;
              const MDi = Dr * tableDi + Di * tableDr;
              const T0r = MAr + MCr;
              const T0i = MAi + MCi;
              const T1r = MAr - MCr;
              const T1i = MAi - MCi;
              const T2r = MBr + MDr;
              const T2i = MBi + MDi;
              const T3r = inv * (MBr - MDr);
              const T3i = inv * (MBi - MDi);
              const FAr = T0r + T2r;
              const FAi = T0i + T2i;
              const FCr = T0r - T2r;
              const FCi = T0i - T2i;
              const FBr = T1r + T3i;
              const FBi = T1i - T3r;
              const FDr = T1r - T3i;
              const FDi = T1i + T3r;
              out[A] = FAr;
              out[A + 1] = FAi;
              out[B] = FBr;
              out[B + 1] = FBi;
              out[C] = FCr;
              out[C + 1] = FCi;
              out[D] = FDr;
              out[D + 1] = FDi;
            }
          }
        }
      };
      FFT2.prototype._singleTransform2 = function _singleTransform2(outOff, off, step) {
        const out = this._out;
        const data = this._data;
        const evenR = data[off];
        const evenI = data[off + 1];
        const oddR = data[off + step];
        const oddI = data[off + step + 1];
        const leftR = evenR + oddR;
        const leftI = evenI + oddI;
        const rightR = evenR - oddR;
        const rightI = evenI - oddI;
        out[outOff] = leftR;
        out[outOff + 1] = leftI;
        out[outOff + 2] = rightR;
        out[outOff + 3] = rightI;
      };
      FFT2.prototype._singleTransform4 = function _singleTransform4(outOff, off, step) {
        const out = this._out;
        const data = this._data;
        const inv = this._inv ? -1 : 1;
        const step2 = step * 2;
        const step3 = step * 3;
        const Ar = data[off];
        const Ai = data[off + 1];
        const Br = data[off + step];
        const Bi = data[off + step + 1];
        const Cr = data[off + step2];
        const Ci = data[off + step2 + 1];
        const Dr = data[off + step3];
        const Di = data[off + step3 + 1];
        const T0r = Ar + Cr;
        const T0i = Ai + Ci;
        const T1r = Ar - Cr;
        const T1i = Ai - Ci;
        const T2r = Br + Dr;
        const T2i = Bi + Di;
        const T3r = inv * (Br - Dr);
        const T3i = inv * (Bi - Di);
        const FAr = T0r + T2r;
        const FAi = T0i + T2i;
        const FBr = T1r + T3i;
        const FBi = T1i - T3r;
        const FCr = T0r - T2r;
        const FCi = T0i - T2i;
        const FDr = T1r - T3i;
        const FDi = T1i + T3r;
        out[outOff] = FAr;
        out[outOff + 1] = FAi;
        out[outOff + 2] = FBr;
        out[outOff + 3] = FBi;
        out[outOff + 4] = FCr;
        out[outOff + 5] = FCi;
        out[outOff + 6] = FDr;
        out[outOff + 7] = FDi;
      };
      FFT2.prototype._realTransform4 = function _realTransform4() {
        var out = this._out;
        var size = this._csize;
        var width = this._width;
        var step = 1 << width;
        var len = size / step << 1;
        var outOff;
        var t;
        var bitrev = this._bitrev;
        if (len === 4) {
          for (outOff = 0, t = 0; outOff < size; outOff += len, t++) {
            const off = bitrev[t];
            this._singleRealTransform2(outOff, off >>> 1, step >>> 1);
          }
        } else {
          for (outOff = 0, t = 0; outOff < size; outOff += len, t++) {
            const off = bitrev[t];
            this._singleRealTransform4(outOff, off >>> 1, step >>> 1);
          }
        }
        var inv = this._inv ? -1 : 1;
        var table = this.table;
        for (step >>= 2; step >= 2; step >>= 2) {
          len = size / step << 1;
          var halfLen = len >>> 1;
          var quarterLen = halfLen >>> 1;
          var hquarterLen = quarterLen >>> 1;
          for (outOff = 0; outOff < size; outOff += len) {
            for (var i = 0, k = 0; i <= hquarterLen; i += 2, k += step) {
              var A = outOff + i;
              var B = A + quarterLen;
              var C = B + quarterLen;
              var D = C + quarterLen;
              var Ar = out[A];
              var Ai = out[A + 1];
              var Br = out[B];
              var Bi = out[B + 1];
              var Cr = out[C];
              var Ci = out[C + 1];
              var Dr = out[D];
              var Di = out[D + 1];
              var MAr = Ar;
              var MAi = Ai;
              var tableBr = table[k];
              var tableBi = inv * table[k + 1];
              var MBr = Br * tableBr - Bi * tableBi;
              var MBi = Br * tableBi + Bi * tableBr;
              var tableCr = table[2 * k];
              var tableCi = inv * table[2 * k + 1];
              var MCr = Cr * tableCr - Ci * tableCi;
              var MCi = Cr * tableCi + Ci * tableCr;
              var tableDr = table[3 * k];
              var tableDi = inv * table[3 * k + 1];
              var MDr = Dr * tableDr - Di * tableDi;
              var MDi = Dr * tableDi + Di * tableDr;
              var T0r = MAr + MCr;
              var T0i = MAi + MCi;
              var T1r = MAr - MCr;
              var T1i = MAi - MCi;
              var T2r = MBr + MDr;
              var T2i = MBi + MDi;
              var T3r = inv * (MBr - MDr);
              var T3i = inv * (MBi - MDi);
              var FAr = T0r + T2r;
              var FAi = T0i + T2i;
              var FBr = T1r + T3i;
              var FBi = T1i - T3r;
              out[A] = FAr;
              out[A + 1] = FAi;
              out[B] = FBr;
              out[B + 1] = FBi;
              if (i === 0) {
                var FCr = T0r - T2r;
                var FCi = T0i - T2i;
                out[C] = FCr;
                out[C + 1] = FCi;
                continue;
              }
              if (i === hquarterLen)
                continue;
              var ST0r = T1r;
              var ST0i = -T1i;
              var ST1r = T0r;
              var ST1i = -T0i;
              var ST2r = -inv * T3i;
              var ST2i = -inv * T3r;
              var ST3r = -inv * T2i;
              var ST3i = -inv * T2r;
              var SFAr = ST0r + ST2r;
              var SFAi = ST0i + ST2i;
              var SFBr = ST1r + ST3i;
              var SFBi = ST1i - ST3r;
              var SA = outOff + quarterLen - i;
              var SB = outOff + halfLen - i;
              out[SA] = SFAr;
              out[SA + 1] = SFAi;
              out[SB] = SFBr;
              out[SB + 1] = SFBi;
            }
          }
        }
      };
      FFT2.prototype._singleRealTransform2 = function _singleRealTransform2(outOff, off, step) {
        const out = this._out;
        const data = this._data;
        const evenR = data[off];
        const oddR = data[off + step];
        const leftR = evenR + oddR;
        const rightR = evenR - oddR;
        out[outOff] = leftR;
        out[outOff + 1] = 0;
        out[outOff + 2] = rightR;
        out[outOff + 3] = 0;
      };
      FFT2.prototype._singleRealTransform4 = function _singleRealTransform4(outOff, off, step) {
        const out = this._out;
        const data = this._data;
        const inv = this._inv ? -1 : 1;
        const step2 = step * 2;
        const step3 = step * 3;
        const Ar = data[off];
        const Br = data[off + step];
        const Cr = data[off + step2];
        const Dr = data[off + step3];
        const T0r = Ar + Cr;
        const T1r = Ar - Cr;
        const T2r = Br + Dr;
        const T3r = inv * (Br - Dr);
        const FAr = T0r + T2r;
        const FBr = T1r;
        const FBi = -T3r;
        const FCr = T0r - T2r;
        const FDr = T1r;
        const FDi = T3r;
        out[outOff] = FAr;
        out[outOff + 1] = 0;
        out[outOff + 2] = FBr;
        out[outOff + 3] = FBi;
        out[outOff + 4] = FCr;
        out[outOff + 5] = 0;
        out[outOff + 6] = FDr;
        out[outOff + 7] = FDi;
      };
    }
  });

  // src/device-entry.js
  var device_entry_exports = {};
  __export(device_entry_exports, {
    analyze: () => analyze,
    score: () => score
  });

  // node_modules/pitchy/index.js
  var import_fft = __toESM(require_fft(), 1);
  var Autocorrelator = class _Autocorrelator {
    /** @private @readonly @type {number} */
    _inputLength;
    /** @private @type {FFT} */
    _fft;
    /** @private @type {(size: number) => T} */
    _bufferSupplier;
    /** @private @type {T} */
    _paddedInputBuffer;
    /** @private @type {T} */
    _transformBuffer;
    /** @private @type {T} */
    _inverseBuffer;
    /**
     * A helper method to create an {@link Autocorrelator} using
     * {@link Float32Array} buffers.
     *
     * @param inputLength {number} the input array length to support
     * @returns {Autocorrelator<Float32Array>}
     */
    static forFloat32Array(inputLength) {
      return new _Autocorrelator(
        inputLength,
        (length) => new Float32Array(length)
      );
    }
    /**
     * A helper method to create an {@link Autocorrelator} using
     * {@link Float64Array} buffers.
     *
     * @param inputLength {number} the input array length to support
     * @returns {Autocorrelator<Float64Array>}
     */
    static forFloat64Array(inputLength) {
      return new _Autocorrelator(
        inputLength,
        (length) => new Float64Array(length)
      );
    }
    /**
     * A helper method to create an {@link Autocorrelator} using `number[]`
     * buffers.
     *
     * @param inputLength {number} the input array length to support
     * @returns {Autocorrelator<number[]>}
     */
    static forNumberArray(inputLength) {
      return new _Autocorrelator(inputLength, (length) => Array(length));
    }
    /**
     * Constructs a new {@link Autocorrelator} able to handle input arrays of the
     * given length.
     *
     * @param inputLength {number} the input array length to support. This
     * `Autocorrelator` will only support operation on arrays of this length.
     * @param bufferSupplier {(length: number) => T} the function to use for
     * creating buffers, accepting the length of the buffer to create and
     * returning a new buffer of that length. The values of the returned buffer
     * need not be initialized in any particular way.
     */
    constructor(inputLength, bufferSupplier) {
      if (inputLength < 1) {
        throw new Error(`Input length must be at least one`);
      }
      this._inputLength = inputLength;
      this._fft = new import_fft.default(ceilPow2(2 * inputLength));
      this._bufferSupplier = bufferSupplier;
      this._paddedInputBuffer = this._bufferSupplier(this._fft.size);
      this._transformBuffer = this._bufferSupplier(2 * this._fft.size);
      this._inverseBuffer = this._bufferSupplier(2 * this._fft.size);
    }
    /**
     * Returns the supported input length.
     *
     * @returns {number} the supported input length
     */
    get inputLength() {
      return this._inputLength;
    }
    /**
     * Autocorrelates the given input data.
     *
     * @param input {ArrayLike<number>} the input data to autocorrelate
     * @param output {T} the output buffer into which to write the autocorrelated
     * data. If not provided, a new buffer will be created.
     * @returns {T} `output`
     */
    autocorrelate(input, output = this._bufferSupplier(input.length)) {
      if (input.length !== this._inputLength) {
        throw new Error(
          `Input must have length ${this._inputLength} but had length ${input.length}`
        );
      }
      for (let i = 0; i < input.length; i++) {
        this._paddedInputBuffer[i] = input[i];
      }
      for (let i = input.length; i < this._paddedInputBuffer.length; i++) {
        this._paddedInputBuffer[i] = 0;
      }
      this._fft.realTransform(this._transformBuffer, this._paddedInputBuffer);
      this._fft.completeSpectrum(this._transformBuffer);
      const tb = this._transformBuffer;
      for (let i = 0; i < tb.length; i += 2) {
        tb[i] = tb[i] * tb[i] + tb[i + 1] * tb[i + 1];
        tb[i + 1] = 0;
      }
      this._fft.inverseTransform(this._inverseBuffer, this._transformBuffer);
      for (let i = 0; i < input.length; i++) {
        output[i] = this._inverseBuffer[2 * i];
      }
      return output;
    }
  };
  function getKeyMaximumIndices(input) {
    const keyIndices = [];
    let lookingForMaximum = false;
    let max = -Infinity;
    let maxIndex = -1;
    for (let i = 1; i < input.length - 1; i++) {
      if (input[i - 1] <= 0 && input[i] > 0) {
        lookingForMaximum = true;
        maxIndex = i;
        max = input[i];
      } else if (input[i - 1] > 0 && input[i] <= 0) {
        lookingForMaximum = false;
        if (maxIndex !== -1) {
          keyIndices.push(maxIndex);
        }
      } else if (lookingForMaximum && input[i] > max) {
        max = input[i];
        maxIndex = i;
      }
    }
    return keyIndices;
  }
  function refineResultIndex(index, data) {
    const [x0, x1, x2] = [index - 1, index, index + 1];
    const [y0, y1, y2] = [data[x0], data[x1], data[x2]];
    const a = y0 / 2 - y1 + y2 / 2;
    const b = -(y0 / 2) * (x1 + x2) + y1 * (x0 + x2) - y2 / 2 * (x0 + x1);
    const c = y0 * x1 * x2 / 2 - y1 * x0 * x2 + y2 * x0 * x1 / 2;
    const xMax = -b / (2 * a);
    const yMax = a * xMax * xMax + b * xMax + c;
    return [xMax, yMax];
  }
  var PitchDetector = class _PitchDetector {
    /** @private @type {Autocorrelator<T>} */
    _autocorrelator;
    /** @private @type {T} */
    _nsdfBuffer;
    /** @private @type {number} */
    _clarityThreshold = 0.9;
    /** @private @type {number} */
    _minVolumeAbsolute = 0;
    /** @private @type {number} */
    _maxInputAmplitude = 1;
    /**
     * A helper method to create an {@link PitchDetector} using {@link Float32Array} buffers.
     *
     * @param inputLength {number} the input array length to support
     * @returns {PitchDetector<Float32Array>}
     */
    static forFloat32Array(inputLength) {
      return new _PitchDetector(inputLength, (length) => new Float32Array(length));
    }
    /**
     * A helper method to create an {@link PitchDetector} using {@link Float64Array} buffers.
     *
     * @param inputLength {number} the input array length to support
     * @returns {PitchDetector<Float64Array>}
     */
    static forFloat64Array(inputLength) {
      return new _PitchDetector(inputLength, (length) => new Float64Array(length));
    }
    /**
     * A helper method to create an {@link PitchDetector} using `number[]` buffers.
     *
     * @param inputLength {number} the input array length to support
     * @returns {PitchDetector<number[]>}
     */
    static forNumberArray(inputLength) {
      return new _PitchDetector(inputLength, (length) => Array(length));
    }
    /**
     * Constructs a new {@link PitchDetector} able to handle input arrays of the
     * given length.
     *
     * @param inputLength {number} the input array length to support. This
     * `PitchDetector` will only support operation on arrays of this length.
     * @param bufferSupplier {(inputLength: number) => T} the function to use for
     * creating buffers, accepting the length of the buffer to create and
     * returning a new buffer of that length. The values of the returned buffer
     * need not be initialized in any particular way.
     */
    constructor(inputLength, bufferSupplier) {
      this._autocorrelator = new Autocorrelator(inputLength, bufferSupplier);
      this._nsdfBuffer = bufferSupplier(inputLength);
    }
    /**
     * Returns the supported input length.
     *
     * @returns {number} the supported input length
     */
    get inputLength() {
      return this._autocorrelator.inputLength;
    }
    /**
     * Sets the clarity threshold used when identifying the correct pitch (the constant
     * `k` from the MPM paper). The value must be between 0 (exclusive) and 1
     * (inclusive), with the most suitable range being between 0.8 and 1.
     *
     * @param threshold {number} the clarity threshold
     */
    set clarityThreshold(threshold) {
      if (!Number.isFinite(threshold) || threshold <= 0 || threshold > 1) {
        throw new Error("clarityThreshold must be a number in the range (0, 1]");
      }
      this._clarityThreshold = threshold;
    }
    /**
     * Sets the minimum detectable volume, as an absolute number between 0 and
     * `maxInputAmplitude`, inclusive, to consider in a sample when detecting the
     * pitch. If a sample fails to meet this minimum volume, `findPitch` will
     * return a clarity of 0.
     *
     * Volume is calculated as the RMS (root mean square) of the input samples.
     *
     * @param volume {number} the minimum volume as an absolute amplitude value
     */
    set minVolumeAbsolute(volume) {
      if (!Number.isFinite(volume) || volume < 0 || volume > this._maxInputAmplitude) {
        throw new Error(
          `minVolumeAbsolute must be a number in the range [0, ${this._maxInputAmplitude}]`
        );
      }
      this._minVolumeAbsolute = volume;
    }
    /**
     * Sets the minimum volume using a decibel measurement. Must be less than or
     * equal to 0: 0 indicates the loudest possible sound (see
     * `maxInputAmplitude`), -10 is a sound with a tenth of the volume of the
     * loudest possible sound, etc.
     *
     * Volume is calculated as the RMS (root mean square) of the input samples.
     *
     * @param db {number} the minimum volume in decibels, with 0 being the loudest
     * sound
     */
    set minVolumeDecibels(db) {
      if (!Number.isFinite(db) || db > 0) {
        throw new Error("minVolumeDecibels must be a number <= 0");
      }
      this._minVolumeAbsolute = this._maxInputAmplitude * 10 ** (db / 10);
    }
    /**
     * Sets the maximum amplitude of an input reading. Must be greater than 0.
     *
     * @param amplitude {number} the maximum amplitude (absolute value) of an input reading
     */
    set maxInputAmplitude(amplitude) {
      if (!Number.isFinite(amplitude) || amplitude <= 0) {
        throw new Error("maxInputAmplitude must be a number > 0");
      }
      this._maxInputAmplitude = amplitude;
    }
    /**
     * Returns the pitch detected using McLeod Pitch Method (MPM) along with a
     * measure of its clarity.
     *
     * The clarity is a value between 0 and 1 (potentially inclusive) that
     * represents how "clear" the pitch was. A clarity value of 1 indicates that
     * the pitch was very distinct, while lower clarity values indicate less
     * definite pitches.
     *
     * @param input {ArrayLike<number>} the time-domain input data
     * @param sampleRate {number} the sample rate at which the input data was
     * collected
     * @returns {[number, number]} the detected pitch, in Hz, followed by the
     * clarity. If a pitch cannot be determined from the input, such as if the
     * volume is too low (see `minVolumeAbsolute` and `minVolumeDecibels`), this
     * will be `[0, 0]`.
     */
    findPitch(input, sampleRate) {
      if (this._belowMinimumVolume(input)) return [0, 0];
      this._nsdf(input);
      const keyMaximumIndices = getKeyMaximumIndices(this._nsdfBuffer);
      if (keyMaximumIndices.length === 0) {
        return [0, 0];
      }
      const nMax = Math.max(...keyMaximumIndices.map((i) => this._nsdfBuffer[i]));
      const resultIndex = keyMaximumIndices.find(
        (i) => this._nsdfBuffer[i] >= this._clarityThreshold * nMax
      );
      const [refinedResultIndex, clarity] = refineResultIndex(
        // @ts-expect-error resultIndex is guaranteed to be defined
        resultIndex,
        this._nsdfBuffer
      );
      return [sampleRate / refinedResultIndex, Math.min(clarity, 1)];
    }
    /**
     * Returns whether the input audio data is below the minimum volume allowed by
     * the pitch detector.
     *
     * @private
     * @param input {ArrayLike<number>}
     * @returns {boolean}
     */
    _belowMinimumVolume(input) {
      if (this._minVolumeAbsolute === 0) return false;
      let squareSum = 0;
      for (let i = 0; i < input.length; i++) {
        squareSum += input[i] ** 2;
      }
      return Math.sqrt(squareSum / input.length) < this._minVolumeAbsolute;
    }
    /**
     * Computes the NSDF of the input and stores it in the internal buffer. This
     * is equation (9) in the McLeod pitch method paper.
     *
     * @private
     * @param input {ArrayLike<number>}
     */
    _nsdf(input) {
      this._autocorrelator.autocorrelate(input, this._nsdfBuffer);
      let m = 2 * this._nsdfBuffer[0];
      let i;
      for (i = 0; i < this._nsdfBuffer.length && m > 0; i++) {
        this._nsdfBuffer[i] = 2 * this._nsdfBuffer[i] / m;
        m -= input[i] ** 2 + input[input.length - i - 1] ** 2;
      }
      for (; i < this._nsdfBuffer.length; i++) {
        this._nsdfBuffer[i] = 0;
      }
    }
  };
  function ceilPow2(v) {
    v--;
    v |= v >> 1;
    v |= v >> 2;
    v |= v >> 4;
    v |= v >> 8;
    v |= v >> 16;
    v++;
    return v;
  }

  // src/config.js
  var SAMPLE_RATE = 16e3;
  var DEFAULTS = Object.freeze({
    maxInputBytes: 16 * 1024 * 1024,
    maxTurnSeconds: 90,
    maxConversationSeconds: 300,
    maxTurns: 20,
    timeoutMs: 18e4,
    frameSamples: 400,
    hopSamples: 160,
    pitchFrameSamples: 1024,
    minPitchHz: 60,
    maxPitchHz: 500,
    minPitchClarity: 0.9,
    minPitchSeconds: 3,
    minPitchCoverage: 0.2,
    minDynamicRangeDb: 15,
    minActiveLevelDb: -45,
    minPauseSeconds: 0.3,
    maxClippedFraction: 0.01,
    minPaceWords: 20,
    minPaceSeconds: 10,
    insightsEnabled: false
  });
  function configuration(overrides = {}) {
    if (!overrides || typeof overrides !== "object" || Array.isArray(overrides)) {
      throw new TypeError("config must be an object");
    }
    for (const key of Object.keys(overrides)) {
      if (!(key in DEFAULTS)) throw new TypeError(`Unknown config key: ${key}`);
    }
    const config = { ...DEFAULTS, ...overrides };
    for (const [key, value] of Object.entries(config)) {
      if (key === "insightsEnabled") {
        if (typeof value !== "boolean") throw new TypeError(`${key} must be boolean`);
      } else if (key === "minActiveLevelDb") {
        if (!Number.isFinite(value) || value >= 0) throw new TypeError(`${key} must be negative`);
      } else if (!Number.isFinite(value) || value <= 0) {
        throw new TypeError(`${key} must be a positive finite number`);
      }
    }
    for (const key of ["maxInputBytes", "maxTurns", "timeoutMs", "frameSamples", "hopSamples", "pitchFrameSamples"]) {
      if (!Number.isSafeInteger(config[key])) throw new TypeError(`${key} must be an integer`);
    }
    if (config.minPitchHz >= config.maxPitchHz || config.maxPitchHz >= SAMPLE_RATE / 2) {
      throw new TypeError("Invalid pitch frequency range");
    }
    for (const key of ["minPitchClarity", "minPitchCoverage", "maxClippedFraction"]) {
      if (config[key] > 1) throw new TypeError(`${key} must be <= 1`);
    }
    return config;
  }

  // src/math.js
  function quantile(values, fraction) {
    if (!values.length) return null;
    const sorted = [...values].sort((a, b) => a - b);
    const index = (sorted.length - 1) * fraction;
    const lower = Math.floor(index);
    return sorted[lower] + (sorted[Math.ceil(index)] - sorted[lower]) * (index - lower);
  }
  function spread(values) {
    return values.length ? quantile(values, 0.9) - quantile(values, 0.1) : null;
  }
  function metric(value, unit, status = "available", reason = null) {
    return { value: Number.isFinite(value) ? value : null, unit, status, reason };
  }
  function unavailable(unit, reason) {
    return metric(null, unit, "unavailable", reason);
  }

  // src/acoustics.js
  function removePitchOutliers(track) {
    return track.map((point, i) => {
      if (point.hz === null) return point;
      const neighbors = track.slice(Math.max(0, i - 3), i).concat(track.slice(i + 1, i + 4)).filter((p) => p.hz !== null);
      const before = neighbors.some((p) => p.time < point.time);
      const after = neighbors.some((p) => p.time > point.time);
      if (!before || !after || neighbors.length < 4) return point;
      const semitones = neighbors.map((p) => 12 * Math.log2(p.hz));
      const median = quantile(semitones, 0.5);
      if (Math.max(...semitones) - Math.min(...semitones) <= 3 && Math.abs(12 * Math.log2(point.hz) - median) > 9) {
        return { ...point, hz: null };
      }
      return point;
    });
  }
  function activeIntervals(frames, hopSeconds, duration, onThreshold, offThreshold) {
    let active = false;
    let candidate = null;
    let start = null;
    const intervals = [];
    for (let i = 0; i < frames.length; i++) {
      const wantsChange = active ? frames[i] < offThreshold : frames[i] > onThreshold;
      if (!wantsChange) {
        candidate = null;
        continue;
      }
      candidate ??= i;
      if ((i - candidate + 1) * hopSeconds < 0.1 - 1e-9) continue;
      const boundary = candidate * hopSeconds;
      if (active) intervals.push({ start, end: boundary });
      else start = boundary;
      active = !active;
      candidate = null;
    }
    if (active) intervals.push({ start, end: duration });
    return intervals;
  }
  function analyzeAcoustics(samples, overrides = {}) {
    const config = configuration(overrides);
    if (!(samples instanceof Float32Array) || !samples.length) {
      throw new TypeError("samples must be a nonempty mono Float32Array at 16000 Hz");
    }
    const duration = samples.length / SAMPLE_RATE;
    if (duration > config.maxTurnSeconds) throw new RangeError("Audio exceeds maxTurnSeconds");
    let clipped = 0;
    for (const sample of samples) {
      if (!Number.isFinite(sample) || Math.abs(sample) > 1.00001) {
        throw new TypeError("PCM samples must be finite and normalized to [-1, 1]");
      }
      if (Math.abs(sample) >= 0.999) clipped++;
    }
    const hopSeconds = config.hopSamples / SAMPLE_RATE;
    const levels = [];
    for (let start = 0; start + config.frameSamples <= samples.length; start += config.hopSamples) {
      let power = 0;
      for (let j = start; j < start + config.frameSamples; j++) power += samples[j] ** 2;
      levels.push(20 * Math.log10(Math.max(Math.sqrt(power / config.frameSamples), 1e-8)));
    }
    const noise = quantile(levels, 0.1) ?? -160;
    const high = quantile(levels, 0.9) ?? -160;
    const clippedFraction = clipped / samples.length;
    const flags = [];
    if (high < config.minActiveLevelDb) flags.push("low_signal");
    if (high - noise < config.minDynamicRangeDb) flags.push("insufficient_level_separation");
    if (clippedFraction > config.maxClippedFraction) flags.push("clipping");
    const intervals = activeIntervals(
      levels,
      hopSeconds,
      duration,
      Math.max(-60, noise + 10),
      Math.max(-63, noise + 6)
    );
    if (!intervals.length) flags.push("no_activity_detected");
    const activityReliable = flags.length === 0;
    const isActive = (time) => intervals.some((p) => time >= p.start && time < p.end);
    const pauses = intervals.slice(1).map((p, i) => ({ start: intervals[i].end, end: p.start })).filter((p) => p.end - p.start >= config.minPauseSeconds);
    const responseSpan = intervals.length ? intervals.at(-1).end - intervals[0].start : 0;
    const pauseSeconds = pauses.reduce((sum, p) => sum + p.end - p.start, 0);
    const activeSeconds = intervals.reduce((sum, p) => sum + p.end - p.start, 0);
    const detector = PitchDetector.forFloat32Array(config.pitchFrameSamples);
    const track = [];
    let activePitchFrames = 0;
    for (let start = 0; start + config.pitchFrameSamples <= samples.length; start += config.hopSamples) {
      const time = (start + config.pitchFrameSamples / 2) / SAMPLE_RATE;
      const active = isActive(time);
      if (active) activePitchFrames++;
      let hz = null;
      let clarity = null;
      if (active) {
        [hz, clarity] = detector.findPitch(samples.subarray(start, start + config.pitchFrameSamples), SAMPLE_RATE);
        if (!Number.isFinite(hz) || !Number.isFinite(clarity) || clarity < config.minPitchClarity || hz < config.minPitchHz || hz > config.maxPitchHz) hz = null;
      }
      track.push({ time, hz, clarity });
    }
    const cleanTrack = removePitchOutliers(track);
    const voiced = cleanTrack.filter((p) => p.hz !== null);
    const medianPitch = quantile(voiced.map((p) => p.hz), 0.5);
    const semitones = voiced.map((p) => 12 * Math.log2(p.hz / medianPitch));
    const pitchSeconds = voiced.length * hopSeconds;
    const coverage = activePitchFrames ? voiced.length / activePitchFrames : 0;
    const pitchReliable = activityReliable && pitchSeconds >= config.minPitchSeconds && coverage >= config.minPitchCoverage;
    const pitchWindows = [];
    for (let start = 0; start + 5 <= duration + 1e-9; start += 5) {
      const points = voiced.filter((p) => p.time >= start && p.time < start + 5);
      if (points.length * hopSeconds >= 1.5) {
        pitchWindows.push({ start, end: start + 5, range: spread(points.map((p) => 12 * Math.log2(p.hz / medianPitch))) });
      }
    }
    const smoothed = [];
    const halfWindow = Math.round(0.1 / hopSeconds);
    for (const interval of intervals) {
      const indices = levels.map((_, i) => i).filter((i) => {
        const center = i * hopSeconds + config.frameSamples / SAMPLE_RATE / 2;
        return center >= interval.start && center < interval.end;
      });
      for (let j = 0; j < indices.length; j++) {
        const neighborhood = indices.slice(Math.max(0, j - halfWindow), j + halfWindow + 1);
        smoothed.push({ time: indices[j] * hopSeconds, db: quantile(neighborhood.map((i) => levels[i]), 0.5) });
      }
    }
    const medianLevel = quantile(smoothed.map((p) => p.db), 0.5);
    const centeredLevels = smoothed.map((p) => p.db - medianLevel);
    const volumeWindows = [];
    for (let start = 0; start + 1 <= duration + 1e-9; start++) {
      const points = smoothed.filter((p) => p.time >= start && p.time < start + 1);
      if (points.length * hopSeconds >= 0.7) volumeWindows.push({ start, end: start + 1, db: quantile(points.map((p) => p.db), 0.5) });
    }
    const activityReason = flags[0] ?? "insufficient_activity";
    const activityMetric = (value, unit) => activityReliable ? metric(value, unit, "experimental", "energy_based_activity") : unavailable(unit, activityReason);
    return {
      duration,
      flags,
      activityReliable,
      pitchReliable,
      intervals,
      pauses: activityReliable ? pauses : [],
      metrics: {
        responseSeconds: activityMetric(responseSpan, "seconds"),
        activeSeconds: activityMetric(activeSeconds, "seconds"),
        pauseSeconds: activityMetric(pauseSeconds, "seconds"),
        pauseRatio: activityMetric(responseSpan ? pauseSeconds / responseSpan : 0, "ratio"),
        longestPauseSeconds: activityMetric(Math.max(0, ...pauses.map((p) => p.end - p.start)), "seconds"),
        medianPitchHz: pitchReliable ? metric(medianPitch, "Hz") : unavailable("Hz", activityReliable ? "insufficient_reliable_pitch" : activityReason),
        pitchRangeSemitones: pitchReliable ? metric(spread(semitones), "semitones") : unavailable("semitones", activityReliable ? "insufficient_reliable_pitch" : activityReason),
        pitchCoverage: metric(coverage, "ratio"),
        reliablePitchSeconds: metric(pitchSeconds, "seconds"),
        volumeSpreadDb: activityMetric(spread(centeredLevels), "dB"),
        clippedFraction: metric(clippedFraction, "ratio")
      },
      // Internal sufficient statistics are removed from public JSON reports.
      evidence: { pitchWindows: pitchReliable ? pitchWindows : [], volumeWindows: activityReliable ? volumeWindows : [] },
      distributions: { semitones: pitchReliable ? semitones : [], levels: activityReliable ? centeredLevels : [] }
    };
  }

  // src/scoring.js
  var SCORING_VERSION = "delivery-rules-1";
  var round = (value) => Math.round(value * 10) / 10;
  var usable = (metric2) => metric2 && ["available", "experimental"].includes(metric2.status) && Number.isFinite(metric2.value) && metric2.value >= 0;
  function bandScore(value, floor, low, high, ceiling) {
    if (![value, floor, low, high, ceiling].every(Number.isFinite) || !(floor < low && low <= high && high < ceiling)) throw new TypeError("Invalid scoring band");
    if (value <= floor || value >= ceiling) return 0;
    if (value < low) return 100 * (value - floor) / (low - floor);
    if (value > high) return 100 * (ceiling - value) / (ceiling - high);
    return 100;
  }
  function combineCategories(categories) {
    if (!Array.isArray(categories)) throw new TypeError("Categories must be an array");
    const names = /* @__PURE__ */ new Set();
    for (const category of categories) {
      if (!category || typeof category.name !== "string" || !category.name || names.has(category.name) || !Number.isFinite(category.weight) || category.weight < 0 || !["available", "experimental", "unavailable"].includes(category.reliability) || category.score !== null && (!Number.isFinite(category.score) || category.score < 0 || category.score > 100)) {
        throw new TypeError("Invalid or duplicate scoring category");
      }
      names.add(category.name);
    }
    const active = categories.filter((category) => category.weight > 0);
    const totalWeight = active.reduce((sum, category) => sum + category.weight, 0);
    if (!Number.isFinite(totalWeight)) throw new TypeError("Category weights overflow");
    const missing = active.filter((category) => category.score === null || category.reliability === "unavailable");
    const experimental = active.filter((category) => category.reliability === "experimental").map((category) => category.name);
    const observedWeight = active.filter((category) => category.score !== null && category.reliability !== "unavailable").reduce((sum, category) => sum + category.weight, 0);
    const complete = active.length > 0 && missing.length === 0;
    return {
      overallVoiceScore: complete ? round(active.reduce((sum, category) => sum + category.score * (category.weight / totalWeight), 0)) : null,
      reliability: !complete ? "unavailable" : experimental.length ? "experimental" : "available",
      reason: !active.length ? "no_weighted_categories" : missing.length ? "required_categories_unavailable" : experimental.length ? "experimental_inputs" : null,
      missingCategories: missing.map((category) => category.name),
      experimentalCategories: experimental,
      weightCoverage: totalWeight ? observedWeight / totalWeight : 0,
      missingPolicy: "require_all"
    };
  }
  function scoreVoiceMetrics(metrics, configOverrides = {}) {
    if (!metrics || typeof metrics !== "object" || Array.isArray(metrics)) throw new TypeError("Metrics must be an object");
    const config = configuration(configOverrides);
    const categories = [];
    const feedback = [];
    function add(name, weight, metricName, score2, extraIssues = [], dependencies = []) {
      const metric2 = metrics[metricName];
      const reasons = [...extraIssues];
      if (!usable(metric2)) reasons.push(metric2?.reason ?? "invalid_or_missing_metric");
      const valid = reasons.length === 0;
      const inputs = [metric2, ...dependencies];
      const reliability = !valid ? "unavailable" : name === "fillers" || inputs.some((input) => input?.status === "experimental") ? "experimental" : "available";
      categories.push({
        name,
        weight,
        score: valid ? score2(metric2.value) : null,
        reliability,
        metric: metricName,
        value: usable(metric2) ? metric2.value : null,
        reasons: valid ? [.../* @__PURE__ */ new Set([
          ...inputs.map((input) => input?.reason).filter(Boolean),
          ...name === "fillers" ? ["filler_completeness_unvalidated"] : []
        ])] : reasons
      });
      return valid;
    }
    const pitchIssues = [];
    if (!usable(metrics.pitchCoverage) || metrics.pitchCoverage.value > 1 || metrics.pitchCoverage.value < config.minPitchCoverage) {
      pitchIssues.push("insufficient_pitch_coverage");
    }
    if (!usable(metrics.reliablePitchSeconds) || metrics.reliablePitchSeconds.value < config.minPitchSeconds) {
      pitchIssues.push("insufficient_reliable_pitch_seconds");
    }
    if (add(
      "pitch",
      0.35,
      "pitchRangeSemitones",
      (v) => bandScore(v, 0, 3, 8, 16),
      pitchIssues,
      [metrics.pitchCoverage, metrics.reliablePitchSeconds]
    )) {
      const value = metrics.pitchRangeSemitones.value;
      const band = value < 3 ? "below" : value > 8 ? "above" : "within";
      feedback.push({
        category: "pitch",
        code: `pitch_${band}_target`,
        value,
        unit: "semitones",
        target: [3, 8],
        message: `Measured pitch variation was ${round(value)} semitones, ${band} the provisional 3-8 semitone target. This does not measure confidence or emotion.`
      });
    }
    if (add("fillers", 0.2, "detectedFillersPer100Words", (v) => 100 / (1 + (v / 6) ** 2))) {
      const value = metrics.detectedFillersPer100Words.value;
      feedback.push({
        category: "fillers",
        code: value > 2 ? "observed_fillers_above_target" : "observed_fillers_within_target",
        value,
        unit: "events/100 words",
        target: [0, 2],
        message: value === 0 ? "No um/uh fillers were detected (0 per 100 words); this does not establish that none were spoken." : `Detected ${round(value)} um/uh fillers per 100 words, ${value > 2 ? "above" : "within"} the provisional 0-2 target. Some spoken fillers may be missing.`
      });
    }
    if (add("pace", 0.45, "speakingRateWpm", (v) => bandScore(v, 60, 120, 180, 260))) {
      const value = metrics.speakingRateWpm.value;
      const band = value < 120 ? "below" : value > 180 ? "above" : "within";
      feedback.push({
        category: "pace",
        code: `pace_${band}_target`,
        value,
        unit: "words/minute",
        target: [120, 180],
        message: `Estimated pace was ${round(value)} words/minute, ${band} the provisional 120-180 target.`
      });
    }
    const composite = combineCategories(categories);
    return {
      version: SCORING_VERSION,
      scale: [0, 100],
      ...composite,
      // Even fully available measurements do not validate the scoring policy.
      reliability: composite.overallVoiceScore === null ? "unavailable" : "experimental",
      reason: composite.overallVoiceScore === null ? composite.reason : "unvalidated_scoring_policy",
      inputReliability: composite.reliability,
      categories: categories.map((category) => ({ ...category, score: category.score === null ? null : round(category.score) })),
      feedback
    };
  }

  // src/apple-report.js
  var normalize = (text) => text.toLowerCase().replace(/^[^\p{L}\p{N}]+|[^\p{L}\p{N}]+$/gu, "");
  var isFiller = (word) => ["um", "uh"].includes(normalize(word.text));
  function buildAppleReport(transcript, acoustic, config) {
    if (typeof transcript?.text !== "string" || !transcript.text.trim() || !Array.isArray(transcript.words) || !Array.isArray(transcript.timingIssues) || !Number.isFinite(transcript.duration) || transcript.duration <= 0) {
      throw new Error("Invalid Apple transcription output");
    }
    const issues = [...transcript.timingIssues];
    let previousEnd = 0;
    for (const word of transcript.words) {
      if (typeof word.text !== "string" || !word.text.trim() || /\s/.test(word.text) || !Number.isFinite(word.start) || !Number.isFinite(word.end) || word.start < 0 || word.end <= word.start || word.end > transcript.duration + 0.05 || word.start < previousEnd - 1e-3) {
        issues.push("invalid_word_timing");
      }
      previousEnd = word.end;
    }
    if (!transcript.words.length) issues.push("word_timing_unavailable");
    const timingsValid = issues.length === 0;
    const words = timingsValid ? transcript.words : [];
    const fillers = words.filter(isFiller);
    const lexicalWordCount = words.filter((word) => !isFiller(word)).length;
    const span = words.length ? words.at(-1).end - words[0].start : 0;
    const gaps = [];
    for (let i = 1; i < words.length; i++) {
      if (words[i].start - words[i - 1].end >= config.minPauseSeconds) {
        gaps.push({ start: words[i - 1].end, end: words[i].start });
      }
    }
    const enoughPace = timingsValid && lexicalWordCount >= config.minPaceWords && span >= config.minPaceSeconds;
    const missing = timingsValid ? "insufficient_words_or_duration" : "word_timing_unavailable";
    const report = {
      schemaVersion: 1,
      analysisVersion: "apple-speech-2",
      status: !timingsValid ? "failed" : Object.values(acoustic.metrics).some((m) => m.value === null) ? "partial" : "complete",
      overallVoiceScore: null,
      transcriptionEngine: "Apple SpeechAnalyzer / SpeechTranscriber",
      durationSeconds: acoustic.duration,
      transcript: { ...transcript, timingIssues: issues, timingsValid, fillerPreservation: "unvalidated" },
      lexicalWordCount: timingsValid ? lexicalWordCount : null,
      detectedFillerCount: timingsValid ? fillers.length : null,
      metrics: {
        ...acoustic.metrics,
        speakingRateWpm: enoughPace ? metric(60 * lexicalWordCount / span, "words/minute", "experimental", "apple_word_timing_estimate") : unavailable("words/minute", missing),
        timestampGapRatio: timingsValid && span > 0 ? metric(gaps.reduce((sum, gap) => sum + gap.end - gap.start, 0) / span, "ratio", "experimental", "gaps_between_recognized_words") : unavailable("ratio", "word_timing_unavailable"),
        detectedFillersPer100Words: timingsValid && lexicalWordCount > 0 ? metric(100 * fillers.length / lexicalWordCount, "events/100 words", "experimental", "filler_completeness_unvalidated") : unavailable("events/100 words", missing)
      },
      evidence: { fillers, timestampGaps: gaps, energyPauses: acoustic.pauses },
      flags: acoustic.flags,
      config,
      warnings: [
        "Observed fillers are not a verified complete count; compare with the recording.",
        "Word timestamps are model estimates; gaps can include unrecognized speech.",
        "Acoustic pause metrics still use energy detection. Pitch quality gates are unchanged.",
        "Delivery scores use provisional product targets, not validated measures of communication ability."
      ]
    };
    report.scoring = scoreVoiceMetrics(report.metrics, config);
    report.overallVoiceScore = report.scoring.overallVoiceScore;
    return report;
  }

  // src/device-entry.js
  function analyze(samples, transcriptJSON) {
    const config = configuration();
    const acoustic = analyzeAcoustics(new Float32Array(samples), config);
    if (transcriptJSON === null) {
      return JSON.stringify({
        analysisVersion: "device-acoustics-1",
        overallVoiceScore: null,
        ...acoustic,
        scoring: scoreVoiceMetrics(acoustic.metrics, config)
      }, null, 2);
    }
    const report = buildAppleReport(JSON.parse(transcriptJSON), acoustic, config);
    report.execution = {
      runtime: "on_device",
      audioDecoder: "AVFoundation",
      signalProcessing: "JavaScriptCore",
      pitchDetector: "Pitchy 4.1.0",
      scoringVersion: report.scoring.version
    };
    return JSON.stringify(report, null, 2);
  }
  function score(metricsJSON) {
    return JSON.stringify(scoreVoiceMetrics(JSON.parse(metricsJSON)));
  }
  return __toCommonJS(device_entry_exports);
})();
