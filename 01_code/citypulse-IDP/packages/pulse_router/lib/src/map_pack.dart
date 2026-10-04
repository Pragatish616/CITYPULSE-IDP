/// The compact binary map pack (PLAN.md M2.1, KNOWN_FLAWS F-06), read without
/// any JSON parsing.
///
/// Written by `scripts/build_packs.py`; the layout is documented there and
/// every length is checked here against the header, because a pack arrives as
/// a downloaded file and must never be trusted blindly (R-security: validate
/// with real checks, not `assert`).
///
/// All values are little-endian. `edge_id` equals the array index.
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:pulse_router/src/csr_graph.dart';

/// Thrown when a pack file is truncated, has the wrong magic number or
/// version, or disagrees with its siblings.
class MapPackFormatException implements Exception {
  /// Creates the exception.
  MapPackFormatException(this.message);

  /// What was wrong.
  final String message;

  @override
  String toString() => 'MapPackFormatException: $message';
}

/// A parsed map pack: the routing graph plus per-edge data and node
/// coordinates.
class MapPack {
  MapPack._({
    required this.graph,
    required this.nodeCount,
    required this.edgeCount,
    required this.edgeFrom,
    required this.edgeTo,
    required this.edgeFreeFlowSeconds,
    required this.edgeFreeFlowKmh,
    required this.nodeLat,
    required this.nodeLon,
    required this.priorMilli,
    required this.priorScale,
    required this.nameIndex,
    required this.highwayCode,
    required this.names,
  });

  /// Parses the three pack files. Throws [MapPackFormatException] on any
  /// inconsistency.
  factory MapPack.parse({
    required ByteData graph,
    required ByteData nodes,
    required ByteData meta,
  }) {
    // ---- graph.bin ------------------------------------------------------
    _expectMagic(graph, 'CPG1', 'graph.bin');
    _expectVersion(graph, 'graph.bin');
    final nodeCount = graph.getUint32(8, Endian.little);
    final edgeCount = graph.getUint32(12, Endian.little);
    final graphExpected = 16 + 20 * edgeCount;
    if (graph.lengthInBytes != graphExpected) {
      throw MapPackFormatException(
        'graph.bin is ${graph.lengthInBytes} bytes, expected $graphExpected '
        'for $edgeCount edges',
      );
    }
    final from = _int32(graph, 16, edgeCount);
    final to = _int32(graph, 16 + 4 * edgeCount, edgeCount);
    final seconds = _float64(graph, 16 + 8 * edgeCount, edgeCount);
    final kmh = _float32AsDouble(graph, 16 + 16 * edgeCount, edgeCount);

    // ---- nodes.bin ------------------------------------------------------
    _expectMagic(nodes, 'CPN1', 'nodes.bin');
    _expectVersion(nodes, 'nodes.bin');
    final nodesInFile = nodes.getUint32(8, Endian.little);
    if (nodesInFile != nodeCount) {
      throw MapPackFormatException(
        'nodes.bin has $nodesInFile nodes, graph.bin has $nodeCount',
      );
    }
    final nodesExpected = 16 + 16 * nodeCount;
    if (nodes.lengthInBytes != nodesExpected) {
      throw MapPackFormatException(
        'nodes.bin is ${nodes.lengthInBytes} bytes, expected $nodesExpected',
      );
    }
    final lat = _float64(nodes, 16, nodeCount);
    final lon = _float64(nodes, 16 + 8 * nodeCount, nodeCount);

    // ---- meta.bin -------------------------------------------------------
    _expectMagic(meta, 'CPM1', 'meta.bin');
    _expectVersion(meta, 'meta.bin');
    final metaEdges = meta.getUint32(8, Endian.little);
    final nameCount = meta.getUint32(12, Endian.little);
    final scale = meta.getUint32(16, Endian.little);
    if (metaEdges != edgeCount) {
      throw MapPackFormatException(
        'meta.bin has $metaEdges edges, graph.bin has $edgeCount',
      );
    }
    if (scale == 0) throw MapPackFormatException('meta.bin prior scale is 0');
    final prior = _int16(meta, 20, edgeCount);
    final nameIdx = _uint16(meta, 20 + 2 * edgeCount, edgeCount);
    final hwy = _uint8(meta, 20 + 4 * edgeCount, edgeCount);
    var cursor = 20 + 5 * edgeCount;
    cursor += (4 - cursor % 4) % 4;
    final offsetsBytes = 4 * (nameCount + 1);
    if (cursor + offsetsBytes > meta.lengthInBytes) {
      throw MapPackFormatException('meta.bin is truncated in the name table');
    }
    final offsets = [
      for (var i = 0; i <= nameCount; i++)
        meta.getUint32(cursor + 4 * i, Endian.little),
    ];
    final textStart = cursor + offsetsBytes;
    if (textStart + offsets.last != meta.lengthInBytes) {
      throw MapPackFormatException(
        'meta.bin name text is ${meta.lengthInBytes - textStart} bytes, '
        'expected ${offsets.last}',
      );
    }
    final text = meta.buffer.asUint8List(
      meta.offsetInBytes + textStart,
      offsets.last,
    );
    final names = [
      for (var i = 0; i < nameCount; i++)
        utf8.decode(text.sublist(offsets[i], offsets[i + 1])),
    ];
    for (var i = 0; i < edgeCount; i++) {
      if (nameIdx[i] >= nameCount) {
        throw MapPackFormatException('edge $i has name index ${nameIdx[i]}');
      }
    }

    final csr = CsrGraph.fromArrays(
      nodeCount: nodeCount,
      from: from,
      to: to,
      freeFlowSeconds: seconds,
      freeFlowKmh: kmh,
    );
    return MapPack._(
      graph: csr,
      nodeCount: nodeCount,
      edgeCount: edgeCount,
      edgeFrom: from,
      edgeTo: to,
      edgeFreeFlowSeconds: seconds,
      edgeFreeFlowKmh: kmh,
      nodeLat: lat,
      nodeLon: lon,
      priorMilli: prior,
      priorScale: scale,
      nameIndex: nameIdx,
      highwayCode: hwy,
      names: names,
    );
  }

