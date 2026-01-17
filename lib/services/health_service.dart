import 'package:health/health.dart';

class HealthService {
  final Health _health = Health();

  Future<bool> requestWeightAuthorization({required bool write}) async {
    final types = [HealthDataType.WEIGHT];
    final permissions = [
      write ? HealthDataAccess.READ_WRITE : HealthDataAccess.READ,
    ];
    return _health.requestAuthorization(types, permissions: permissions);
  }

  Future<bool> requestBloodPressureAuthorization({required bool write}) async {
    final types = [
      HealthDataType.BLOOD_PRESSURE_SYSTOLIC,
      HealthDataType.BLOOD_PRESSURE_DIASTOLIC,
    ];
    final permissions = [
      write ? HealthDataAccess.READ_WRITE : HealthDataAccess.READ,
      write ? HealthDataAccess.READ_WRITE : HealthDataAccess.READ,
    ];
    return _health.requestAuthorization(types, permissions: permissions);
  }

  Future<bool> requestPulseAuthorization() async {
    final types = [HealthDataType.HEART_RATE];
    return _health.requestAuthorization(
      types,
      permissions: [HealthDataAccess.READ],
    );
  }

  Future<bool> requestStepsAuthorization() async {
    final types = [HealthDataType.STEPS];
    return _health.requestAuthorization(
      types,
      permissions: [HealthDataAccess.READ],
    );
  }

  Future<double?> fetchLatestWeight(DateTime date) async {
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    final data = await _health.getHealthDataFromTypes(
      types: [HealthDataType.WEIGHT],
      startTime: start,
      endTime: end,
    );
    if (data.isEmpty) return null;
    data.sort((a, b) => a.dateTo.compareTo(b.dateTo));
    final value = data.last.value;
    if (value is NumericHealthValue) {
      return value.numericValue.toDouble();
    }
    return null;
  }

  Future<void> writeWeight(double weight, DateTime date) async {
    await _health.writeHealthData(
      value: weight,
      type: HealthDataType.WEIGHT,
      startTime: date,
      endTime: date,
    );
  }

  Future<BloodPressureResult?> fetchLatestBloodPressure(DateTime date) async {
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    final systolic = await _health.getHealthDataFromTypes(
      types: [HealthDataType.BLOOD_PRESSURE_SYSTOLIC],
      startTime: start,
      endTime: end,
    );
    final diastolic = await _health.getHealthDataFromTypes(
      types: [HealthDataType.BLOOD_PRESSURE_DIASTOLIC],
      startTime: start,
      endTime: end,
    );
    if (systolic.isEmpty || diastolic.isEmpty) return null;
    systolic.sort((a, b) => a.dateTo.compareTo(b.dateTo));
    diastolic.sort((a, b) => a.dateTo.compareTo(b.dateTo));
    final systolicValue = systolic.last.value;
    final diastolicValue = diastolic.last.value;
    if (systolicValue is NumericHealthValue &&
        diastolicValue is NumericHealthValue) {
      return BloodPressureResult(
        systolic: systolicValue.numericValue.toInt(),
        diastolic: diastolicValue.numericValue.toInt(),
      );
    }
    return null;
  }

  Future<void> writeBloodPressure({
    required int systolic,
    required int diastolic,
    required DateTime date,
  }) async {
    await _health.writeHealthData(
      value: systolic.toDouble(),
      type: HealthDataType.BLOOD_PRESSURE_SYSTOLIC,
      startTime: date,
      endTime: date,
    );
    await _health.writeHealthData(
      value: diastolic.toDouble(),
      type: HealthDataType.BLOOD_PRESSURE_DIASTOLIC,
      startTime: date,
      endTime: date,
    );
  }

  Future<int?> fetchLatestPulse(DateTime date) async {
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    final data = await _health.getHealthDataFromTypes(
      types: [HealthDataType.HEART_RATE],
      startTime: start,
      endTime: end,
    );
    if (data.isEmpty) return null;
    data.sort((a, b) => a.dateTo.compareTo(b.dateTo));
    final value = data.last.value;
    if (value is NumericHealthValue) {
      return value.numericValue.toInt();
    }
    return null;
  }

  Future<int?> fetchTodaySteps(DateTime date) async {
    final start = DateTime(date.year, date.month, date.day);
    final end = start.add(const Duration(days: 1));
    final data = await _health.getHealthDataFromTypes(
      types: [HealthDataType.STEPS],
      startTime: start,
      endTime: end,
    );
    if (data.isEmpty) return null;
    var total = 0.0;
    for (final point in data) {
      final value = point.value;
      if (value is NumericHealthValue) {
        total += value.numericValue;
      }
    }
    return total.toInt();
  }
}

class BloodPressureResult {
  BloodPressureResult({required this.systolic, required this.diastolic});

  final int systolic;
  final int diastolic;
}
