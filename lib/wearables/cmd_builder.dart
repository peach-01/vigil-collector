import 'package:flutter/foundation.dart';
import 'package:vigil_collector/logger.dart';

class CommandBuilder {
  static Uint8List packet(int type, List<int> payload) {
    final len = payload.length + 1;
    final data = <int>[0x78, len, type, ...payload];

    int checksum = 0;
    for (final d in data) {
      checksum ^= d;
    }

    data.add(checksum & 0xFF);
    logStep("CMD BLDR", "Wrote data packet: $data");
    return Uint8List.fromList(data);
  }

  // REAL COMMANDS
  static Uint8List startRealTimeHR()  => packet(0x28, [0x01]);
  static Uint8List stopRealTimeHR()   => packet(0x28, [0x02]);
  static Uint8List holdRealTimeHR()   => packet(0x28, [0x03]);
}