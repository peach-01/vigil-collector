class SensorPacket {
    final double heartRate;
    final double hrv;
    final double temp;
    final double motion;
    final double sleepQuality;
    final double sleepTime;

    SensorPacket({
        required this.heartRate,
        required this.hrv,
        required this.temp,
        required this.motion,
        required this.sleepQuality,
        required this.sleepTime,
    });

    Map<String, dynamic> toJson(String wid) => {
        "wid": wid,
        "heart_rate": heartRate,
        "hrv": hrv,
        "temp": temp,
        "motion": motion,
        "sleep_quality": sleepQuality,
        "sleep_time": sleepTime,
    };

    factory SensorPacket.fromJson(Map<String, dynamic> json) {
      return SensorPacket(
        heartRate: (json["heart_rate"] ?? 0).toDouble(), 
        hrv: (json["hrv"] ?? 0).toDouble(), 
        temp: (json["temp"] ?? 0).toDouble(), 
        motion: (json["motion"] ?? 0).toDouble(), 
        sleepQuality: (json["sleep_quality"] ?? 0).toDouble(), 
        sleepTime: (json["sleep_time"] ?? 0).toDouble(),
      );
    }
}