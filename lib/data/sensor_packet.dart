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

    Map<String, dynamic> toJson(String uid) => {
        "user_id": uid,
        "heart_rate": heartRate,
        "hrv": hrv,
        "temp": temp,
        "motion": motion,
        "sleep_quality": sleepQuality,
        "sleep_time": sleepTime,
    };
}