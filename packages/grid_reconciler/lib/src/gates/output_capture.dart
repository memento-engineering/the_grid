import 'dart:convert';

/// Maximum size of captured gate stdout/stderr — **bytes only, per stream**.
/// Byte-faithful to `MaxOutputBytes` (capture.go:13). There is **no** line
/// limit (gates-exec.md §6).
const int maxOutputBytes = 4096;

/// `utf8.UTFMax` — the longest UTF-8 encoding (4 bytes). The capture buffer is
/// sized `maxOutputBytes + utf8UtfMax` so truncation can detect overflow and
/// trim to a rune boundary (condition.go:334-335).
const int utf8UtfMax = 4;

/// Capture-buffer ceiling: `4096 + 4 = 4100` bytes per stream
/// (condition.go:334-335). The bounded sink discards beyond this; the runner
/// then [truncateOutput]s the captured slice down to [maxOutputBytes].
const int captureBufferBytes = maxOutputBytes + utf8UtfMax;

/// A byte sink that stores at most [maxBytes]; once full, further bytes are
/// **silently discarded** while the stream keeps flowing (so the child process
/// never sees a closed pipe / broken write). Sets [overflowed] when any byte is
/// dropped.
///
/// Port of gc's `boundedBuffer` (capture.go:17-43): its `Write` returns
/// `(len(p), nil)` past the cap — it *lies* to the writer so a chatty gate
/// script cannot get an EPIPE-like failure mid-write (gates-exec.md trap #7). In
/// Dart we achieve the same by consuming the whole stream but only retaining
/// [maxBytes].
class BoundedByteSink {
  BoundedByteSink(this.maxBytes) : assert(maxBytes >= 0);

  /// The retention cap in bytes (the runner passes [captureBufferBytes]).
  final int maxBytes;

  final List<int> _buf = <int>[];
  bool _overflow = false;

  /// The retained bytes (≤ [maxBytes]).
  List<int> get bytes => _buf;

  /// True once any byte has been dropped past the cap.
  bool get overflowed => _overflow;

  /// Appends [chunk], retaining bytes up to [maxBytes] and flagging overflow for
  /// the rest — mirrors `boundedBuffer.Write` (capture.go:27-40).
  void add(List<int> chunk) {
    final remaining = maxBytes - _buf.length;
    if (remaining <= 0) {
      if (chunk.isNotEmpty) _overflow = true;
      return;
    }
    if (chunk.length > remaining) {
      _buf.addAll(chunk.take(remaining));
      _overflow = true;
    } else {
      _buf.addAll(chunk);
    }
  }

  /// Drains [stream] into this sink, never propagating a write error back to
  /// the producer (the discard-but-succeed contract). Completes when the stream
  /// closes.
  Future<void> addStream(Stream<List<int>> stream) =>
      stream.forEach(add).catchError((_) {});
}

/// Truncates captured bytes to [maxBytes], returning `(string, truncated)`.
///
/// Byte-faithful port of `TruncateOutput` (capture.go:47-69):
///
/// * `maxBytes <= 0` ⇒ `('', false)` for empty input, `('', true)` otherwise.
/// * `data.length <= maxBytes` ⇒ `(decode(data), false)`.
/// * else back `end` off from [maxBytes] by at most `utf8UtfMax - 1 = 3` bytes
///   (while `end > maxBytes - utf8UtfMax`) until a UTF-8 **rune start** byte —
///   so a multi-byte rune is never split. Binary garbage elsewhere in the slice
///   is preserved as-is. Returns `(decode(data[:end]), true)`.
///
/// Decoding is lossy UTF-8 (Go's `string([]byte)` keeps invalid bytes; Dart's
/// closest faithful read is `allowMalformed`, which the rune-boundary backoff
/// keeps off the truncation seam).
({String text, bool truncated}) truncateOutput(List<int> data, int maxBytes) {
  if (maxBytes <= 0) {
    return data.isEmpty
        ? (text: '', truncated: false)
        : (text: '', truncated: true);
  }
  if (data.length <= maxBytes) {
    return (text: _decode(data), truncated: false);
  }
  var end = maxBytes;
  while (end > 0 && end > maxBytes - utf8UtfMax) {
    if (_isRuneStart(data[end])) break;
    end--;
  }
  return (text: _decode(data.sublist(0, end)), truncated: true);
}

/// Go's `utf8.RuneStart(b)`: a byte is a rune start unless it is a UTF-8
/// continuation byte (`0b10xxxxxx`, i.e. `b & 0xC0 == 0x80`).
bool _isRuneStart(int b) => (b & 0xC0) != 0x80;

String _decode(List<int> bytes) =>
    const Utf8Decoder(allowMalformed: true).convert(bytes);