  /// The routing graph.
  final CsrGraph graph;

  /// Number of nodes.
  final int nodeCount;

  /// Number of directed edges. `edge_id` is the index in `[0, edgeCount)`.
  final int edgeCount;

  /// Source node of each edge.
  final Int32List edgeFrom;

  /// Target node of each edge.
  final Int32List edgeTo;

  /// Free-flow travel time of each edge, seconds.
  final Float64List edgeFreeFlowSeconds;

  /// Free-flow (car) speed of each edge, km/h. With [edgeFreeFlowSeconds] it
  /// gives the edge length in metres: `seconds * km/h / 3.6`.
  final List<double> edgeFreeFlowKmh;

  /// Node latitudes, degrees.
  final Float64List nodeLat;

  /// Node longitudes, degrees.
  final Float64List nodeLon;

  /// Per-edge static prior log-odds in units of `1 / priorScale`.
  final Int16List priorMilli;

  /// Divisor for [priorMilli] (1000 in the current pack).
  final int priorScale;

  /// Index into [names] for each edge; `0` means unnamed.
  final Uint16List nameIndex;

  /// Highway class code for each edge (see the pack manifest).
  final Uint8List highwayCode;

  /// Distinct street names; index `0` is the empty string.
  final List<String> names;

  /// `ℓ0(e)`: the static prior log-odds of [edgeId].
  double priorLogOdds(int edgeId) => priorMilli[edgeId] / priorScale;

  /// The OSM street name of [edgeId], or `null` if it has none.
  String? streetName(int edgeId) {
    final i = nameIndex[edgeId];
    return i == 0 ? null : names[i];
  }

  static void _expectMagic(ByteData d, String magic, String file) {
    if (d.lengthInBytes < 16) {
      throw MapPackFormatException('$file is too short to be a pack file');
    }
    for (var i = 0; i < 4; i++) {
      if (d.getUint8(i) != magic.codeUnitAt(i)) {
        throw MapPackFormatException('$file does not start with "$magic"');
      }
    }
  }

  static void _expectVersion(ByteData d, String file) {
    final v = d.getUint32(4, Endian.little);
    if (v != 1) {
      throw MapPackFormatException('$file has unsupported version $v');
    }
  }

  static Int32List _int32(ByteData d, int offset, int n) {
    final out = Int32List(n);
    for (var i = 0; i < n; i++) {
      out[i] = d.getInt32(offset + 4 * i, Endian.little);
    }
    return out;
  }

  static Int16List _int16(ByteData d, int offset, int n) {
    final out = Int16List(n);
    for (var i = 0; i < n; i++) {
      out[i] = d.getInt16(offset + 2 * i, Endian.little);
    }
    return out;
  }

  static Uint16List _uint16(ByteData d, int offset, int n) {
    final out = Uint16List(n);
    for (var i = 0; i < n; i++) {
      out[i] = d.getUint16(offset + 2 * i, Endian.little);
    }
    return out;
  }

  static Uint8List _uint8(ByteData d, int offset, int n) {
    final out = Uint8List(n);
    for (var i = 0; i < n; i++) {
      out[i] = d.getUint8(offset + i);
    }
    return out;
  }

  static Float64List _float64(ByteData d, int offset, int n) {
    final out = Float64List(n);
    for (var i = 0; i < n; i++) {
      out[i] = d.getFloat64(offset + 8 * i, Endian.little);
    }
    return out;
  }

  static Float64List _float32AsDouble(ByteData d, int offset, int n) {
    final out = Float64List(n);
    for (var i = 0; i < n; i++) {
      out[i] = d.getFloat32(offset + 4 * i, Endian.little);
    }
    return out;
  }
}
