// lib/utils/wav_to_pcm.dart
import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

class WavParseResult {
  final Uint8List pcm16;
  final int sampleRate;
  final int channels;
  WavParseResult({required this.pcm16, required this.sampleRate, required this.channels});
}

/// Read a .wav file and return signed 16-bit little-endian PCM samples.
/// - If the WAV is 16-bit PCM, the function extracts samples and optionally mixes to mono.
/// - If the WAV is 8-bit PCM, it converts to 16-bit signed PCM.
/// - If the WAV is not PCM (e.g. compressed), returns null.
Future<WavParseResult?> extractPcm16FromWav(File wavFile, {bool forceMono = true}) async {
  final bytes = await wavFile.readAsBytes();
  final buf = bytes.buffer;
  final b = ByteData.view(buf);

  int readU32(int offset) => b.getUint32(offset, Endian.little);
  int readU16(int offset) => b.getUint16(offset, Endian.little);
  int readS8(int offset) => b.getInt8(offset);
  int readU8(int offset) => b.getUint8(offset);

  // Minimal header checks
  if (bytes.length < 44) return null;
  final riff = String.fromCharCodes(bytes.sublist(0, 4));
  final wave = String.fromCharCodes(bytes.sublist(8, 12));
  if (riff != 'RIFF' || wave != 'WAVE') return null;

  // Walk chunks to find fmt and data
  int offset = 12;
  int audioFormat = -1;
  int numChannels = 0;
  int sampleRate = 0;
  int bitsPerSample = 0;
  int dataStart = -1;
  int dataLen = 0;

  while (offset + 8 <= bytes.length) {
    final chunkId = String.fromCharCodes(bytes.sublist(offset, offset + 4));
    final chunkSize = readU32(offset + 4);
    final chunkDataStart = offset + 8;

    if (chunkDataStart + chunkSize > bytes.length) break; // malformed

    if (chunkId == 'fmt ') {
      // parse fmt chunk (PCM format)
      if (chunkSize < 16) return null;
      audioFormat = readU16(offset + 8); // 1 = PCM, 3 = IEEE float, etc.
      numChannels = readU16(offset + 10);
      sampleRate = readU32(offset + 12);
      // skip byteRate (4) and blockAlign(2)
      bitsPerSample = readU16(offset + 22);
    } else if (chunkId == 'data') {
      dataStart = chunkDataStart;
      dataLen = chunkSize;
      break; // data usually last, we can exit
    }

    // chunk sizes are word-aligned (pad if odd)
    offset = chunkDataStart + chunkSize + (chunkSize.isOdd ? 1 : 0);
  }

  if (dataStart < 0 || audioFormat < 0) return null;

  // Accept PCM (1) or 8-bit PCM (format 1 with bitsPerSample 8 or 16).
  if (audioFormat != 1) {
    // Not PCM. caller should use FFmpeg to convert.
    return null;
  }

  // Extract samples
  final data = bytes.sublist(dataStart, dataStart + dataLen);

  // Helper to convert 8-bit unsigned PCM -> 16-bit signed
  int _u8ToS16(int u8) => ((u8 - 128) << 8);

  // If 16-bit PCM:
  if (bitsPerSample == 16) {
    // If mono required and file is stereo, downmix by averaging samples
    if (forceMono && numChannels == 2) {
      final frameCount = dataLen ~/ 4; // 4 bytes per frame (2channels * 2 bytes)
      final out = BytesBuilder(copy: false);
      final view = ByteData.view(data.buffer, data.offsetInBytes, data.length);
      for (int i = 0; i < frameCount; i++) {
        final sL = view.getInt16(i * 4, Endian.little);
        final sR = view.getInt16(i * 4 + 2, Endian.little);
        final mono = ((sL + sR) ~/ 2);
        // write int16 little-endian
        out.addByte(mono & 0xFF);
        out.addByte((mono >> 8) & 0xFF);
      }
      final pcm = out.toBytes();
      return WavParseResult(pcm16: Uint8List.fromList(pcm), sampleRate: sampleRate, channels: 1);
    } else {
      // if not forcing mono, or already mono, just return data (ensure even length)
      final pcm = (data.length % 2 == 0) ? data : (Uint8List.fromList([...data, 0]));
      return WavParseResult(pcm16: Uint8List.fromList(pcm), sampleRate: sampleRate, channels: numChannels);
    }
  }

  // If 8-bit PCM, convert to 16-bit signed LE
  if (bitsPerSample == 8) {
    final out = BytesBuilder(copy: false);
    if (numChannels == 1) {
      for (int i = 0; i < data.length; i++) {
        final s16 = _u8ToS16(data[i]);
        out.addByte(s16 & 0xFF);
        out.addByte((s16 >> 8) & 0xFF);
      }
      final pcm = out.toBytes();
      return WavParseResult(pcm16: Uint8List.fromList(pcm), sampleRate: sampleRate, channels: 1);
    } else if (numChannels == 2) {
      // convert stereo uint8 -> mono int16 by averaging
      final frameCount = data.length ~/ 2;
      final view = data;
      for (int i = 0; i < frameCount; i++) {
        final uL = view[i * 2];
        final uR = view[i * 2 + 1];
        final s16L = _u8ToS16(uL);
        final s16R = _u8ToS16(uR);
        final mono = ((s16L + s16R) ~/ 2);
        out.addByte(mono & 0xFF);
        out.addByte((mono >> 8) & 0xFF);
      }
      final pcm = out.toBytes();
      return WavParseResult(pcm16: Uint8List.fromList(pcm), sampleRate: sampleRate, channels: 1);
    }
  }

  // Unsupported bitsPerSample
  return null;
}
